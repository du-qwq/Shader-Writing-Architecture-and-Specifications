Shader "ToonRenderFramework/Scene/Lit/Ground"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)

        [NoScaleOffset] _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalScale("Normal Scale", Range(0, 2)) = 1.0

        _ShadowColor("Shadow Color (Local Backup)", Color) = (0.75, 0.80, 0.90, 1)
        _ToonThreshold("Toon Threshold (Local Backup)", Range(0, 1)) = 0.5
        _ToonSmoothness("Toon Smoothness (Local Backup)", Range(0.001, 0.3)) = 0.06

        [Toggle(_TOON_SCENE_SPECULAR_ON)] _EnableSpecular("Enable Specular", Float) = 0
        _SpecColor("Specular Color", Color) = (1,1,1,1)
        _SpecThreshold("Specular Threshold", Range(0, 1)) = 0.82
        _SpecSmoothness("Specular Smoothness", Range(0.001, 0.2)) = 0.03
        _SpecIntensity("Specular Intensity", Range(0, 2)) = 0.25
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual
            Blend One Zero

            HLSLPROGRAM
            #pragma target 3.0

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #pragma shader_feature_local _TOON_SCENE_SPECULAR_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;

                half _NormalScale;

                half4 _ShadowColor;
                half _ToonThreshold;
                half _ToonSmoothness;

                half4 _SpecColor;
                half _SpecThreshold;
                half _SpecSmoothness;
                half _SpecIntensity;
            CBUFFER_END

            // 全局 Toon 参数
            float4 _GlobalToonShadowColor;
            float _GlobalToonThreshold;
            float _GlobalToonSmoothness;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                half3 normalWS     : TEXCOORD2;
                half3 tangentWS    : TEXCOORD3;
                half3 bitangentWS  : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                half fogFactor     : TEXCOORD6;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionCS = positionInputs.positionCS;
                OUT.positionWS = positionInputs.positionWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                OUT.normalWS = NormalizeNormalPerVertex(normalInputs.normalWS);
                OUT.tangentWS = NormalizeNormalPerVertex(normalInputs.tangentWS);
                OUT.bitangentWS = NormalizeNormalPerVertex(normalInputs.bitangentWS);

                OUT.shadowCoord = GetShadowCoord(positionInputs);
                OUT.fogFactor = ComputeFogFactor(positionInputs.positionCS.z);

                return OUT;
            }

            half3 GetNormalWS(Varyings IN)
            {
                half4 normalSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv);
                half3 normalTS = UnpackNormalScale(normalSample, _NormalScale);

                half3x3 tbn = half3x3(
                    normalize(IN.tangentWS),
                    normalize(IN.bitangentWS),
                    normalize(IN.normalWS)
                );

                return normalize(TransformTangentToWorld(normalTS, tbn));
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 albedo = baseTex.rgb * _BaseColor.rgb;

                half3 normalWS = GetNormalWS(IN);
                half3 viewDirWS = normalize(GetWorldSpaceViewDir(IN.positionWS));

                Light mainLight = GetMainLight(IN.shadowCoord);

                half3 lightDirWS = normalize(mainLight.direction);
                half3 lightColor = mainLight.color;

                half ndotl = saturate(dot(normalWS, lightDirWS));
                half lightAtten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half litTerm = ndotl * lightAtten;

                half3 shadowColor = _GlobalToonShadowColor.rgb;
                half toonThreshold = _GlobalToonThreshold;
                half toonSmoothness = _GlobalToonSmoothness;

                half toonStep = smoothstep(
                    toonThreshold - toonSmoothness,
                    toonThreshold + toonSmoothness,
                    litTerm
                );

                half3 toonDiffuse = lerp(albedo * shadowColor, albedo, toonStep);
                toonDiffuse *= lightColor;

                half3 ambient = albedo * SampleSH(normalWS);

                half3 specular = 0;
                #if defined(_TOON_SCENE_SPECULAR_ON)
                {
                    half3 halfDir = normalize(lightDirWS + viewDirWS);
                    half ndoth = saturate(dot(normalWS, halfDir));

                    half specStep = smoothstep(
                        _SpecThreshold - _SpecSmoothness,
                        _SpecThreshold + _SpecSmoothness,
                        ndoth
                    );

                    specular = specStep * _SpecColor.rgb * _SpecIntensity * lightColor * lightAtten;
                }
                #endif

                half3 finalColor = ambient + toonDiffuse + specular;
                finalColor = MixFog(finalColor, IN.fogFactor);

                return half4(finalColor, baseTex.a * _BaseColor.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadowVert(Attributes IN)
            {
                Varyings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(positionWS);
                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex DepthVert
            #pragma fragment DepthFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings DepthVert(Attributes IN)
            {
                Varyings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(positionWS);
                return OUT;
            }

            half4 DepthFrag(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}