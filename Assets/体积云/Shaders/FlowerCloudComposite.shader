Shader "Hidden/FlowerClouds/Composite"
{
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
        }

        Pass
        {
            Name "FlowerCloudComposite"

            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D_X(_CloudColorTexture);
            SAMPLER(sampler_CloudColorTexture);

            bool FlowerIsSkyPixel(float rawDepth)
            {
                #if UNITY_REVERSED_Z
                    return rawDepth <= 0.0001;
                #else
                    return rawDepth >= 0.9999;
                #endif
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                half4 sceneColor =
                    SAMPLE_TEXTURE2D_X(
                        _BlitTexture,
                        sampler_LinearClamp,
                        uv
                    );

                float rawDepth =
                    SampleSceneDepth(uv);

                // Flower's cloud raymarch exits on scene geometry.
                // Keep the same rule in the URP composite.
                if (!FlowerIsSkyPixel(rawDepth))
                {
                    return sceneColor;
                }

                float4 cloud =
                    SAMPLE_TEXTURE2D_X(
                        _CloudColorTexture,
                        sampler_CloudColorTexture,
                        uv
                    );

                // cloud.rgb = in-scattered luminance
                // cloud.a   = view transmittance
                float3 result =
                    sceneColor.rgb *
                    saturate(cloud.a) +
                    max(cloud.rgb, 0.0);

                return half4(
                    result,
                    sceneColor.a
                );
            }

            ENDHLSL
        }
    }

    Fallback Off
}
