Shader "Hidden/VolumetricClouds/CloudComposite"
{
    Properties
    {
        [Header(Planet)]
        _PlanetCenter("Planet Center", Vector) = (0, -100000, 0, 0)
        _PlanetRadius("Planet Radius", Float) = 100000

        [Header(Cloud Shell)]
        _CloudBottom("Cloud Bottom Height", Float) = 1500
        _CloudTop("Cloud Top Height", Float) = 4000

        [Header(Ray Marching)]
        [IntRange]
        _ViewStepCount("View Step Count", Range(8, 128)) = 48

        [IntRange]
        _LightStepCount("Light Step Count", Range(1, 16)) = 8

        _CloudDensity("Cloud Density", Range(0, 0.005)) = 0.0015
        _Extinction("View Extinction", Range(0, 5)) = 1
        _LightAbsorption("Light Absorption", Range(0, 5)) = 1.5

        _BottomFade("Bottom Fade", Range(0.001, 0.5)) = 0.15
        _TopFade("Top Fade", Range(0.001, 0.5)) = 0.25

        [Header(Cloud Shape)]
        _Coverage("Coverage", Range(0, 1)) = 0.55
        _NoiseSoftness("Noise Softness", Range(0.001, 0.5)) = 0.08

        _BaseNoiseScale("Base Noise Scale", Float) = 0.0006
        _DetailNoiseScale("Detail Noise Scale", Float) = 0.003
        _DetailStrength("Detail Strength", Range(0, 1)) = 0.3

        _WindDirection("Wind Direction XZ", Vector) = (1, 0, 0, 0)
        _WindSpeed("Wind Speed", Float) = 20

        [Header(Lighting)]
        [HDR]
        _CloudColor("Cloud Color", Color) = (1, 1, 1, 1)

        _ScatteringStrength("Scattering Strength", Range(0, 5)) = 1
        _SunIntensity("Sun Intensity", Range(0, 10)) = 1.5

        [HDR]
        _AmbientColor("Ambient Color", Color) = (0.35, 0.45, 0.65, 1)

        _AmbientStrength("Ambient Strength", Range(0, 2)) = 0.25

        [Header(Ambient Trace)]
        [IntRange]
        _AmbientStepCount("Ambient Step Count", Range(1, 8)) = 4
        _AmbientAbsorption("Ambient Absorption", Range(0, 5)) = 1
        _AmbientTraceStrength("Ambient Trace Strength", Range(0, 1)) = 0.65

        [Header(Powder Effect)]
        _PowderStrength("Powder Strength", Range(0, 3)) = 0.8
        _PowderDensityScale("Powder Density Scale", Range(0, 8)) = 2
        _PowderHeightStart("Powder Height Start", Range(0, 1)) = 0.05
        _PowderHeightEnd("Powder Height End", Range(0, 1)) = 0.75

        [Header(Atmospheric Perspective)]
        [HDR]
        _AtmosphereColor("Atmosphere Color", Color) = (0.55, 0.7, 1.0, 1)
        _AtmosphereDensity("Atmosphere Density", Range(0, 0.0002)) = 0.000025
        _AtmosphereStrength("Atmosphere Strength", Range(0, 1)) = 0.65

        [Header(Phase Function)]
        _PhaseForward("Forward Scattering", Range(0, 0.95)) = 0.65
        _PhaseBackward("Backward Scattering", Range(-0.95, 0)) = -0.2
        _PhaseBlend("Backward Blend", Range(0, 1)) = 0.2
        _PhaseStrength("Phase Strength", Range(0, 1)) = 0.8

        [Header(Debug)]
        [Enum(CloudMask,0,RayDirection,1,StartDistance,2,SegmentLength,3,Cloud,4)]
        _DebugMode("Debug Mode", Float) = 4

        _DebugDistance("Debug Distance", Float) = 50000
        _DebugOpacity("Debug Opacity", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "VolumetricClouds"

            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #define MAX_VIEW_STEP_COUNT 128
            #define MAX_LIGHT_STEP_COUNT 16
            #define MAX_AMBIENT_STEP_COUNT 8
            #define PI 3.14159265359

            CBUFFER_START(UnityPerMaterial)

                float4 _PlanetCenter;
                float _PlanetRadius;

                float _CloudBottom;
                float _CloudTop;

                float _ViewStepCount;
                float _LightStepCount;

                float _CloudDensity;
                float _Extinction;
                float _LightAbsorption;

                float _BottomFade;
                float _TopFade;

                float _Coverage;
                float _NoiseSoftness;

                float _BaseNoiseScale;
                float _DetailNoiseScale;
                float _DetailStrength;

                float4 _WindDirection;
                float _WindSpeed;

                float4 _CloudColor;
                float _ScatteringStrength;
                float _SunIntensity;

                float4 _AmbientColor;
                float _AmbientStrength;

                float _AmbientStepCount;
                float _AmbientAbsorption;
                float _AmbientTraceStrength;

                float _PowderStrength;
                float _PowderDensityScale;
                float _PowderHeightStart;
                float _PowderHeightEnd;

                float4 _AtmosphereColor;
                float _AtmosphereDensity;
                float _AtmosphereStrength;

                float _PhaseForward;
                float _PhaseBackward;
                float _PhaseBlend;
                float _PhaseStrength;

                float _DebugMode;
                float _DebugDistance;
                float _DebugOpacity;

            CBUFFER_END

            float2 RaySphere(
                float3 rayOrigin,
                float3 rayDirection,
                float3 sphereCenter,
                float sphereRadius)
            {
                float3 offset = rayOrigin - sphereCenter;

                float b = dot(offset, rayDirection);
                float c = dot(offset, offset) - sphereRadius * sphereRadius;
                float discriminant = b * b - c;

                if (discriminant < 0.0)
                {
                    return float2(-1.0, -1.0);
                }

                float sqrtDiscriminant = sqrt(discriminant);

                return float2(
                    -b - sqrtDiscriminant,
                    -b + sqrtDiscriminant
                );
            }

            float3 GetWorldRayDirection(float2 screenUV)
            {
                #if UNITY_REVERSED_Z
                    float farDepth = 0.0;
                #else
                    float farDepth = 1.0;
                #endif

                float3 farPositionWS = ComputeWorldSpacePosition(
                    screenUV,
                    farDepth,
                    UNITY_MATRIX_I_VP
                );

                return normalize(farPositionWS - _WorldSpaceCameraPos);
            }

            bool IsSkyPixel(float rawDepth)
            {
                #if UNITY_REVERSED_Z
                    return rawDepth <= 0.0001;
                #else
                    return rawDepth >= 0.9999;
                #endif
            }

            bool GetCloudRaySegment(
                float3 rayOriginWS,
                float3 rayDirectionWS,
                out float rayStart,
                out float rayEnd)
            {
                rayStart = 0.0;
                rayEnd = 0.0;

                float3 planetCenterWS = _PlanetCenter.xyz;

                float innerRadius = _PlanetRadius + _CloudBottom;
                float outerRadius = _PlanetRadius + _CloudTop;

                float2 innerHit = RaySphere(
                    rayOriginWS,
                    rayDirectionWS,
                    planetCenterWS,
                    innerRadius
                );

                float2 outerHit = RaySphere(
                    rayOriginWS,
                    rayDirectionWS,
                    planetCenterWS,
                    outerRadius
                );

                if (outerHit.y <= 0.0)
                {
                    return false;
                }

                float cameraRadius = distance(rayOriginWS, planetCenterWS);

                if (cameraRadius < innerRadius)
                {
                    if (innerHit.y <= 0.0)
                    {
                        return false;
                    }

                    rayStart = max(innerHit.y, 0.0);
                    rayEnd = outerHit.y;
                }
                else if (cameraRadius < outerRadius)
                {
                    rayStart = 0.0;
                    rayEnd = outerHit.y;

                    if (innerHit.x > 0.0)
                    {
                        rayEnd = min(rayEnd, innerHit.x);
                    }
                }
                else
                {
                    rayStart = max(outerHit.x, 0.0);
                    rayEnd = outerHit.y;

                    if (innerHit.x > rayStart && innerHit.x < rayEnd)
                    {
                        rayEnd = innerHit.x;
                    }
                }

                float2 planetHit = RaySphere(
                    rayOriginWS,
                    rayDirectionWS,
                    planetCenterWS,
                    _PlanetRadius
                );

                float planetDistance = 1e20;

                if (planetHit.x > 0.0)
                {
                    planetDistance = planetHit.x;
                }
                else if (planetHit.y > 0.0)
                {
                    planetDistance = planetHit.y;
                }

                if (planetDistance < rayEnd)
                {
                    rayEnd = planetDistance;
                }

                return rayEnd > rayStart;
            }

            float GetNormalizedCloudHeight(float3 positionWS)
            {
                float radiusFromPlanetCenter = distance(
                    positionWS,
                    _PlanetCenter.xyz
                );

                float heightAboveSurface =
                    radiusFromPlanetCenter - _PlanetRadius;

                float cloudThickness = max(
                    _CloudTop - _CloudBottom,
                    0.0001
                );

                return saturate(
                    (heightAboveSurface - _CloudBottom) / cloudThickness
                );
            }

            float Hash31(float3 position)
            {
                position = frac(position * 0.1031);

                position += dot(
                    position,
                    position.yzx + 33.33
                );

                return frac(
                    (position.x + position.y) * position.z
                );
            }

            float ValueNoise3D(float3 position)
            {
                float3 cell = floor(position);
                float3 localPosition = frac(position);

                float3 smoothPosition =
                    localPosition * localPosition * (3.0 - 2.0 * localPosition);

                float n000 = Hash31(cell + float3(0.0, 0.0, 0.0));
                float n100 = Hash31(cell + float3(1.0, 0.0, 0.0));
                float n010 = Hash31(cell + float3(0.0, 1.0, 0.0));
                float n110 = Hash31(cell + float3(1.0, 1.0, 0.0));
                float n001 = Hash31(cell + float3(0.0, 0.0, 1.0));
                float n101 = Hash31(cell + float3(1.0, 0.0, 1.0));
                float n011 = Hash31(cell + float3(0.0, 1.0, 1.0));
                float n111 = Hash31(cell + float3(1.0, 1.0, 1.0));

                float nx00 = lerp(n000, n100, smoothPosition.x);
                float nx10 = lerp(n010, n110, smoothPosition.x);
                float nx01 = lerp(n001, n101, smoothPosition.x);
                float nx11 = lerp(n011, n111, smoothPosition.x);

                float nxy0 = lerp(nx00, nx10, smoothPosition.y);
                float nxy1 = lerp(nx01, nx11, smoothPosition.y);

                return lerp(nxy0, nxy1, smoothPosition.z);
            }

            float FBM3D(float3 position)
            {
                float result = 0.0;
                float amplitude = 0.5;

                [unroll]
                for (int octave = 0; octave < 4; octave++)
                {
                    result += ValueNoise3D(position) * amplitude;

                    position =
                        position * 2.03
                        + float3(17.1, 31.7, 11.3);

                    amplitude *= 0.5;
                }

                return result / 0.9375;
            }

            float SampleCloudDensity(float3 positionWS)
            {
                float height01 = GetNormalizedCloudHeight(positionWS);

                float bottomFadeSize = max(_BottomFade, 0.0001);
                float topFadeSize = max(_TopFade, 0.0001);

                float bottomFade = smoothstep(
                    0.0,
                    bottomFadeSize,
                    height01
                );

                float topFade =
                    1.0 - smoothstep(
                        1.0 - topFadeSize,
                        1.0,
                        height01
                    );

                float heightShape = bottomFade * topFade;

                if (heightShape <= 0.0001)
                {
                    return 0.0;
                }

                float2 windDirectionXZ = _WindDirection.xz;
                float windLength = length(windDirectionXZ);

                if (windLength > 0.0001)
                {
                    windDirectionXZ /= windLength;
                }
                else
                {
                    windDirectionXZ = float2(1.0, 0.0);
                }

                float3 windOffsetWS = float3(
                    windDirectionXZ.x,
                    0.0,
                    windDirectionXZ.y
                ) * (_Time.y * _WindSpeed);

                float3 baseNoisePosition =
                    (positionWS + windOffsetWS)
                    * max(_BaseNoiseScale, 0.000001);

                float baseNoise = FBM3D(baseNoisePosition);

                float cloudThreshold = 1.0 - _Coverage;
                float softness = max(_NoiseSoftness, 0.0001);

                float baseShape = smoothstep(
                    cloudThreshold - softness,
                    cloudThreshold + softness,
                    baseNoise
                );

                if (baseShape <= 0.0001)
                {
                    return 0.0;
                }

                float3 detailNoisePosition =
                    (positionWS - windOffsetWS * 1.7)
                    * max(_DetailNoiseScale, 0.000001);

                float detailNoise = FBM3D(
                    detailNoisePosition
                    + float3(13.7, 7.1, 19.3)
                );

                float erosion =
                    (1.0 - detailNoise) * _DetailStrength;

                float finalShape =
                    saturate(baseShape - erosion) * heightShape;

                return finalShape * _CloudDensity;
            }

            float HenyeyGreenstein(float cosTheta, float g)
            {
                float g2 = g * g;

                float denominator =
                    max(1.0 + g2 - 2.0 * g * cosTheta, 0.0001);

                return
                    (1.0 - g2)
                    / (4.0 * PI * denominator * sqrt(denominator));
            }

            float DualLobePhase(float cosTheta)
            {
                float forwardPhase =
                    HenyeyGreenstein(cosTheta, _PhaseForward);

                float backwardPhase =
                    HenyeyGreenstein(cosTheta, _PhaseBackward);

                float phase =
                    lerp(forwardPhase, backwardPhase, _PhaseBlend);

                // 乘 4PI 后，g=0 的各向同性相位值约等于 1。
                float normalizedPhase = phase * (4.0 * PI);

                return lerp(
                    1.0,
                    normalizedPhase,
                    _PhaseStrength
                );
            }

            float GetLightTransmittance(
                float3 samplePositionWS,
                float3 lightDirectionWS)
            {
                float outerRadius = _PlanetRadius + _CloudTop;

                float3 lightRayOrigin =
                    samplePositionWS + lightDirectionWS * 1.0;

                float2 outerHit = RaySphere(
                    lightRayOrigin,
                    lightDirectionWS,
                    _PlanetCenter.xyz,
                    outerRadius
                );

                if (outerHit.y <= 0.0)
                {
                    return 1.0;
                }

                float lightDistance = outerHit.y;

                float2 planetHit = RaySphere(
                    lightRayOrigin,
                    lightDirectionWS,
                    _PlanetCenter.xyz,
                    _PlanetRadius
                );

                float nearestPlanetHit = 1e20;

                if (planetHit.x > 0.0)
                {
                    nearestPlanetHit = planetHit.x;
                }
                else if (planetHit.y > 0.0)
                {
                    nearestPlanetHit = planetHit.y;
                }

                // 太阳方向被星球本身挡住。
                if (nearestPlanetHit < lightDistance)
                {
                    return 0.0;
                }

                int lightStepCount = clamp(
                    (int)_LightStepCount,
                    1,
                    MAX_LIGHT_STEP_COUNT
                );

                float lightStepLength =
                    lightDistance / lightStepCount;

                float currentLightDistance =
                    lightStepLength * 0.5;

                float lightTransmittance = 1.0;

                [loop]
                for (int j = 0; j < MAX_LIGHT_STEP_COUNT; j++)
                {
                    if (j >= lightStepCount)
                    {
                        break;
                    }

                    float3 lightSamplePositionWS =
                        lightRayOrigin
                        + lightDirectionWS * currentLightDistance;

                    float lightDensity =
                        SampleCloudDensity(lightSamplePositionWS);

                    if (lightDensity > 0.000001)
                    {
                        float lightOpticalDepth =
                            lightDensity
                            * _Extinction
                            * _LightAbsorption
                            * lightStepLength;

                        lightTransmittance *=
                            exp(-lightOpticalDepth);

                        if (lightTransmittance < 0.01)
                        {
                            return 0.01;
                        }
                    }

                    currentLightDistance += lightStepLength;
                }

                return lightTransmittance;
            }

            float GetAmbientVisibility(float3 samplePositionWS)
            {
                float3 upDirectionWS = normalize(
                    samplePositionWS - _PlanetCenter.xyz
                );

                float outerRadius = _PlanetRadius + _CloudTop;

                float3 ambientRayOrigin =
                    samplePositionWS + upDirectionWS * 1.0;

                float2 outerHit = RaySphere(
                    ambientRayOrigin,
                    upDirectionWS,
                    _PlanetCenter.xyz,
                    outerRadius
                );

                if (outerHit.y <= 0.0)
                {
                    return 1.0;
                }

                int ambientStepCount = clamp(
                    (int)_AmbientStepCount,
                    1,
                    MAX_AMBIENT_STEP_COUNT
                );

                float ambientDistance = outerHit.y;
                float ambientStepLength =
                    ambientDistance / ambientStepCount;

                float currentAmbientDistance =
                    ambientStepLength * 0.5;

                float ambientVisibility = 1.0;

                [loop]
                for (int k = 0; k < MAX_AMBIENT_STEP_COUNT; k++)
                {
                    if (k >= ambientStepCount)
                    {
                        break;
                    }

                    float3 ambientSamplePositionWS =
                        ambientRayOrigin
                        + upDirectionWS * currentAmbientDistance;

                    float ambientDensity =
                        SampleCloudDensity(ambientSamplePositionWS);

                    if (ambientDensity > 0.000001)
                    {
                        float ambientOpticalDepth =
                            ambientDensity
                            * _Extinction
                            * _AmbientAbsorption
                            * ambientStepLength;

                        ambientVisibility *=
                            exp(-ambientOpticalDepth);

                        if (ambientVisibility < 0.02)
                        {
                            return 0.02;
                        }
                    }

                    currentAmbientDistance += ambientStepLength;
                }

                return ambientVisibility;
            }

            float GetPowderBoost(
                float normalizedDensity,
                float height01,
                float viewLightCos)
            {
                float depthProbability =
                    1.0 - exp(
                        -saturate(normalizedDensity)
                        * _PowderDensityScale
                    );

                float verticalProbability = smoothstep(
                    _PowderHeightStart,
                    max(_PowderHeightEnd, _PowderHeightStart + 0.0001),
                    height01
                );

                float forwardProbability =
                    saturate(viewLightCos * 0.5 + 0.5);

                forwardProbability *= forwardProbability;

                float powderShape = lerp(
                    verticalProbability,
                    1.0,
                    forwardProbability
                );

                return 1.0
                    + depthProbability
                    * powderShape
                    * _PowderStrength;
            }

            float3 DistanceDebugColor(float distanceValue)
            {
                float distance01 = saturate(
                    distanceValue / max(_DebugDistance, 0.0001)
                );

                float3 nearColor = float3(1.0, 0.15, 0.05);
                float3 farColor = float3(0.05, 0.25, 1.0);

                return lerp(nearColor, farColor, distance01);
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 screenUV =
                    UnityStereoTransformScreenSpaceTex(input.texcoord);

                half4 sceneColor = SAMPLE_TEXTURE2D_X(
                    _BlitTexture,
                    sampler_LinearClamp,
                    screenUV
                );

                float rawDepth = SampleSceneDepth(screenUV);

                if (!IsSkyPixel(rawDepth))
                {
                    return sceneColor;
                }

                float3 rayOriginWS = _WorldSpaceCameraPos;
                float3 rayDirectionWS = GetWorldRayDirection(screenUV);

                float rayStart;
                float rayEnd;

                bool hasCloudSegment = GetCloudRaySegment(
                    rayOriginWS,
                    rayDirectionWS,
                    rayStart,
                    rayEnd
                );

                if (!hasCloudSegment)
                {
                    return sceneColor;
                }

                float rayLength = rayEnd - rayStart;

                if (_DebugMode < 0.5)
                {
                    float3 debugColor = float3(0.05, 0.75, 1.0);

                    return half4(
                        lerp(sceneColor.rgb, debugColor, _DebugOpacity),
                        sceneColor.a
                    );
                }

                if (_DebugMode < 1.5)
                {
                    float3 debugColor =
                        rayDirectionWS * 0.5 + 0.5;

                    return half4(
                        lerp(sceneColor.rgb, debugColor, _DebugOpacity),
                        sceneColor.a
                    );
                }

                if (_DebugMode < 2.5)
                {
                    float3 debugColor =
                        DistanceDebugColor(rayStart);

                    return half4(
                        lerp(sceneColor.rgb, debugColor, _DebugOpacity),
                        sceneColor.a
                    );
                }

                if (_DebugMode < 3.5)
                {
                    float length01 = saturate(
                        rayLength / max(_DebugDistance, 0.0001)
                    );

                    float3 debugColor = length01.xxx;

                    return half4(
                        lerp(sceneColor.rgb, debugColor, _DebugOpacity),
                        sceneColor.a
                    );
                }

                Light mainLight = GetMainLight();

                float3 lightDirectionWS =
                    normalize(mainLight.direction);

                float3 sunColor =
                    mainLight.color * _SunIntensity;

                // 朝太阳方向看时 cosTheta 接近 1，产生明显前向散射。
                float cosTheta =
                    dot(rayDirectionWS, lightDirectionWS);

                float phase =
                    DualLobePhase(cosTheta);

                int stepCount = clamp(
                    (int)_ViewStepCount,
                    1,
                    MAX_VIEW_STEP_COUNT
                );

                float stepLength = rayLength / stepCount;
                float currentDistance = rayStart + stepLength * 0.5;

                float transmittance = 1.0;
                float3 scattering = 0.0;

                // 用真正产生散射贡献的权重估算云的代表距离，
                // 后面用于大气透视。
                float weightedCloudDistance = 0.0;
                float cloudDistanceWeight = 0.0;

                [loop]
                for (int i = 0; i < MAX_VIEW_STEP_COUNT; i++)
                {
                    if (i >= stepCount)
                    {
                        break;
                    }

                    float3 samplePositionWS =
                        rayOriginWS
                        + rayDirectionWS * currentDistance;

                    float density =
                        SampleCloudDensity(samplePositionWS);

                    if (density > 0.000001)
                    {
                        float opticalDepth =
                            density
                            * _Extinction
                            * stepLength;

                        float stepTransmittance =
                            exp(-opticalDepth);

                        float sunTransmittance =
                            GetLightTransmittance(
                                samplePositionWS,
                                lightDirectionWS
                            );

                        float height01 =
                            GetNormalizedCloudHeight(samplePositionWS);

                        float ambientHeight =
                            lerp(0.65, 1.0, height01);

                        float ambientVisibility =
                            GetAmbientVisibility(samplePositionWS);

                        float ambientOcclusion = lerp(
                            1.0,
                            ambientVisibility,
                            _AmbientTraceStrength
                        );

                        float3 ambientLighting =
                            _AmbientColor.rgb
                            * _AmbientStrength
                            * ambientHeight
                            * ambientOcclusion;

                        float normalizedDensity = saturate(
                            density / max(_CloudDensity, 0.000001)
                        );

                        float powderBoost = GetPowderBoost(
                            normalizedDensity,
                            height01,
                            cosTheta
                        );

                        float3 directLighting =
                            sunColor
                            * sunTransmittance
                            * phase
                            * powderBoost;

                        float3 stepLighting =
                            _CloudColor.rgb
                            * (ambientLighting + directLighting)
                            * _ScatteringStrength;

                        float contributionWeight =
                            transmittance
                            * (1.0 - stepTransmittance);

                        scattering +=
                            contributionWeight
                            * stepLighting;

                        weightedCloudDistance +=
                            currentDistance
                            * contributionWeight;

                        cloudDistanceWeight +=
                            contributionWeight;

                        transmittance *= stepTransmittance;

                        if (transmittance < 0.01)
                        {
                            break;
                        }
                    }

                    currentDistance += stepLength;
                }

                float cloudOpacity = 1.0 - transmittance;

                float representativeCloudDistance =
                    cloudDistanceWeight > 0.000001
                    ? weightedCloudDistance / cloudDistanceWeight
                    : rayStart;

                float atmosphereAmount =
                    1.0 - exp(
                        -representativeCloudDistance
                        * _AtmosphereDensity
                    );

                atmosphereAmount = saturate(
                    atmosphereAmount
                    * _AtmosphereStrength
                );

                // 只对云自身的散射结果做大气透视，
                // 不会把没有云的天空区域一起染色。
                float3 atmosphereScattering =
                    _AtmosphereColor.rgb
                    * cloudOpacity;

                float3 foggedCloudScattering = lerp(
                    scattering,
                    atmosphereScattering,
                    atmosphereAmount
                );

                float3 finalColor =
                    sceneColor.rgb * transmittance
                    + foggedCloudScattering;

                return half4(finalColor, sceneColor.a);
            }

            ENDHLSL
        }
    }

    Fallback Off
}
