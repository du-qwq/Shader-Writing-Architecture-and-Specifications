#ifndef FLOWER_CLOUD_DENSITY_COMMON_INCLUDED
#define FLOWER_CLOUD_DENSITY_COMMON_INCLUDED

// ============================================================
// Flower cloudMap0 / cloudMap1 / cloudMap2
// Faithful HLSL port of:
// qiutang98/flower/dark/install/shader/cloud_render_common.glsl
//
// Unity adaptations only:
// 1. GLSL texture(...) -> HLSL Texture.SampleLevel(..., 0)
// 2. frameData.cloud.* -> Unity material / compute parameters
// 3. Basic/detail scale use the X component as the original scalar scale
// ============================================================

float FlowerDensityRemap(
    float value,
    float sourceMinimum,
    float sourceMaximum,
    float targetMinimum,
    float targetMaximum)
{
    float sourceRange = sourceMaximum - sourceMinimum;

    if (abs(sourceRange) < 0.000001)
    {
        return targetMinimum;
    }

    float normalizedValue = (value - sourceMinimum) / sourceRange;
    return normalizedValue * (targetMaximum - targetMinimum) + targetMinimum;
}

float FlowerSampleBasicNoise(float3 uvw)
{
    return _FlowerCloudBasicNoise.SampleLevel(
        sampler_FlowerCloudBasicNoise,
        frac(uvw),
        0.0
    ).r;
}

float FlowerSampleDetailNoise(float3 uvw)
{
    return _FlowerCloudDetailNoise.SampleLevel(
        sampler_FlowerCloudDetailNoise,
        frac(uvw),
        0.0
    ).r;
}

float FlowerSampleWeather(float2 uv)
{
    return _FlowerCloudWeather.SampleLevel(
        sampler_FlowerCloudWeather,
        frac(uv),
        0.0
    ).r;
}

float3 FlowerSampleCurl(float2 uv)
{
    float3 curl = _FlowerCloudCurl.SampleLevel(
        sampler_FlowerCloudCurl,
        frac(uv),
        0.0
    ).xyz;

    return curl * 2.0 - 1.0;
}

float FlowerSampleCoverageNoise(float2 uv)
{
    return _FlowerCloudCoverageNoise.SampleLevel(
        sampler_FlowerCloudCoverageNoise,
        frac(uv),
        0.0
    ).r;
}

float3 FlowerGetWindDirection()
{
    float3 direction = _CloudDirection.xyz;

    if (dot(direction, direction) < 0.000001)
    {
        return float3(1.0, 0.0, 0.0);
    }

    // Flower assumes this value is already a direction.
    return direction;
}

float FlowerGetBasicNoiseScale()
{
    // The original project uses one scalar for XYZ.
    return max(abs(_CloudBasicNoiseScale.x), 0.000001);
}

float FlowerGetDetailNoiseScale()
{
    // The original project uses one scalar for XYZ.
    return max(abs(_CloudDetailNoiseScale.x), 0.000001);
}

// ------------------------------------------------------------
// Original Flower low cloud layer.
// Whole cloud-area normalized height range: 0.0 - 0.4
// Approximate physical range in the original project: 500 - 3000 m.
// ------------------------------------------------------------
float FlowerCloudMap0(float3 positionMeter, float normalizedHeight)
{
    const float coverageBase = 0.5;

    float densityScale = _CloudDensity * 2.0;
    float3 windDirection = FlowerGetWindDirection();
    float cloudSpeed = _CloudSpeed;

    positionMeter += windDirection * normalizedHeight * 500.0;

    float3 positionKm = positionMeter * 0.001;
    float animationOffset = _Time.y * cloudSpeed * 50.0;

    float2 curlUV =
        (animationOffset + positionMeter.xz) *
        0.0000008 +
        0.7;

    float3 curl = FlowerSampleCurl(curlUV);
    positionKm += curl * 2.0;

    float3 windOffset =
        (windDirection + float3(0.0, 0.1, 0.0)) *
        _Time.y *
        cloudSpeed;

    float2 weatherUV =
        positionKm.xz *
        _CloudWeatherUVScale;

    float weatherValue =
        FlowerSampleWeather(weatherUV);

    float2 localCoverageUV =
        (animationOffset + positionMeter.xz) *
        0.000001 +
        0.5;

    float localCoverage =
        FlowerSampleCoverageNoise(localCoverageUV);

    localCoverage =
        saturate(localCoverage * 3.0 - 0.75) *
        0.2;

    float coverage =
        saturate(
            coverageBase *
            (localCoverage + weatherValue)
        );

    float gradientShape =
        FlowerDensityRemap(
            normalizedHeight,
            0.10,
            0.80,
            _CloudCoverage * 1.9,
            0.2
        ) *
        FlowerDensityRemap(
            normalizedHeight,
            0.00,
            0.10,
            0.5,
            1.0
        );

    float basicScale = FlowerGetBasicNoiseScale();

    float3 basicUVW =
        (positionKm + windOffset) *
        basicScale;

    float basicNoise =
        FlowerSampleBasicNoise(basicUVW);

    float basicCloudNoise =
        gradientShape *
        basicNoise;

    float basicCloudWithCoverage =
        coverage *
        FlowerDensityRemap(
            basicCloudNoise,
            1.0 - coverage,
            1.0,
            0.0,
            1.0
        );

    float3 detailPosition =
        positionKm -
        windOffset * 0.15;

    float detailScale =
        FlowerGetDetailNoiseScale();

    float detailNoiseComposite =
        FlowerSampleDetailNoise(
            detailPosition *
            detailScale
        );

    float detailNoiseMixByHeight =
        0.2 *
        lerp(
            detailNoiseComposite,
            1.0 - detailNoiseComposite,
            saturate(normalizedHeight * 10.0)
        );

    float densityShape =
        saturate(
            0.01 +
            (1.0 - normalizedHeight) *
            0.5
        ) *
        0.25 *
        FlowerDensityRemap(
            normalizedHeight,
            0.0,
            0.3,
            0.0,
            1.0
        ) *
        FlowerDensityRemap(
            normalizedHeight,
            0.7,
            1.0,
            1.0,
            0.0
        );

    float cloudDensity =
        densityShape *
        FlowerDensityRemap(
            basicCloudWithCoverage,
            detailNoiseMixByHeight,
            1.0,
            0.0,
            1.0
        );

    cloudDensity =
        pow(
            max(cloudDensity, 0.0),
            saturate(1.0 - normalizedHeight) *
            0.4 +
            0.1
        ) *
        densityScale *
        0.1;

    return saturate(cloudDensity);
}

// ------------------------------------------------------------
// Original Flower middle cloud layer.
// Whole cloud-area normalized height range: 0.4 - 0.8
// Approximate physical range in the original project: 3000 - 7000 m.
// ------------------------------------------------------------
float FlowerCloudMap1(float3 positionMeter, float normalizedHeight)
{
    float coverageBase =
        saturate(_CloudCoverage);

    float densityScale =
        _CloudDensity *
        0.35;

    float3 windDirection =
        FlowerGetWindDirection();

    float cloudSpeed =
        _CloudSpeed;

    positionMeter +=
        windDirection *
        normalizedHeight *
        500.0;

    float3 positionKm =
        positionMeter *
        0.001;

    float animationOffset =
        _Time.y *
        cloudSpeed *
        50.0;

    float2 curlUV =
        (animationOffset + positionMeter.xz) *
        0.000001 -
        0.3;

    float3 curl =
        FlowerSampleCurl(curlUV);

    positionKm +=
        curl *
        5.0;

    float3 windOffset =
        (windDirection + float3(0.0, 0.1, 0.0)) *
        _Time.y *
        cloudSpeed;

    float2 weatherUV =
        positionKm.xz *
        _CloudWeatherUVScale *
        0.5 +
        0.39;

    weatherUV.y *=
        2.0;

    float weatherValue =
        FlowerSampleWeather(weatherUV);

    float2 localCoverageUV =
        (animationOffset + positionMeter.xz) *
        0.000001 -
        0.11;

    float localCoverage =
        FlowerSampleCoverageNoise(localCoverageUV);

    localCoverage =
        saturate(localCoverage * 4.0 - 2.0) *
        0.5;

    float coverage =
        saturate(
            coverageBase *
            (localCoverage + weatherValue)
        );

    float gradientShape =
        FlowerDensityRemap(
            normalizedHeight,
            0.00,
            0.01,
            0.1,
            1.0
        ) *
        FlowerDensityRemap(
            normalizedHeight,
            0.10,
            0.80,
            0.7,
            0.2
        );

    float basicScale =
        FlowerGetBasicNoiseScale();

    float3 basicUVW =
        2.0 *
        (positionKm + windOffset) *
        basicScale;

    float basicNoise =
        FlowerSampleBasicNoise(basicUVW);

    float basicCloudNoise =
        gradientShape *
        basicNoise;

    float basicCloudWithCoverage =
        coverage *
        FlowerDensityRemap(
            basicCloudNoise,
            1.0 - coverage,
            1.0,
            0.0,
            1.0
        );

    float3 detailPosition =
        positionKm -
        windOffset * 0.15;

    float detailScale =
        FlowerGetDetailNoiseScale();

    float detailNoiseComposite =
        FlowerSampleDetailNoise(
            2.0 *
            detailPosition *
            detailScale
        );

    float detailNoiseMixByHeight =
        0.2 *
        lerp(
            detailNoiseComposite,
            1.0 - detailNoiseComposite,
            saturate(normalizedHeight * 10.0)
        );

    float densityShape =
        saturate(
            0.01 +
            (1.0 - normalizedHeight) *
            0.5
        ) *
        0.1 *
        FlowerDensityRemap(
            normalizedHeight,
            0.0,
            0.3,
            0.0,
            1.0
        ) *
        FlowerDensityRemap(
            normalizedHeight,
            0.7,
            1.0,
            1.0,
            0.0
        );

    float cloudDensity =
        densityShape *
        FlowerDensityRemap(
            basicCloudWithCoverage,
            detailNoiseMixByHeight,
            1.0,
            0.0,
            1.0
        );

    cloudDensity =
        pow(
            max(cloudDensity, 0.0),
            saturate(1.0 - normalizedHeight) *
            0.4 +
            0.1
        ) *
        densityScale *
        0.1;

    return saturate(cloudDensity);
}

// ------------------------------------------------------------
// Original Flower high cloud layer.
// Whole cloud-area normalized height range: 0.8 - 1.0
// Approximate physical range in the original project: 7000 - 11000 m.
// ------------------------------------------------------------
float FlowerCloudMap2(float3 positionMeter, float normalizedHeight)
{
    float coverageBase =
        _CloudCoverage *
        0.75;

    float densityScale =
        _CloudDensity *
        0.20;

    float3 windDirection =
        FlowerGetWindDirection();

    float cloudSpeed =
        _CloudSpeed;

    positionMeter +=
        windDirection *
        normalizedHeight *
        500.0;

    float3 positionKm =
        positionMeter *
        0.001;

    float animationOffset =
        _Time.y *
        cloudSpeed *
        50.0;

    float2 curlUV =
        (animationOffset + positionMeter.xz) *
        0.00000125 +
        0.7;

    float3 curl =
        FlowerSampleCurl(curlUV);

    positionKm +=
        curl *
        10.0;

    float3 windOffset =
        (windDirection + float3(0.0, 0.1, 0.0)) *
        _Time.y *
        cloudSpeed;

    float2 weatherUV =
        positionKm.xz *
        _CloudWeatherUVScale *
        0.6 +
        0.739;

    weatherUV.y *=
        6.0;

    float weatherValue =
        FlowerSampleWeather(weatherUV);

    float2 localCoverageUV =
        (animationOffset + positionMeter.xz) *
        0.000001 -
        0.39;

    float localCoverage =
        FlowerSampleCoverageNoise(localCoverageUV);

    localCoverage =
        saturate(
            1.0 -
            pow(localCoverage, 8.0)
        );

    float coverage =
        saturate(
            coverageBase *
            (localCoverage + weatherValue)
        );

    float gradientShape =
        FlowerDensityRemap(
            normalizedHeight,
            0.00,
            0.01,
            0.1,
            1.0
        ) *
        FlowerDensityRemap(
            normalizedHeight,
            0.10,
            0.20,
            0.8,
            0.5
        );

    float basicScale =
        FlowerGetBasicNoiseScale();

    float3 basicUVW =
        3.0 *
        (positionKm + windOffset + 0.39) *
        basicScale;

    float basicNoise =
        FlowerSampleBasicNoise(basicUVW);

    float basicCloudNoise =
        gradientShape *
        basicNoise;

    float basicCloudWithCoverage =
        coverage *
        FlowerDensityRemap(
            basicCloudNoise,
            1.0 - coverage,
            1.0,
            0.0,
            1.0
        );

    float densityShape =
        saturate(
            0.01 +
            (1.0 - normalizedHeight) *
            0.5
        ) *
        0.1 *
        FlowerDensityRemap(
            normalizedHeight,
            0.0,
            0.3,
            0.0,
            1.0
        ) *
        FlowerDensityRemap(
            normalizedHeight,
            0.7,
            1.0,
            1.0,
            0.0
        );

    float cloudDensity =
        densityShape *
        basicCloudWithCoverage;

    cloudDensity *=
        densityScale;

    return saturate(cloudDensity);
}

// ------------------------------------------------------------
// Original Flower layer split:
// 0.0 - 0.4 -> low cloud
// 0.4 - 0.8 -> middle cloud
// 0.8 - 1.0 -> high cloud
// ------------------------------------------------------------
float FlowerCloudMap(
    float3 positionMeter,
    float normalizedHeight,
    out float actualHeight01,
    out int layerIndex)
{
    normalizedHeight =
        saturate(normalizedHeight);

    actualHeight01 = 0.0;
    layerIndex = 0;

    if (normalizedHeight < 0.4)
    {
        layerIndex = 0;
        actualHeight01 =
            normalizedHeight /
            0.4;

        return FlowerCloudMap0(
            positionMeter,
            actualHeight01
        );
    }

    if (normalizedHeight < 0.8)
    {
        layerIndex = 1;
        actualHeight01 =
            (normalizedHeight - 0.4) /
            0.4;

        return FlowerCloudMap1(
            positionMeter,
            actualHeight01
        );
    }

    layerIndex = 2;
    actualHeight01 =
        (normalizedHeight - 0.8) /
        0.2;

    return FlowerCloudMap2(
        positionMeter,
        actualHeight01
    );
}

#endif
