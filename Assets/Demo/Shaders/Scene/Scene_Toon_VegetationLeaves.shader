Shader "ToonRenderFramework/Scene/Lit/VegetationLeaves"
{
    Properties
    {
        [Toggle(_HIDESIDES_ON)] _HideSides("Hide Sides", Float) = 0
        _HidePower("Hide Power", Float) = 2.5
        _Cutoff("Mask Clip Value", Range(0,1)) = 0.5

        [Header(Main Maps)]
        _MainColor("Main Color", Color) = (1,1,1,1)
        _Diffuse("Diffuse", 2D) = "white" {}

        [Header(Gradient Parameters)]
        _GradientColor("Gradient Color", Color) = (1,1,1,1)
        _GradientFalloff("Gradient Falloff", Range(0.01,2)) = 2
        _GradientPosition("Gradient Position", Range(0,1)) = 0.5
        [Toggle(_INVERTGRADIENT_ON)] _InvertGradient("Invert Gradient", Float) = 0

        [Header(Color Variation)]
        _ColorVariation("Color Variation", Color) = (1,0,0,1)
        _ColorVariationPower("Color Variation Power", Range(0,1)) = 1
        _ColorVariationNoise("Color Variation Noise", 2D) = "white" {}
        _NoiseScale("Noise Scale", Float) = 0.5

        [Header(Wind)]
        _WindMultiplier("BaseWind Multiplier", Float) = 0
        _MicroWindMultiplier("MicroWind Multiplier", Float) = 1
        [KeywordEnum(R,G,B,A)] _BaseWindChannel("Base Wind Channel", Float) = 2
        [KeywordEnum(R,G,B,A)] _MicroWindChannel("Micro Wind Channel", Float) = 0
        _WindTrunkPosition("Wind Trunk Position", Float) = 0
        _WindTrunkContrast("Wind Trunk Contrast", Float) = 10
        _WindSpeed("Wind Speed", Float) = 1
        _WindPower("Wind Power", Float) = 1
        _WindBurstsSpeed("Wind Bursts Speed", Float) = 1
        _WindBurstsScale("Wind Bursts Scale", Float) = 1
        _WindBurstsPower("Wind Bursts Power", Float) = 1
        _MicroFrequency("Micro Frequency", Float) = 1
        _MicroSpeed("Micro Speed", Float) = 1
        _MicroPower("Micro Power", Float) = 1

        [Toggle(_WINDDEBUGVIEW_ON)] _WindDebugView("WindDebugView", Float) = 0
        [Toggle(_SEEVERTEXCOLOR_ON)] _SeeVertexColor("See Vertex Color", Float) = 0

        [Header(Toon Lighting)]
        _ShadowColor("Shadow Color (Local Backup)", Color) = (0.75, 0.80, 0.90, 1)
        _ToonThreshold("Toon Threshold (Local Backup)", Range(0,1)) = 0.5
        _ToonSmoothness("Toon Smoothness (Local Backup)", Range(0.001,0.3)) = 0.06

        [Header(Translucency)]
        _Translucency("Strength", Range(0,50)) = 1
        _TransNormalDistortion("Normal Distortion", Range(0,1)) = 0.1
        _TransScattering("Scattering Falloff", Range(1,50)) = 2
        _TransDirect("Direct", Range(0,1)) = 1
        _TransAmbient("Ambient", Range(0,1)) = 0.2
        _TransShadow("Shadow", Range(0,1)) = 0.9
    }

    SubShader
    {
        Tags
        {
            "RenderType"="TransparentCutout"
            "Queue"="AlphaTest"
            "RenderPipeline"="UniversalPipeline"
        }

        Cull Back

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

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
            #pragma multi_compile_fog

            #pragma shader_feature_local _BASEWINDCHANNEL_R _BASEWINDCHANNEL_G _BASEWINDCHANNEL_B _BASEWINDCHANNEL_A
            #pragma shader_feature_local _MICROWINDCHANNEL_R _MICROWINDCHANNEL_G _MICROWINDCHANNEL_B _MICROWINDCHANNEL_A
            #pragma shader_feature_local _SEEVERTEXCOLOR_ON
            #pragma shader_feature_local _WINDDEBUGVIEW_ON
            #pragma shader_feature_local _INVERTGRADIENT_ON
            #pragma shader_feature_local _HIDESIDES_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_Diffuse);
            SAMPLER(sampler_Diffuse);

            TEXTURE2D(_ColorVariationNoise);
            SAMPLER(sampler_ColorVariationNoise);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainColor;
                float4 _GradientColor;
                float4 _ColorVariation;
                float4 _Diffuse_ST;

                float _GradientFalloff;
                float _GradientPosition;
                float _ColorVariationPower;
                float _NoiseScale;

                float _WindMultiplier;
                float _MicroWindMultiplier;
                float _WindTrunkPosition;
                float _WindTrunkContrast;
                float _WindSpeed;
                float _WindPower;
                float _WindBurstsSpeed;
                float _WindBurstsScale;
                float _WindBurstsPower;
                float _MicroFrequency;
                float _MicroSpeed;
                float _MicroPower;

                float4 _ShadowColor;
                float _ToonThreshold;
                float _ToonSmoothness;

                float _Translucency;
                float _TransNormalDistortion;
                float _TransScattering;
                float _TransDirect;
                float _TransAmbient;
                float _TransShadow;

                float _HidePower;
                float _Cutoff;
            CBUFFER_END

            // 全局 Toon 参数
            float4 _GlobalToonShadowColor;
            float _GlobalToonThreshold;
            float _GlobalToonSmoothness;

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
                float4 positionCS  : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                half3 normalWS     : TEXCOORD1;
                float2 uv          : TEXCOORD2;
                half4 color        : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
                half3 viewDirWS    : TEXCOORD5;
                float4 screenPos   : TEXCOORD6;
                half fogFactor     : TEXCOORD7;
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

                float3 m = max(0.5 - float3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
                m *= m;
                m *= m;

                float3 x = 2.0 * frac(p * C.www) - 1.0;
                float3 h = abs(x) - 0.5;
                float3 ox = floor(x + 0.5);
                float3 a0 = x - ox;

                m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);

                float3 g;
                g.x = a0.x * x0.x + h.x * x0.y;
                g.yz = a0.yz * x12.xz + h.yz * x12.yw;

                return 130.0 * dot(m, g);
            }

            float4 ApplyContrast(float contrastValue, float4 colorTarget)
            {
                float t = 0.5 * (1.0 - contrastValue);
                return mul(float4x4(
                    contrastValue, 0, 0, t,
                    0, contrastValue, 0, t,
                    0, 0, contrastValue, t,
                    0, 0, 0, 1), colorTarget);
            }

            float GetBaseWindChannel(float4 c)
            {
                #if defined(_BASEWINDCHANNEL_R)
                    return c.r;
                #elif defined(_BASEWINDCHANNEL_G)
                    return c.g;
                #elif defined(_BASEWINDCHANNEL_B)
                    return c.b;
                #elif defined(_BASEWINDCHANNEL_A)
                    return c.a;
                #else
                    return c.b;
                #endif
            }

            float GetMicroWindChannel(float4 c)
            {
                #if defined(_MICROWINDCHANNEL_R)
                    return c.r;
                #elif defined(_MICROWINDCHANNEL_G)
                    return c.g;
                #elif defined(_MICROWINDCHANNEL_B)
                    return c.b;
                #elif defined(_MICROWINDCHANNEL_A)
                    return c.a;
                #else
                    return c.r;
                #endif
            }

            float Dither8x8Bayer(int x, int y)
            {
                const float dither[64] = {
                    1,49,13,61,4,52,16,64,
                    33,17,45,29,36,20,48,32,
                    9,57,5,53,12,60,8,56,
                    41,25,37,21,44,28,40,24,
                    3,51,15,63,2,50,14,62,
                    35,19,47,31,34,18,46,30,
                    11,59,7,55,10,58,6,54,
                    43,27,39,23,42,26,38,22
                };

                int index = y * 8 + x;
                return dither[index] / 64.0;
            }

            float3 ApplyVegetationWind(float3 positionOS, float3 normalOS, float3 positionWS0, float4 color)
            {
                float timeValue = _Time.y * _WindSpeed;

                float2 burstUV = positionWS0.xz + float2(_WindBurstsSpeed, _WindBurstsSpeed) * _Time.y;
                float burstNoise = SimplexNoise(burstUV * (_WindBurstsScale / 10.0));
                burstNoise = burstNoise * 0.5 + 0.5;
                float burst = _WindPower * (burstNoise * _WindBurstsPower);

                float baseWindMask = GetBaseWindChannel(color);
                float4 trunkMask = saturate(ApplyContrast(_WindTrunkContrast, pow(1.0 - baseWindMask, _WindTrunkPosition).xxxx));

                float3 baseWindWS = float3(
                    sin(timeValue) * burst * trunkMask.r,
                    0.0,
                    cos(timeValue) * (burst * 0.5) * trunkMask.r
                );
                float3 baseWindOS = TransformWorldToObjectDir(baseWindWS) * _WindMultiplier;

                float2 microUV = positionWS0.xz + _Time.y * _MicroSpeed.xx;
                float microNoise = SimplexNoise(microUV);
                microNoise = microNoise * 0.5 + 0.5;

                float3 microWave = clamp(sin(_MicroFrequency * (positionWS0 + microNoise)), -1.0, 1.0);
                float microWindMask = GetMicroWindChannel(color);
                float3 microWindOS = (((microWave * normalOS) * _MicroPower) * microWindMask) * _MicroWindMultiplier;

                return positionOS + baseWindOS + microWindOS;
            }

            half3 EvaluateLeafBaseColor(Varyings IN, half4 diffuseTex)
            {
                half worldY = IN.normalWS.y;
                half gradientMask;

                #if defined(_INVERTGRADIENT_ON)
                    gradientMask = 1.0h - worldY;
                #else
                    gradientMask = worldY;
                #endif

                gradientMask = saturate((gradientMask + (-2.0h + (half)_GradientPosition * 3.0h)) / max((half)_GradientFalloff, 0.0001h));
                half4 gradientColor = lerp((half4)_MainColor, (half4)_GradientColor, gradientMask);

                half noiseValue = SAMPLE_TEXTURE2D(_ColorVariationNoise, sampler_ColorVariationNoise, IN.positionWS.xz * (_NoiseScale / 100.0)).r;
                half blendT = (half)_ColorVariationPower * pow(noiseValue, 3.0h);

                half4 variedColor = lerp(
                    gradientColor,
                    saturate((half4)_ColorVariation / max(1.0h - gradientColor, 0.00001h)),
                    blendT
                );

                return (variedColor * diffuseTex).rgb;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionWS0 = TransformObjectToWorld(IN.positionOS.xyz);
                float3 bentPositionOS = ApplyVegetationWind(IN.positionOS.xyz, IN.normalOS, positionWS0, IN.color);

                VertexPositionInputs posInputs = GetVertexPositionInputs(bentPositionOS);
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS = NormalizeNormalPerVertex(normInputs.normalWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _Diffuse);
                OUT.color = IN.color;
                OUT.shadowCoord = GetShadowCoord(posInputs);
                OUT.viewDirWS = normalize(GetWorldSpaceViewDir(posInputs.positionWS));
                OUT.screenPos = ComputeScreenPos(posInputs.positionCS);
                OUT.fogFactor = ComputeFogFactor(posInputs.positionCS.z);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                #if defined(_WINDDEBUGVIEW_ON)
                    return half4(abs(IN.color.rgb), 1.0h);
                #endif

                #if defined(_SEEVERTEXCOLOR_ON)
                    return half4(IN.color.rgb, 1.0h);
                #endif

                half4 diffuseTex = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, IN.uv);
                half opacity = diffuseTex.a;

                #if defined(_HIDESIDES_ON)
                    float4 screenPosNorm = IN.screenPos / IN.screenPos.w;
                    float2 clipScreen = screenPosNorm.xy * _ScreenParams.xy;

                    float3 ddxPos = ddx(IN.positionWS);
                    float3 ddyPos = ddy(IN.positionWS);
                    float3 faceNormal = normalize(cross(ddyPos, ddxPos));

                    half3 viewDir = normalize(IN.viewDirWS);
                    half facing = abs(dot(viewDir, faceNormal));
                    half hideOpacity = saturate((opacity * (1.0h - ((1.0h - facing) * 2.0h))) * (half)_HidePower);

                    half dither = Dither8x8Bayer((int)fmod(clipScreen.x, 8), (int)fmod(clipScreen.y, 8));
                    opacity = step(dither, hideOpacity);
                #endif

                clip(opacity - (half)_Cutoff);

                half3 albedo = EvaluateLeafBaseColor(IN, diffuseTex);

                half3 normalWS = normalize(IN.normalWS);
                Light mainLight = GetMainLight(IN.shadowCoord);
                half3 viewDirWS = normalize(IN.viewDirWS);

                half ndotl = saturate(dot(normalWS, mainLight.direction));
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

                half3 diffuse = lerp(albedo * shadowColor, albedo, toonStep) * mainLight.color;
                half3 ambient = albedo * 0.2h;

                half3 transLightAtten = mainLight.color * lerp(1.0h, mainLight.shadowAttenuation, (half)_TransShadow);
                half3 transLightDir = normalize(mainLight.direction + normalWS * (half)_TransNormalDistortion);
                half transVdotL = pow(saturate(dot(viewDirWS, -transLightDir)), (half)_TransScattering);
                half3 translucency = transLightAtten * (transVdotL * (half)_TransDirect + (half)_TransAmbient) * (half)_Translucency;

                half3 finalColor = diffuse + ambient + albedo * translucency;
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
            #pragma multi_compile_instancing
            #pragma shader_feature_local _BASEWINDCHANNEL_R _BASEWINDCHANNEL_G _BASEWINDCHANNEL_B _BASEWINDCHANNEL_A
            #pragma shader_feature_local _MICROWINDCHANNEL_R _MICROWINDCHANNEL_G _MICROWINDCHANNEL_B _MICROWINDCHANNEL_A

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_Diffuse);
            SAMPLER(sampler_Diffuse);

            CBUFFER_START(UnityPerMaterial)
                float4 _Diffuse_ST;
                float _WindMultiplier;
                float _MicroWindMultiplier;
                float _WindTrunkPosition;
                float _WindTrunkContrast;
                float _WindSpeed;
                float _WindPower;
                float _WindBurstsSpeed;
                float _WindBurstsScale;
                float _WindBurstsPower;
                float _MicroFrequency;
                float _MicroSpeed;
                float _MicroPower;
                float _Cutoff;
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

                float3 m = max(0.5 - float3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
                m *= m;
                m *= m;

                float3 x = 2.0 * frac(p * C.www) - 1.0;
                float3 h = abs(x) - 0.5;
                float3 ox = floor(x + 0.5);
                float3 a0 = x - ox;

                m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);

                float3 g;
                g.x = a0.x * x0.x + h.x * x0.y;
                g.yz = a0.yz * x12.xz + h.yz * x12.yw;

                return 130.0 * dot(m, g);
            }

            float4 ApplyContrast(float contrastValue, float4 colorTarget)
            {
                float t = 0.5 * (1.0 - contrastValue);
                return mul(float4x4(
                    contrastValue, 0, 0, t,
                    0, contrastValue, 0, t,
                    0, 0, contrastValue, t,
                    0, 0, 0, 1), colorTarget);
            }

            float GetBaseWindChannel(float4 c)
            {
                #if defined(_BASEWINDCHANNEL_R)
                    return c.r;
                #elif defined(_BASEWINDCHANNEL_G)
                    return c.g;
                #elif defined(_BASEWINDCHANNEL_B)
                    return c.b;
                #elif defined(_BASEWINDCHANNEL_A)
                    return c.a;
                #else
                    return c.b;
                #endif
            }

            float GetMicroWindChannel(float4 c)
            {
                #if defined(_MICROWINDCHANNEL_R)
                    return c.r;
                #elif defined(_MICROWINDCHANNEL_G)
                    return c.g;
                #elif defined(_MICROWINDCHANNEL_B)
                    return c.b;
                #elif defined(_MICROWINDCHANNEL_A)
                    return c.a;
                #else
                    return c.r;
                #endif
            }

            float3 ApplyVegetationWind(float3 positionOS, float3 normalOS, float3 positionWS0, float4 color)
            {
                float timeValue = _Time.y * _WindSpeed;

                float2 burstUV = positionWS0.xz + float2(_WindBurstsSpeed, _WindBurstsSpeed) * _Time.y;
                float burstNoise = SimplexNoise(burstUV * (_WindBurstsScale / 10.0));
                burstNoise = burstNoise * 0.5 + 0.5;
                float burst = _WindPower * (burstNoise * _WindBurstsPower);

                float baseWindMask = GetBaseWindChannel(color);
                float4 trunkMask = saturate(ApplyContrast(_WindTrunkContrast, pow(1.0 - baseWindMask, _WindTrunkPosition).xxxx));

                float3 baseWindWS = float3(
                    sin(timeValue) * burst * trunkMask.r,
                    0.0,
                    cos(timeValue) * (burst * 0.5) * trunkMask.r
                );
                float3 baseWindOS = TransformWorldToObjectDir(baseWindWS) * _WindMultiplier;

                float2 microUV = positionWS0.xz + _Time.y * _MicroSpeed.xx;
                float microNoise = SimplexNoise(microUV);
                microNoise = microNoise * 0.5 + 0.5;

                float3 microWave = clamp(sin(_MicroFrequency * (positionWS0 + microNoise)), -1.0, 1.0);
                float microWindMask = GetMicroWindChannel(color);
                float3 microWindOS = (((microWave * normalOS) * _MicroPower) * microWindMask) * _MicroWindMultiplier;

                return positionOS + baseWindOS + microWindOS;
            }

            Varyings ShadowVert(Attributes IN)
            {
                Varyings OUT;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                float3 positionWS0 = TransformObjectToWorld(IN.positionOS.xyz);
                float3 bentPositionOS = ApplyVegetationWind(IN.positionOS.xyz, IN.normalOS, positionWS0, IN.color);

                float3 positionWS = TransformObjectToWorld(bentPositionOS);
                OUT.positionCS = TransformWorldToHClip(positionWS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _Diffuse);

                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target
            {
                half alpha = SAMPLE_TEXTURE2D(_Diffuse, sampler_Diffuse, IN.uv).a;
                clip(alpha - (half)_Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}