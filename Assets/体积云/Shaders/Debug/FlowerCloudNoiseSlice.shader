Shader "FlowerClouds/Debug/Noise Slice"
{
    Properties
    {
        _NoiseTex("Noise Texture", 3D) = "" {}
        _Slice("Z Slice", Range(0, 1)) = 0.5
        _Contrast("Contrast", Range(0.1, 8)) = 1
        _Invert("Invert", Range(0, 1)) = 0
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
            Name "NoiseSlice"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE3D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            CBUFFER_START(UnityPerMaterial)
                float _Slice;
                float _Contrast;
                float _Invert;
            CBUFFER_END

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

                output.positionCS =
                    TransformObjectToHClip(input.positionOS.xyz);

                output.uv = input.uv;

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float noiseValue = SAMPLE_TEXTURE3D(
                    _NoiseTex,
                    sampler_NoiseTex,
                    float3(input.uv, _Slice)
                ).r;

                noiseValue = saturate(
                    (noiseValue - 0.5) * _Contrast + 0.5
                );

                noiseValue = lerp(
                    noiseValue,
                    1.0 - noiseValue,
                    _Invert
                );

                return half4(
                    noiseValue,
                    noiseValue,
                    noiseValue,
                    1.0
                );
            }

            ENDHLSL
        }
    }

    Fallback Off
}
