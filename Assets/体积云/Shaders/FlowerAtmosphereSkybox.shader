Shader "FlowerClouds/AtmosphereSkybox"
{
    Properties
    {
        _SkyExposure("Sky Exposure", Range(0, 8)) = 1
        _SunDiskIntensity("Sun Disk Intensity", Range(0, 100)) = 12
        _SunAngularRadius("Sun Angular Radius", Range(0.001, 0.02)) = 0.00465
        _SunDiskSoftness("Sun Disk Softness", Range(0.0001, 0.02)) = 0.002
    }

    SubShader
    {
        Tags
        {
            "Queue" = "Background"
            "RenderType" = "Background"
            "PreviewType" = "Skybox"
            "RenderPipeline" = "UniversalPipeline"
        }

        Cull Off
        ZWrite Off

        Pass
        {
            Name "FlowerAtmosphereSkybox"

            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Includes/FlowerAtmosphereCommon.hlsl"

            TEXTURE2D_ARRAY(_FlowerAtmosphereSkyCapture);
            SAMPLER(sampler_FlowerAtmosphereSkyCapture);

            float3 _FlowerAtmosphereSunDirection;
            float3 _FlowerAtmosphereSunLuminance;

            CBUFFER_START(UnityPerMaterial)
                float _SkyExposure;
                float _SunDiskIntensity;
                float _SunAngularRadius;
                float _SunDiskSoftness;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 directionWS : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                float3 positionWS =
                    TransformObjectToWorld(
                        input.positionOS
                    );

                output.positionCS =
                    TransformWorldToHClip(
                        positionWS
                    );

                output.directionWS =
                    normalize(
                        positionWS -
                        GetCameraPositionWS()
                    );

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float3 directionWS =
                    normalize(
                        input.directionWS
                    );

                uint faceIndex;
                float2 cubeUv;

                FlowerAtmosphereDirectionToCubeUv(
                    directionWS,
                    faceIndex,
                    cubeUv
                );

                float3 sky =
                    _FlowerAtmosphereSkyCapture.SampleLevel(
                        sampler_FlowerAtmosphereSkyCapture,
                        float3(
                            cubeUv,
                            faceIndex
                        ),
                        0.0
                    ).rgb;

                float sunCosine =
                    dot(
                        directionWS,
                        normalize(
                            _FlowerAtmosphereSunDirection
                        )
                    );

                float sunRadiusCosine =
                    cos(
                        _SunAngularRadius
                    );

                float sunSoftCosine =
                    cos(
                        _SunAngularRadius +
                        _SunDiskSoftness
                    );

                float sunDisk =
                    smoothstep(
                        sunSoftCosine,
                        sunRadiusCosine,
                        sunCosine
                    );

                float3 sun =
                    _FlowerAtmosphereSunLuminance *
                    _SunDiskIntensity *
                    sunDisk;

                return half4(
                    (sky + sun) *
                    _SkyExposure,
                    1.0
                );
            }

            ENDHLSL
        }
    }

    Fallback Off
}
