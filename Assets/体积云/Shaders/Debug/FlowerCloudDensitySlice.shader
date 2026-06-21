Shader "FlowerClouds/Debug/DensitySlice"
{
    Properties
    {
        [Header(Cloud)]
        _CloudCoverage("Cloud Coverage", Range(0, 1)) = 0.5
        _CloudDensity("Cloud Density", Range(0, 10)) = 1
        _CloudWeatherUVScale("Weather UV Scale", Range(0.001, 1)) = 0.03

        [Header(Noise)]
        _CloudBasicNoiseScale("Basic Noise Scale", Vector) = (0.15, 0.15, 0.15, 0)
        _CloudDetailNoiseScale("Detail Noise Scale", Vector) = (0.8, 0.8, 0.8, 0)

        [Header(Wind)]
        _CloudDirection("Cloud Direction", Vector) = (1, 0, 0, 0)
        _CloudSpeed("Cloud Speed", Range(0, 2)) = 0.05

        [Header(Slice)]
        _HorizontalRangeKm("Horizontal Range Km", Range(1, 200)) = 60
        _SliceZKm("Slice Z Km", Float) = 0
        _DensityContrast("Density Contrast", Range(0.1, 20)) = 5

        [Enum(Density,0,LayerColor,1)]
        _DisplayMode("Display Mode", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "DensitySlice"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE3D(_FlowerCloudBasicNoise);
            SAMPLER(sampler_FlowerCloudBasicNoise);

            TEXTURE3D(_FlowerCloudDetailNoise);
            SAMPLER(sampler_FlowerCloudDetailNoise);

            TEXTURE2D(_FlowerCloudWeather);
            SAMPLER(sampler_FlowerCloudWeather);

            TEXTURE2D(_FlowerCloudCurl);
            SAMPLER(sampler_FlowerCloudCurl);

            TEXTURE2D(_FlowerCloudCoverageNoise);
            SAMPLER(sampler_FlowerCloudCoverageNoise);

            CBUFFER_START(UnityPerMaterial)
                float _CloudCoverage;
                float _CloudDensity;
                float _CloudWeatherUVScale;

                float4 _CloudBasicNoiseScale;
                float4 _CloudDetailNoiseScale;

                float4 _CloudDirection;
                float _CloudSpeed;

                float _HorizontalRangeKm;
                float _SliceZKm;
                float _DensityContrast;
                float _DisplayMode;
            CBUFFER_END

            #include "../Includes/FlowerCloudDensityCommon.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float normalizedHeight = saturate(input.uv.y);

                float horizontalPositionKm = (input.uv.x - 0.5) * _HorizontalRangeKm;
                float heightMeter = normalizedHeight * 11000.0;

                float3 samplePositionMeter = float3(
                    horizontalPositionKm * 1000.0,
                    heightMeter,
                    _SliceZKm * 1000.0
                );

                float actualHeight01;
                int layerIndex;

                float density = FlowerCloudMap(
                    samplePositionMeter,
                    normalizedHeight,
                    actualHeight01,
                    layerIndex
                );

                density = saturate(density * _DensityContrast);

                if (_DisplayMode < 0.5)
                {
                    return half4(density, density, density, 1.0);
                }

                float3 layerColor = float3(1.0, 0.35, 0.1);

                if (layerIndex == 1)
                {
                    layerColor = float3(0.1, 0.8, 1.0);
                }
                else if (layerIndex == 2)
                {
                    layerColor = float3(0.7, 0.25, 1.0);
                }

                float3 backgroundColor = float3(0.01, 0.01, 0.015);
                float3 result = lerp(backgroundColor, layerColor, density);

                return half4(result, 1.0);
            }

            ENDHLSL
        }
    }

    Fallback Off
}