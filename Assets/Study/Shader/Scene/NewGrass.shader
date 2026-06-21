Shader "ToonRenderFramework/Scene/Lit/NewGrass"
{
    Properties
    {
        _Cutoff("Mask Clip Value", Range(0,1)) = 0.29

        [Space(10)]
        _Color01("Color 01", Color) = (0.5613207,0.8245283,1,1)
        _Color02("Color 02", Color) = (1,1,1,1)

        [Space(10)]
        _MainTex("Texture", 2D) = "white" {}

        _ColorVariationPower("Color Variation Power", Range(0,1)) = 1
        _Noise("Noise", 2D) = "white" {}
        _NoiseTiling("Noise Tiling", Float) = 1.09

        [Space(20)]
        _Smoothness("Smoothness", Range(0,1)) = 0.2

        [Space(20)]
        _MicroSpeed("Micro Speed", Float) = 2
        _MicroFrequency("Micro Frequency", Float) = 3
        _MicroPower("Micro Power", Float) = 0.05

        [Toggle(_WINDDEBUGVIEW_ON)] _WindDebugView("WindDebugView", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"="TransparentCutout"
            "Queue"="AlphaTest"
            "RenderPipeline"="UniversalPipeline"
        }

        Cull Off

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            Blend One Zero
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_instancing
            #pragma shader_feature_local _WINDDEBUGVIEW_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_Noise);
            SAMPLER(sampler_Noise);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color01;
                float4 _Color02;
                float4 _MainTex_ST;
                float _ColorVariationPower;
                float _NoiseTiling;
                float _Cutoff;
                float _Smoothness;
                float _MicroSpeed;
                float _MicroFrequency;
                float _MicroPower;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                half3 normalWS     : TEXCOORD1;
                float2 uv          : TEXCOORD2;
                half4 color        : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float3 Mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            float2 Mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            float3 Permute(float3 x) { return Mod289(((x * 34.0) + 1.0) * x); }

            float SimplexNoise(float2 v)
            {
                const float4 C = float4(
                    0.211324865405187,
                    0.366025403784439,
                    -0.577350269189626,
                    0.024390243902439
                );

                float2 i = floor(v + dot(v, C.yy));
                float2 x0 = v - i + dot(i, C.xx);

                float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
                float4 x12 = x0.xyxy + C.xxzz;
                x12.xy -= i1;

                i = Mod289(i);
                float3 p = Permute(Permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));

                float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
                m = m * m;
                m = m * m;

                float3 x = 2.0 * frac(p * C.www) - 1.0;
                float3 h = abs(x) - 0.5;
                float3 ox = floor(x + 0.5);
                float3 a0 = x - ox;

                m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

                float3 g;
                g.x = a0.x * x0.x + h.x * x0.y;
                g.yz = a0.yz * x12.xz + h.yz * x12.yw;

                return 130.0 * dot(m, g);
            }

            float3 ApplyMicroWindOffset(float3 positionOS, float3 positionWS, float2 uv, float4 color)
            {
                float3 swizzledWS = float3(positionWS.z, positionWS.y, positionWS.x);
                float2 noiseUV = swizzledWS.xy + _Time.y * (_MicroSpeed * 0.5).xx;

                float noiseValue = SimplexNoise(noiseUV);
                noiseValue = noiseValue * 0.5 + 0.5;

                float3 wave = sin((swizzledWS + noiseValue) * (_MicroFrequency * 2.0));
                float3 microWind = ((wave * uv.y) * _MicroPower) * color.r;
                microWind *= float3(12.0, 3.6, 1.0);
                microWind *= 0.01;

                return positionOS + microWind;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionWSOriginal = TransformObjectToWorld(IN.positionOS.xyz);
                float3 bentPositionOS = ApplyMicroWindOffset(IN.positionOS.xyz, positionWSOriginal, IN.uv, IN.color);

                VertexPositionInputs positionInputs = GetVertexPositionInputs(bentPositionOS);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionCS = positionInputs.positionCS;
                OUT.positionWS = positionInputs.positionWS;
                OUT.normalWS = NormalizeNormalPerVertex(normalInputs.normalWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.color = IN.color;
                OUT.shadowCoord = GetShadowCoord(positionInputs);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                float2 worldUV = IN.positionWS.xz;
                half noiseValue = SAMPLE_TEXTURE2D(_Noise, sampler_Noise, worldUV * _NoiseTiling).r;
                half3 variationColor = lerp(_Color01.rgb, _Color02.rgb, _ColorVariationPower * noiseValue);

                half4 mainTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                clip(mainTex.a - _Cutoff);

                half3 baseColor;
                #if defined(_WINDDEBUGVIEW_ON)
                    baseColor = abs(IN.color.r).xxx;
                #else
                    baseColor = variationColor * mainTex.rgb;
                #endif

                half3 normalWS = normalize(IN.normalWS);
                Light mainLight = GetMainLight(IN.shadowCoord);

                half NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = baseColor * (0.25h + NdotL * mainLight.color * mainLight.shadowAttenuation);

                half3 viewDirWS = normalize(GetWorldSpaceViewDir(IN.positionWS));
                half3 halfDir = normalize(mainLight.direction + viewDirWS);
                half spec = pow(saturate(dot(normalWS, halfDir)), lerp(8.0h, 64.0h, (half)_Smoothness));
                half3 specular = spec * mainLight.color * (half)_Smoothness * mainLight.shadowAttenuation;

                return half4(diffuse + specular, 1.0h);
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
            Cull Off

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float _Cutoff;
                float _MicroSpeed;
                float _MicroFrequency;
                float _MicroPower;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float4 color      : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            float3 Mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            float2 Mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
            float3 Permute(float3 x) { return Mod289(((x * 34.0) + 1.0) * x); }

            float SimplexNoise(float2 v)
            {
                const float4 C = float4(
                    0.211324865405187,
                    0.366025403784439,
                    -0.577350269189626,
                    0.024390243902439
                );

                float2 i = floor(v + dot(v, C.yy));
                float2 x0 = v - i + dot(i, C.xx);

                float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
                float4 x12 = x0.xyxy + C.xxzz;
                x12.xy -= i1;

                i = Mod289(i);
                float3 p = Permute(Permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));

                float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
                m = m * m;
                m = m * m;

                float3 x = 2.0 * frac(p * C.www) - 1.0;
                float3 h = abs(x) - 0.5;
                float3 ox = floor(x + 0.5);
                float3 a0 = x - ox;

                m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

                float3 g;
                g.x = a0.x * x0.x + h.x * x0.y;
                g.yz = a0.yz * x12.xz + h.yz * x12.yw;

                return 130.0 * dot(m, g);
            }

            float3 ApplyMicroWindOffset(float3 positionOS, float3 positionWS, float2 uv, float4 color)
            {
                float3 swizzledWS = float3(positionWS.z, positionWS.y, positionWS.x);
                float2 noiseUV = swizzledWS.xy + _Time.y * (_MicroSpeed * 0.5).xx;

                float noiseValue = SimplexNoise(noiseUV);
                noiseValue = noiseValue * 0.5 + 0.5;

                float3 wave = sin((swizzledWS + noiseValue) * (_MicroFrequency * 2.0));
                float3 microWind = ((wave * uv.y) * _MicroPower) * color.r;
                microWind *= float3(12.0, 3.6, 1.0);
                microWind *= 0.01;

                return positionOS + microWind;
            }

            Varyings ShadowVert(Attributes IN)
            {
                Varyings OUT;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                float3 positionWSOriginal = TransformObjectToWorld(IN.positionOS.xyz);
                float3 bentPositionOS = ApplyMicroWindOffset(IN.positionOS.xyz, positionWSOriginal, IN.uv, IN.color);

                float3 positionWS = TransformObjectToWorld(bentPositionOS);
                OUT.positionCS = TransformWorldToHClip(positionWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);

                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).a;
                clip(alpha - _Cutoff);

                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}