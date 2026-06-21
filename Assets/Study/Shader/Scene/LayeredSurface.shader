Shader "ToonRenderFramework/Scene/Lit/NewLayeredSurface"
{
    Properties
    {
        [Header(Base Layer)]
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [NoScaleOffset] _BaseNormalMap("Base Normal", 2D) = "bump" {}
        _BaseNormalScale("Base Normal Scale", Range(0,2)) = 1

        [Header(Deposit Layer)]
        _LayerMap("Layer Map", 2D) = "white" {}
        _LayerColor("Layer Color", Color) = (1,1,1,1)
        _LayerNormalMap("Layer Normal", 2D) = "bump" {}
        _LayerNormalScale("Layer Normal Scale", Range(0,2)) = 1
        _LayerTiling("Layer Tiling", Float) = 1

        [Header(Mask)]
        [Toggle]_UseVertexColor("Use Vertex Color", Float) = 0
        [KeywordEnum(R,G,B,A)] _VertexColorChannel("Vertex Color Channel", Float) = 2
        _LayerPower("Layer Power", Range(0,1)) = 0.5
        _LayerContrast("Layer Contrast", Range(0,4)) = 1

        [Header(Toon Lighting)]
        _ShadowColor("Shadow Color", Color) = (0.75, 0.80, 0.90, 1)
        _ToonThreshold("Toon Threshold", Range(0,1)) = 0.5
        _ToonSmoothness("Toon Smoothness", Range(0.001,0.3)) = 0.06

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

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

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

            #pragma shader_feature_local _SEEVERTEXCOLORS_ON
            #pragma shader_feature_local _VERTEXCOLORCHANNEL_R _VERTEXCOLORCHANNEL_G _VERTEXCOLORCHANNEL_B _VERTEXCOLORCHANNEL_A

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BaseNormalMap); SAMPLER(sampler_BaseNormalMap);
            TEXTURE2D(_LayerMap); SAMPLER(sampler_LayerMap);
            TEXTURE2D(_LayerNormalMap); SAMPLER(sampler_LayerNormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _BaseNormalScale;

                half4 _LayerColor;
                half _LayerNormalScale;
                float _LayerTiling;

                half _UseVertexColor;
                half _LayerPower;
                half _LayerContrast;

                half4 _ShadowColor;
                half _ToonThreshold;
                half _ToonSmoothness;
            CBUFFER_END

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
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
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
                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 baseAlbedo = baseTex.rgb * _BaseColor.rgb;

                half3 baseNormalWS = normalize(IN.normalWS);

                half3 tangentWS = normalize(IN.tangentWS.xyz);
                half tangentSign = IN.tangentWS.w;
                half3 bitangentWS = normalize(cross(baseNormalWS, tangentWS) * tangentSign);
                half3x3 tbn = half3x3(tangentWS, bitangentWS, baseNormalWS);

                half3 baseNormalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_BaseNormalMap, sampler_BaseNormalMap, IN.uv),
                    _BaseNormalScale
                );
                half3 meshNormalWS = normalize(mul(baseNormalTS, tbn));

                half4 layerTex = SampleTriplanarColor(
                    TEXTURE2D_ARGS(_LayerMap, sampler_LayerMap),
                    IN.positionWS,
                    baseNormalWS,
                    _LayerTiling
                );
                half3 layerAlbedo = layerTex.rgb * _LayerColor.rgb;

                half3 layerNormalWS = SampleTriplanarNormalWS(
                    TEXTURE2D_ARGS(_LayerNormalMap, sampler_LayerNormalMap),
                    IN.positionWS,
                    baseNormalWS,
                    _LayerTiling,
                    _LayerNormalScale
                );

                half mask;
                if (_UseVertexColor > 0.5h)
                {
                    mask = GetVertexMask(IN.color);
                    mask = Contrast01(mask, _LayerContrast);
                }
                else
                {
                    mask = saturate(layerNormalWS.y);
                }

                mask = saturate(pow(mask, max(0.001h, 1.0h - _LayerPower)));

                half3 finalAlbedo = lerp(baseAlbedo, layerAlbedo, mask);

                #if defined(_SEEVERTEXCOLORS_ON)
                    finalAlbedo = IN.color.rgb;
                #endif

                half3 finalNormalWS = normalize(lerp(meshNormalWS, layerNormalWS, mask));

                Light mainLight = GetMainLight(IN.shadowCoord);

                half ndotl = saturate(dot(finalNormalWS, mainLight.direction));
                half lightAtten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half litTerm = ndotl * lightAtten;

                half toonStep = smoothstep(
                    _ToonThreshold - _ToonSmoothness,
                    _ToonThreshold + _ToonSmoothness,
                    litTerm
                );

                half3 diffuse = lerp(finalAlbedo * _ShadowColor.rgb, finalAlbedo, toonStep) * mainLight.color;
                half3 ambient = finalAlbedo * SampleSH(finalNormalWS);

                half3 finalColor = diffuse + ambient;
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