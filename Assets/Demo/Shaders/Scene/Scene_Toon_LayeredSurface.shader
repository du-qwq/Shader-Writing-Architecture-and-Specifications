Shader "ToonRenderFramework/Scene/Lit/LayeredSurface"
{
    Properties
    {
        [Header(Base Maps)]
        _Color("Main Color", Color) = (1,1,1,1)
        _MainTex("Albedo", 2D) = "white" {}
        _BumpMap("Normal", 2D) = "bump" {}
        _NormalPower("Normal Power", Range(0,2)) = 1
        _MetallicGlossMap("Metallic (R) Occlusion (G) Smoothness (A)", 2D) = "black" {}
        _MetallicPower("Metallic Power", Range(0,1)) = 0
        _SmoothnessPower("Smoothness Power", Range(0,1)) = 0.4
        _OcclusionPower("Occlusion Power", Range(0,4)) = 1

        [Header(Layer Control)]
        [Toggle]_UseVertexColor("Use Vertex Color", Float) = 0
        [KeywordEnum(R,G,B,A)] _VertexColorChannel("Vertex Color Channel", Float) = 2
        _LayerPower("Layer Power", Range(0,1)) = 0.15
        _LayerThreshold("Layer Threshold", Range(0,1)) = 0.5
        _LayerContrast("Layer Contrast", Range(0,4)) = 1

        [Header(Layer Maps)]
        _2ndColor("Layer Color", Color) = (1,1,1,1)
        _DetailAlbedoMap("Layer Albedo", 2D) = "white" {}
        _DetailNormalMap("Layer Normal", 2D) = "bump" {}
        _2ndNormalPower("Layer Normal Power", Range(0,2)) = 1
        _DetailMetallicGlossMap("Layer Metallic (R) Occlusion (G) Smoothness (A)", 2D) = "black" {}
        _Tiling("Layer Tiling", Float) = 1

        [Header(Toon Lighting)]
        _ShadowColor("Shadow Color (Local Backup)", Color) = (0.75, 0.80, 0.90, 1)
        _ToonThreshold("Toon Threshold (Local Backup)", Range(0,1)) = 0.5
        _ToonSmoothness("Toon Smoothness (Local Backup)", Range(0.001,0.3)) = 0.06

        [Toggle(_SEEVERTEXCOLORS_ON)] _SeeVertexColors("See Vertex Colors", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "Queue"="Geometry"
            "RenderPipeline"="UniversalPipeline"
        }

        Cull Back

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

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

            #pragma shader_feature_local _SEEVERTEXCOLORS_ON
            #pragma shader_feature_local _VERTEXCOLORCHANNEL_R _VERTEXCOLORCHANNEL_G _VERTEXCOLORCHANNEL_B _VERTEXCOLORCHANNEL_A

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_MetallicGlossMap); SAMPLER(sampler_MetallicGlossMap);

            TEXTURE2D(_DetailAlbedoMap); SAMPLER(sampler_DetailAlbedoMap);
            TEXTURE2D(_DetailNormalMap); SAMPLER(sampler_DetailNormalMap);
            TEXTURE2D(_DetailMetallicGlossMap); SAMPLER(sampler_DetailMetallicGlossMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float4 _2ndColor;
                float4 _MainTex_ST;
                float4 _BumpMap_ST;
                float4 _MetallicGlossMap_ST;

                float _NormalPower;
                float _2ndNormalPower;
                float _Tiling;

                float _UseVertexColor;
                float _LayerPower;
                float _LayerThreshold;
                float _LayerContrast;

                float _MetallicPower;
                float _SmoothnessPower;
                float _OcclusionPower;

                float4 _ShadowColor;
                float _ToonThreshold;
                float _ToonSmoothness;
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
                float4 color      : COLOR;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                half3 normalWS     : TEXCOORD2;
                half4 tangentWS    : TEXCOORD3;
                half4 color        : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                half fogFactor     : TEXCOORD6;
            };

            half GetVertexMask(half4 c)
            {
                #if defined(_VERTEXCOLORCHANNEL_R)
                    return c.r;
                #elif defined(_VERTEXCOLORCHANNEL_G)
                    return c.g;
                #elif defined(_VERTEXCOLORCHANNEL_B)
                    return c.b;
                #elif defined(_VERTEXCOLORCHANNEL_A)
                    return c.a;
                #else
                    return c.b;
                #endif
            }

            half Contrast01(half x, half contrast)
            {
                return saturate((x - 0.5h) * contrast + 0.5h);
            }

            half4 SampleTriplanarColor(TEXTURE2D_PARAM(tex, samp), float3 worldPos, half3 worldNormal, float tiling)
            {
                half3 n = pow(abs(worldNormal), 1.0h);
                n /= max(n.x + n.y + n.z, 0.0001h);

                half4 x = SAMPLE_TEXTURE2D(tex, samp, worldPos.zy * tiling);
                half4 y = SAMPLE_TEXTURE2D(tex, samp, worldPos.xz * tiling);
                half4 z = SAMPLE_TEXTURE2D(tex, samp, worldPos.xy * tiling);

                return x * n.x + y * n.y + z * n.z;
            }

            half3 SampleTriplanarNormalWS(TEXTURE2D_PARAM(tex, samp), float3 worldPos, half3 worldNormal, float tiling, half normalScale)
            {
                half3 n = pow(abs(worldNormal), 1.0h);
                n /= max(n.x + n.y + n.z, 0.0001h);

                half3 nx = UnpackNormalScale(SAMPLE_TEXTURE2D(tex, samp, worldPos.zy * tiling), normalScale);
                half3 ny = UnpackNormalScale(SAMPLE_TEXTURE2D(tex, samp, worldPos.xz * tiling), normalScale);
                half3 nz = UnpackNormalScale(SAMPLE_TEXTURE2D(tex, samp, worldPos.xy * tiling), normalScale);

                half3 worldNX = normalize(half3(nx.z, nx.y, nx.x));
                half3 worldNY = normalize(half3(ny.x, ny.z, ny.y));
                half3 worldNZ = normalize(half3(nz.x, nz.y, nz.z));

                return normalize(worldNX * n.x + worldNY * n.y + worldNZ * n.z);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionCS = posInputs.positionCS;
                OUT.uv = IN.uv;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS = NormalizeNormalPerVertex(normInputs.normalWS);
                OUT.tangentWS = half4(normalize(normInputs.tangentWS), IN.tangentOS.w);
                OUT.color = IN.color;
                OUT.shadowCoord = GetShadowCoord(posInputs);
                OUT.fogFactor = ComputeFogFactor(posInputs.positionCS.z);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uvMain = TRANSFORM_TEX(IN.uv, _MainTex);
                float2 uvBump = TRANSFORM_TEX(IN.uv, _BumpMap);
                float2 uvMRA  = TRANSFORM_TEX(IN.uv, _MetallicGlossMap);

                float3 worldPos = IN.positionWS;
                half3 baseNormalWS = normalize(IN.normalWS);

                half3 tangentWS = normalize(IN.tangentWS.xyz);
                half tangentSign = IN.tangentWS.w;
                half3 bitangentWS = normalize(cross(baseNormalWS, tangentWS) * tangentSign);
                half3x3 tbn = half3x3(tangentWS, bitangentWS, baseNormalWS);

                half4 mainAlb = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uvMain);
                half3 baseAlbedo = _Color.rgb * mainAlb.rgb;

                half3 meshNormalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uvBump), _NormalPower);
                half3 meshNormalWS = normalize(mul(meshNormalTS, tbn));

                half4 layerAlbTex = SampleTriplanarColor(
                    TEXTURE2D_ARGS(_DetailAlbedoMap, sampler_DetailAlbedoMap),
                    worldPos, baseNormalWS, _Tiling
                );
                half3 layerAlbedo = _2ndColor.rgb * layerAlbTex.rgb;

                half3 layerNormalWS = SampleTriplanarNormalWS(
                    TEXTURE2D_ARGS(_DetailNormalMap, sampler_DetailNormalMap),
                    worldPos, baseNormalWS, _Tiling, _2ndNormalPower
                );

                half vertexMask = GetVertexMask(IN.color);
                vertexMask = Contrast01(vertexMask, max(1.0h, _LayerContrast));

                half upMask = saturate(layerNormalWS.y);
                half useVC = saturate(_UseVertexColor);
                half blendMask = lerp(upMask, vertexMask, useVC);

                blendMask = saturate(blendMask + _LayerPower);
                blendMask = lerp(blendMask, smoothstep(0.2h, 0.8h, blendMask), saturate(_LayerThreshold));

                half3 finalAlbedo = lerp(baseAlbedo, layerAlbedo, blendMask);

                #if defined(_SEEVERTEXCOLORS_ON)
                    finalAlbedo = IN.color.rgb;
                #endif

                half3 finalNormalWS = normalize(lerp(meshNormalWS, layerNormalWS, blendMask));

                half4 baseMRA = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, uvMRA);
                half4 layerMRA = SampleTriplanarColor(
                    TEXTURE2D_ARGS(_DetailMetallicGlossMap, sampler_DetailMetallicGlossMap),
                    worldPos, baseNormalWS, _Tiling
                );

                half metallic = saturate(lerp(baseMRA.r, layerMRA.r, blendMask) + _MetallicPower);
                half smoothness = saturate(lerp(baseMRA.a, layerMRA.a, blendMask) * _SmoothnessPower);
                half occlusion = pow(saturate(lerp(baseMRA.g, layerMRA.g, blendMask)), max(_OcclusionPower, 0.0001));

                Light mainLight = GetMainLight(IN.shadowCoord);
                half3 viewDirWS = normalize(GetWorldSpaceViewDir(worldPos));

                half ndotl = saturate(dot(finalNormalWS, mainLight.direction));
                half lightAtten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half litTerm = ndotl * lightAtten;

                // 使用全局 Toon 参数
                half3 shadowColor = _GlobalToonShadowColor.rgb;
                half toonThreshold = _GlobalToonThreshold;
                half toonSmoothness = _GlobalToonSmoothness;

                half toonStep = smoothstep(
                    toonThreshold - toonSmoothness,
                    toonThreshold + toonSmoothness,
                    litTerm
                );

                half3 diffuse = lerp(finalAlbedo * shadowColor, finalAlbedo, toonStep) * mainLight.color;
                half3 ambient = finalAlbedo * SampleSH(finalNormalWS) * occlusion;

                half3 halfDir = normalize(mainLight.direction + viewDirWS);
                half spec = pow(saturate(dot(finalNormalWS, halfDir)), lerp(8.0h, 128.0h, smoothness));
                half3 specular = spec * metallic * mainLight.color * lightAtten;

                half3 finalColor = diffuse + ambient + specular;
                finalColor = MixFog(finalColor, IN.fogFactor);

                return half4(finalColor, 1.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

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
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}