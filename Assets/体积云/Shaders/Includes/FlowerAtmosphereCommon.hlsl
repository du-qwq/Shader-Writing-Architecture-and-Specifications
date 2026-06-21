#ifndef FLOWER_ATMOSPHERE_COMMON_INCLUDED
#define FLOWER_ATMOSPHERE_COMMON_INCLUDED

#define FLOWER_ATMOSPHERE_PI 3.14159265358979323846
#define FLOWER_ATMOSPHERE_MAX_STEPS 64
#define FLOWER_ATMOSPHERE_MAX_DIRECTIONS 64

static const float FLOWER_ATMOSPHERE_UNIT_SCALE = 1000.0;
static const float FLOWER_ATMOSPHERE_CAMERA_OFFSET_KM = 0.021;
static const float FLOWER_AERIAL_PERSPECTIVE_KM_PER_SLICE = 4.0;
static const float FLOWER_DISTANT_GRID_KM_PER_SLICE = 4.0;
static const float FLOWER_DISTANT_SKY_LIT_MAX_METER = 16384.0;

float _AtmosphereBottomRadius;
float _AtmosphereTopRadius;
float _RayleighScaleHeight;
float _MieScaleHeight;
float _OzoneCenterHeight;
float _OzoneHalfWidth;

float3 _RayleighScattering;
float3 _MieScattering;
float3 _MieAbsorption;
float3 _OzoneAbsorption;
float3 _GroundAlbedo;

float _MultipleScatteringFactor;
float3 _AtmosphereSunDirection;
float3 _AtmosphereSunLuminance;

int _AtmosphereIntegrationSteps;
int _AtmosphereDirectionSamples;

float FlowerAerialPerspectiveDepthToSlice(float depthKm)
{
    return depthKm * (1.0 / FLOWER_AERIAL_PERSPECTIVE_KM_PER_SLICE);
}

float FlowerAerialPerspectiveSliceToDepth(float slice)
{
    return slice * FLOWER_AERIAL_PERSPECTIVE_KM_PER_SLICE;
}

float FlowerDistantGridDepthToSlice(float depthKm)
{
    return depthKm * (1.0 / FLOWER_DISTANT_GRID_KM_PER_SLICE);
}

float FlowerDistantGridSliceToDepth(float slice)
{
    return slice * FLOWER_DISTANT_GRID_KM_PER_SLICE;
}

float3 FlowerConvertToAtmosphereUnit(
    float3 cameraUnitPositionMeter,
    float bottomRadiusKm)
{
    return cameraUnitPositionMeter / FLOWER_ATMOSPHERE_UNIT_SCALE +
        float3(
            0.0,
            bottomRadiusKm + FLOWER_ATMOSPHERE_CAMERA_OFFSET_KM,
            0.0
        );
}

float3 FlowerConvertToCameraUnit(
    float3 atmospherePositionKm,
    float bottomRadiusKm)
{
    return (
        atmospherePositionKm -
        float3(
            0.0,
            bottomRadiusKm + FLOWER_ATMOSPHERE_CAMERA_OFFSET_KM,
            0.0
        )
    ) * FLOWER_ATMOSPHERE_UNIT_SCALE;
}

float2 FlowerAtmosphereRaySphere(
    float3 origin,
    float3 direction,
    float radius)
{
    float b = dot(origin, direction);
    float c = dot(origin, origin) - radius * radius;
    float discriminant = b * b - c;

    if (discriminant < 0.0)
    {
        return float2(-1.0, -1.0);
    }

    float root = sqrt(discriminant);
    return float2(-b - root, -b + root);
}

float FlowerAtmosphereDistanceToBoundary(
    float3 position,
    float3 direction)
{
    float2 topHit = FlowerAtmosphereRaySphere(
        position,
        direction,
        _AtmosphereTopRadius
    );

    if (topHit.y <= 0.0)
    {
        return 0.0;
    }

    float distanceToTop =
        topHit.x > 0.0
            ? topHit.x
            : topHit.y;

    float2 groundHit = FlowerAtmosphereRaySphere(
        position,
        direction,
        _AtmosphereBottomRadius
    );

    if (groundHit.x > 0.0)
    {
        return min(distanceToTop, groundHit.x);
    }

    if (groundHit.y > 0.0 &&
        length(position) < _AtmosphereBottomRadius)
    {
        return min(distanceToTop, groundHit.y);
    }

    return distanceToTop;
}

float FlowerAtmosphereRayleighDensity(float heightKm)
{
    return exp(
        -max(heightKm, 0.0) /
        max(_RayleighScaleHeight, 0.001)
    );
}

float FlowerAtmosphereMieDensity(float heightKm)
{
    return exp(
        -max(heightKm, 0.0) /
        max(_MieScaleHeight, 0.001)
    );
}

float FlowerAtmosphereOzoneDensity(float heightKm)
{
    float distanceFromCenter =
        abs(heightKm - _OzoneCenterHeight);

    return saturate(
        1.0 -
        distanceFromCenter /
        max(_OzoneHalfWidth, 0.001)
    );
}

void FlowerAtmosphereMedium(
    float3 positionKm,
    out float3 scattering,
    out float3 extinction,
    out float3 rayleighScattering,
    out float3 mieScattering)
{
    float heightKm =
        max(
            length(positionKm) -
            _AtmosphereBottomRadius,
            0.0
        );

    float rayleighDensity =
        FlowerAtmosphereRayleighDensity(heightKm);

    float mieDensity =
        FlowerAtmosphereMieDensity(heightKm);

    float ozoneDensity =
        FlowerAtmosphereOzoneDensity(heightKm);

    rayleighScattering =
        _RayleighScattering *
        rayleighDensity;

    mieScattering =
        _MieScattering *
        mieDensity;

    float3 mieExtinction =
        (_MieScattering + _MieAbsorption) *
        mieDensity;

    float3 ozoneExtinction =
        _OzoneAbsorption *
        ozoneDensity;

    scattering =
        rayleighScattering +
        mieScattering;

    extinction =
        rayleighScattering +
        mieExtinction +
        ozoneExtinction;
}

float FlowerAtmosphereRayleighPhase(float cosTheta)
{
    return
        3.0 /
        (16.0 * FLOWER_ATMOSPHERE_PI) *
        (1.0 + cosTheta * cosTheta);
}

float FlowerAtmosphereMiePhase(float cosTheta, float g)
{
    float g2 = g * g;

    float denominator =
        max(
            1.0 + g2 -
            2.0 * g * cosTheta,
            0.0001
        );

    return
        (1.0 - g2) /
        (
            4.0 *
            FLOWER_ATMOSPHERE_PI *
            denominator *
            sqrt(denominator)
        );
}

float2 FlowerAtmosphereTransmittanceUvFromParams(
    float radiusKm,
    float mu)
{
    float bottomRadius = _AtmosphereBottomRadius;
    float topRadius = _AtmosphereTopRadius;

    float H =
        sqrt(
            max(
                topRadius * topRadius -
                bottomRadius * bottomRadius,
                0.0
            )
        );

    float rho =
        sqrt(
            max(
                radiusKm * radiusKm -
                bottomRadius * bottomRadius,
                0.0
            )
        );

    float discriminant =
        radiusKm * radiusKm *
        (mu * mu - 1.0) +
        topRadius * topRadius;

    float distance =
        max(
            0.0,
            -radiusKm * mu +
            sqrt(max(discriminant, 0.0))
        );

    float distanceMin =
        topRadius - radiusKm;

    float distanceMax =
        rho + H;

    float xMu =
        (distance - distanceMin) /
        max(
            distanceMax - distanceMin,
            0.0001
        );

    float xRadius =
        rho /
        max(H, 0.0001);

    return saturate(
        float2(xMu, xRadius)
    );
}

void FlowerAtmosphereTransmittanceParamsFromUv(
    float2 uv,
    out float radiusKm,
    out float mu)
{
    float bottomRadius = _AtmosphereBottomRadius;
    float topRadius = _AtmosphereTopRadius;

    float H =
        sqrt(
            max(
                topRadius * topRadius -
                bottomRadius * bottomRadius,
                0.0
            )
        );

    float rho =
        H * saturate(uv.y);

    radiusKm =
        sqrt(
            rho * rho +
            bottomRadius * bottomRadius
        );

    float distanceMin =
        topRadius - radiusKm;

    float distanceMax =
        rho + H;

    float distance =
        lerp(
            distanceMin,
            distanceMax,
            saturate(uv.x)
        );

    if (distance <= 0.0001)
    {
        mu = 1.0;
    }
    else
    {
        mu =
            (
                H * H -
                rho * rho -
                distance * distance
            ) /
            max(
                2.0 *
                radiusKm *
                distance,
                0.0001
            );
    }

    mu = clamp(mu, -1.0, 1.0);
}

float3 FlowerAtmosphereIntegrateOpticalDepth(
    float3 originKm,
    float3 direction,
    float distanceKm,
    int stepCount)
{
    stepCount =
        clamp(
            stepCount,
            1,
            FLOWER_ATMOSPHERE_MAX_STEPS
        );

    float stepLengthKm =
        distanceKm /
        stepCount;

    float currentDistanceKm =
        stepLengthKm * 0.5;

    float3 opticalDepth = 0.0;

    [loop]
    for (int index = 0;
         index < FLOWER_ATMOSPHERE_MAX_STEPS;
         index++)
    {
        if (index >= stepCount)
        {
            break;
        }

        float3 samplePositionKm =
            originKm +
            direction *
            currentDistanceKm;

        float3 scattering;
        float3 extinction;
        float3 rayleighScattering;
        float3 mieScattering;

        FlowerAtmosphereMedium(
            samplePositionKm,
            scattering,
            extinction,
            rayleighScattering,
            mieScattering
        );

        opticalDepth +=
            extinction *
            stepLengthKm;

        currentDistanceKm +=
            stepLengthKm;
    }

    return opticalDepth;
}

float3 FlowerAtmosphereSampleTransmittance(
    Texture2D<float4> transmittanceTexture,
    SamplerState transmittanceSampler,
    float3 positionKm,
    float3 direction)
{
    float radiusKm =
        length(positionKm);

    float3 up =
        positionKm /
        max(radiusKm, 0.0001);

    float mu =
        dot(up, direction);

    float2 uv =
        FlowerAtmosphereTransmittanceUvFromParams(
            radiusKm,
            mu
        );

    return transmittanceTexture.SampleLevel(
        transmittanceSampler,
        uv,
        0.0
    ).rgb;
}

float2 FlowerAtmosphereMultiScatterUv(
    float radiusKm,
    float sunMu)
{
    float height01 =
        saturate(
            (
                radiusKm -
                _AtmosphereBottomRadius
            ) /
            max(
                _AtmosphereTopRadius -
                _AtmosphereBottomRadius,
                0.001
            )
        );

    return float2(
        sunMu * 0.5 + 0.5,
        height01
    );
}

float3 FlowerAtmosphereSampleMultiScatter(
    Texture2D<float4> multiScatterTexture,
    SamplerState multiScatterSampler,
    float3 positionKm,
    float3 sunDirection)
{
    float radiusKm =
        length(positionKm);

    float3 up =
        positionKm /
        max(radiusKm, 0.0001);

    float sunMu =
        dot(up, sunDirection);

    float2 uv =
        FlowerAtmosphereMultiScatterUv(
            radiusKm,
            sunMu
        );

    return multiScatterTexture.SampleLevel(
        multiScatterSampler,
        saturate(uv),
        0.0
    ).rgb;
}

float3 FlowerAtmosphereUniformSphereDirection(
    uint index,
    uint count)
{
    float u =
        (index + 0.5) /
        max((float)count, 1.0);

    float v =
        frac(
            (index + 0.5) *
            0.6180339887498949
        );

    float cosTheta =
        1.0 - 2.0 * u;

    float sinTheta =
        sqrt(
            saturate(
                1.0 -
                cosTheta * cosTheta
            )
        );

    float phi =
        2.0 *
        FLOWER_ATMOSPHERE_PI *
        v;

    return float3(
        cos(phi) * sinTheta,
        cosTheta,
        sin(phi) * sinTheta
    );
}

float3 FlowerAtmosphereCosineHemisphereDirection(
    uint index,
    uint count,
    float3 normal)
{
    float u =
        (index + 0.5) /
        max((float)count, 1.0);

    float v =
        frac(
            (index + 0.5) *
            0.6180339887498949
        );

    float radius =
        sqrt(u);

    float phi =
        2.0 *
        FLOWER_ATMOSPHERE_PI *
        v;

    float x =
        radius * cos(phi);

    float y =
        radius * sin(phi);

    float z =
        sqrt(
            saturate(
                1.0 - u
            )
        );

    float3 helper =
        abs(normal.y) < 0.999
            ? float3(0.0, 1.0, 0.0)
            : float3(1.0, 0.0, 0.0);

    float3 tangent =
        normalize(
            cross(helper, normal)
        );

    float3 bitangent =
        cross(normal, tangent);

    return normalize(
        tangent * x +
        bitangent * y +
        normal * z
    );
}

float3 FlowerAtmosphereCubeDirection(
    uint faceIndex,
    float2 uv)
{
    float2 p =
        uv * 2.0 - 1.0;

    p.y = -p.y;

    float3 direction = 0.0;

    if (faceIndex == 0)
    {
        direction =
            float3(
                1.0,
                p.y,
                -p.x
            );
    }
    else if (faceIndex == 1)
    {
        direction =
            float3(
                -1.0,
                p.y,
                p.x
            );
    }
    else if (faceIndex == 2)
    {
        direction =
            float3(
                p.x,
                1.0,
                -p.y
            );
    }
    else if (faceIndex == 3)
    {
        direction =
            float3(
                p.x,
                -1.0,
                p.y
            );
    }
    else if (faceIndex == 4)
    {
        direction =
            float3(
                p.x,
                p.y,
                1.0
            );
    }
    else
    {
        direction =
            float3(
                -p.x,
                p.y,
                -1.0
            );
    }

    return normalize(direction);
}

void FlowerAtmosphereDirectionToCubeUv(
    float3 direction,
    out uint faceIndex,
    out float2 uv)
{
    float3 absoluteDirection =
        abs(direction);

    float maximumAxis;
    float2 projected;

    if (absoluteDirection.x >= absoluteDirection.y &&
        absoluteDirection.x >= absoluteDirection.z)
    {
        maximumAxis =
            absoluteDirection.x;

        if (direction.x >= 0.0)
        {
            faceIndex = 0;

            projected =
                float2(
                    -direction.z,
                    direction.y
                ) /
                maximumAxis;
        }
        else
        {
            faceIndex = 1;

            projected =
                float2(
                    direction.z,
                    direction.y
                ) /
                maximumAxis;
        }
    }
    else if (absoluteDirection.y >= absoluteDirection.x &&
             absoluteDirection.y >= absoluteDirection.z)
    {
        maximumAxis =
            absoluteDirection.y;

        if (direction.y >= 0.0)
        {
            faceIndex = 2;

            projected =
                float2(
                    direction.x,
                    -direction.z
                ) /
                maximumAxis;
        }
        else
        {
            faceIndex = 3;

            projected =
                float2(
                    direction.x,
                    direction.z
                ) /
                maximumAxis;
        }
    }
    else
    {
        maximumAxis =
            absoluteDirection.z;

        if (direction.z >= 0.0)
        {
            faceIndex = 4;

            projected =
                float2(
                    direction.x,
                    direction.y
                ) /
                maximumAxis;
        }
        else
        {
            faceIndex = 5;

            projected =
                float2(
                    -direction.x,
                    direction.y
                ) /
                maximumAxis;
        }
    }

    uv =
        projected * 0.5 + 0.5;

    uv.y =
        1.0 - uv.y;

    uv =
        saturate(uv);
}

struct FlowerAtmosphereIntegrationResult
{
    float3 scatteredLight;
    float3 transmittance;
};

FlowerAtmosphereIntegrationResult
FlowerAtmosphereIntegrateScattering(
    Texture2D<float4> transmittanceTexture,
    SamplerState transmittanceSampler,
    Texture2D<float4> multiScatterTexture,
    SamplerState multiScatterSampler,
    float3 originKm,
    float3 direction,
    float maximumDistanceKm,
    float3 sunDirection,
    float3 sunLuminance,
    int stepCount,
    bool usePhase,
    float mieG)
{
    FlowerAtmosphereIntegrationResult result;

    result.scatteredLight = 0.0;
    result.transmittance = 1.0;

    float atmosphereDistanceKm =
        FlowerAtmosphereDistanceToBoundary(
            originKm,
            direction
        );

    float integrationDistanceKm =
        min(
            maximumDistanceKm,
            atmosphereDistanceKm
        );

    if (integrationDistanceKm <= 0.0)
    {
        return result;
    }

    stepCount =
        clamp(
            stepCount,
            1,
            FLOWER_ATMOSPHERE_MAX_STEPS
        );

    float stepLengthKm =
        integrationDistanceKm /
        stepCount;

    float currentDistanceKm =
        stepLengthKm * 0.5;

    float cosTheta =
        dot(
            direction,
            sunDirection
        );

    float rayleighPhase =
        usePhase
            ? FlowerAtmosphereRayleighPhase(
                cosTheta
            )
            : 1.0 /
              (4.0 * FLOWER_ATMOSPHERE_PI);

    float miePhase =
        usePhase
            ? FlowerAtmosphereMiePhase(
                cosTheta,
                mieG
            )
            : 1.0 /
              (4.0 * FLOWER_ATMOSPHERE_PI);

    [loop]
    for (int index = 0;
         index < FLOWER_ATMOSPHERE_MAX_STEPS;
         index++)
    {
        if (index >= stepCount)
        {
            break;
        }

        float3 samplePositionKm =
            originKm +
            direction *
            currentDistanceKm;

        float3 scattering;
        float3 extinction;
        float3 rayleighScattering;
        float3 mieScattering;

        FlowerAtmosphereMedium(
            samplePositionKm,
            scattering,
            extinction,
            rayleighScattering,
            mieScattering
        );

        float3 sunTransmittance =
            FlowerAtmosphereSampleTransmittance(
                transmittanceTexture,
                transmittanceSampler,
                samplePositionKm,
                sunDirection
            );

        float3 multipleScattering =
            FlowerAtmosphereSampleMultiScatter(
                multiScatterTexture,
                multiScatterSampler,
                samplePositionKm,
                sunDirection
            );

        float3 directSource =
            sunLuminance *
            sunTransmittance *
            (
                rayleighScattering *
                rayleighPhase +
                mieScattering *
                miePhase
            );

        float3 multipleSource =
            multipleScattering *
            scattering;

        float3 source =
            directSource +
            multipleSource;

        float3 stepTransmittance =
            exp(
                -extinction *
                stepLengthKm
            );

        float3 integratedSource =
            (
                source -
                source *
                stepTransmittance
            ) /
            max(
                extinction,
                0.0000001
            );

        result.scatteredLight +=
            result.transmittance *
            integratedSource;

        result.transmittance *=
            stepTransmittance;

        currentDistanceKm +=
            stepLengthKm;
    }

    return result;
}

#endif
