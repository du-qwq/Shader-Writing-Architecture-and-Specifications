Shader "Custom/SkyboxSingleScattering"
{
    Properties
    {
        _SunIntensity("Sun Intensity",Float)=20
        _Exposure("Exposure",Float)=1
        _PlanetRadius("Planet Radius",Float)=6371000
        _AtmosphereHeight("Atmosphere Height",Float)=100000
        _RayleighScaleHeight("Rayleigh Scale Height",Float)=8500
        _MieScaleHeight("Mie Scale Height",Float)=1200
        _MieG("Mie Anisotropy",Range(-0.99,0.99))=0.76
        
        _SunDiskColor("Sun Disk Color",Color)=(1,1,1,1)
        _SunDiskIntensity("Sun Disk Intensity",Float)=20
        _SunDiskAngularRadius("Sun Disk Angular Radius (Deg)",Float)=0.27
        _SunDiskSoftness("Sun Disk Softness (Deg)",Float)=0.15
        _SunGlowIntensity("Sun Glow Intensity",Float)=2
        _SunGlowSize("Sun Glow Size (Deg)",Float)=2
        
        _TransmittanceLut("Transmittance LUT",2D)="white"{}
        _SkyViewLut("Sky View LUT",2D)="black"{}
    }
    SubShader
    {
        Tags
        {
            "Queue"="Background"
            "RenderType"="Background"
            "PreviewType"="Skybox"
        }
        
        Cull Off
        ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            #define PI 3.14159265359
            #define VIEW_SAMPLE_COUNT 24
            #define LIGHT_SAMPLE_COUNT 32

            TEXTURE2D(_TransmittanceLut);
            SAMPLER(sampler_TransmittanceLut);
            TEXTURE2D(_SkyViewLut);
            SAMPLER(sampler_SkyViewLut);

            CBUFFER_START(UnityPerMaterial)
                float _SunIntensity;
                float _Exposure;
                float _PlanetRadius;
                float _AtmosphereHeight;
                float _RayleighScaleHeight;
                float _MieScaleHeight;
                float _MieG;

                float3 _SunDirWS;
                float3 _PlanetCenterWS;

                float4 _SunDiskColor;
                float _SunDiskIntensity;
                float _SunDiskAngularRadius;
                float _SunDiskSoftness;
                float _SunGlowIntensity;
                float _SunGlowSize;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS:POSITION;
            };

            struct Varyings
            {
                float4 positionCS:SV_POSITION;
                float3 dirWS:TEXCOORD0;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS=TransformObjectToHClip(IN.positionOS.xyz);
                float3 dirWS=mul((float3x3)unity_ObjectToWorld,IN.positionOS.xyz);
                OUT.dirWS=normalize(dirWS);

                return OUT;
            }

            //射线和球求交
            float2 RaySphere(float3 rayOrigin,float3 rayDir,float3 sphereCenter,float sphereRadius)
            {
                float3 oc=rayOrigin-sphereCenter;
                float b=dot(oc,rayDir);
                float c=dot(oc,oc)-sphereRadius*sphereRadius;
                float h=b*b-c;
                if (h<0)
                {
                    return float2(-1,-1);
                }
                h=sqrt(h);
                
                return float2(-b-h,-b+h);
            }
            //高度计算
            float GetHeight(float3 p)
            {
                return max(0,length(p-_PlanetCenterWS)-_PlanetRadius);
            }
            //瑞利散射系数
            float3 RayleighCoefficient(float h)
            {
                float3 sigma=float3(5.802,13.558,33.1)*1e-6;
                float rho=exp(-h/_RayleighScaleHeight);
                return sigma*rho;
            }
            //瑞利相位函数
            float RayleighPhase(float cosTheta)
            {
                return 3/(16*PI)*(1+cosTheta*cosTheta);
            }
            //米氏散射系数
            float3 MieCoefficient(float h)
            {
                float3 sigma=float3(3.996,3.996,3.996)*1e-6;
                //float3 sigma=float3(0.05,0.05,0.05)*1e-6;
                //float3 sigma=float3(0.5,0.5,0.5)*1e-6;
                float rho=exp(-h/_MieScaleHeight);
                return sigma*rho;
                // //return 0.0;
            }
            //米氏相位函数
            float MiePhase(float cosTheta)
            {
                float g=_MieG;
                float a=3/(8*PI);
                float b=(1-g*g)/(2+g*g);
                float c=1+cosTheta*cosTheta;
                float d=pow(max(0.0001,1+g*g-2*g*cosTheta),1.5);
                float phase=a*b*c/d;
                return phase;
                //return min(phase,2.0);
            }
            //米氏吸收
            float3 MieAbsorption(float h)
            {
                float3 sigma=float3(4.4,4.4,4.4)*1e-6;
                float rho=exp(-h/_MieScaleHeight);
                return sigma*rho;
            }
            //臭氧吸收
            float3 OzoneAbsorption(float h)
            {
                float3 sigma=float3(0.650,1.881,0.085)*1e-6;
                float center=25000;
                float width=15000;
                float rho=max(0,1-abs(h-center)/width);

                return sigma*rho;
            }
            //总消光系数
            float3 ExtinctionCoefficient(float h)
            {
                float3 scattering=RayleighCoefficient(h)+MieCoefficient(h);
                float3 absorption=MieAbsorption(h)+OzoneAbsorption(h);
                return scattering+absorption;
            }
            //当前点的散射贡献系数
            float3 ScatteringCoefficient(float h,float cosTheta)
            {
                float3 rayleigh=RayleighCoefficient(h)*RayleighPhase(cosTheta);
                float3 mie=MieCoefficient(h)*MiePhase(cosTheta);
                float a=0.5;
                //return a*rayleigh+(1-a)*mie;
                return rayleigh+0.6*mie;
            }
            //p1到p2透射率
            float3 TransmittanceSegment(float3 p1,float3 p2)
            {
                float3 dir=p2-p1;
                float distance=length(dir);
                if (distance<=0.0001)
                {
                    return 1.0;
                }
                dir/=distance;
                float ds=distance/LIGHT_SAMPLE_COUNT;
                float3 sum=0.0;
                float3 p=p1+dir*ds*0.5;

                [loop]
                for(int i=0;i<LIGHT_SAMPLE_COUNT;i++)
                {
                    float h=GetHeight(p);
                    float3 extinction=ExtinctionCoefficient(h);
                    sum+=extinction*ds;
                    p+=dir*ds;
                }
                return exp(-sum);
            }
            //太阳到采样点的透射率
            float3 SunTransmittance(float3 p,float3 sunDir)
            {
                float atmosphereRadius=_PlanetRadius+_AtmosphereHeight;
                float2 planetHit=RaySphere(p,sunDir,_PlanetCenterWS,_PlanetRadius);
                if(planetHit.x>0.0)
                {
                    return 0.0;
                }
                float2 atmosphereHit=RaySphere(p,sunDir,_PlanetCenterWS,atmosphereRadius);
                if(atmosphereHit.y<0.0)
                {
                    return 0.0;
                }
                float tStart=max(atmosphereHit.x,0.0);
                float tEnd=atmosphereHit.y;

                float3 pStart=p+sunDir*tStart;
                float3 pEnd=p+sunDir*tEnd;

                return TransmittanceSegment(pStart,pEnd);
            }

            float SunDiskMask(float3 rayDir,float3 sunDir)
            {
                float cosTheta=dot(normalize(rayDir),normalize(sunDir));

                float sunRadius=radians(_SunDiskAngularRadius);
                float sunSoftness=radians(_SunDiskSoftness);

                float inner=cos(sunRadius);
                float outer=cos(sunRadius+sunSoftness);

                return smoothstep(outer,inner,cosTheta);
            }
            
            float SunGlowMask(float3 rayDir,float3 sunDir)
            {
                float cosTheta=dot(normalize(rayDir), normalize(sunDir));

                float glowRadius=radians(_SunGlowSize);
                float glowOuter=cos(glowRadius);
                float glowInner=cos(radians(_SunDiskAngularRadius));

                float glow=smoothstep(glowOuter,glowInner,cosTheta);
                return glow;
            }
            //查LUT
            float2 GetTransmittanceLutUv(float bottomRadius, float topRadius, float mu, float r)
            {
                float H = sqrt(max(0.0, topRadius * topRadius - bottomRadius * bottomRadius));
                float rho = sqrt(max(0.0, r * r - bottomRadius * bottomRadius));

                float discriminant = r * r * (mu * mu - 1.0) + topRadius * topRadius;
                float d = max(0.0, -r * mu + sqrt(max(0.0, discriminant)));

                float dMin = topRadius - r;
                float dMax = rho + H;

                float xMu = (d - dMin) / max(0.0001, dMax - dMin);
                float xR = rho / max(0.0001, H);

                return saturate(float2(xMu, xR));
            }

            float3 TransmittanceToAtmosphereLut(float3 p, float3 dir)
            {
                float3 localP = p - _PlanetCenterWS;

                float r = length(localP);

                float bottomRadius = _PlanetRadius;
                float topRadius = _PlanetRadius + _AtmosphereHeight;

                r = clamp(r, bottomRadius, topRadius);

                float3 upVector = normalize(localP);
                float mu = dot(upVector, normalize(dir));
                mu = clamp(mu, -1.0, 1.0);

                float2 uv = GetTransmittanceLutUv(bottomRadius, topRadius, mu, r);

                return SAMPLE_TEXTURE2D_LOD(
                    _TransmittanceLut,
                    sampler_TransmittanceLut,
                    uv,
                    0
                ).rgb;
            }

            float2 ViewDirToSkyViewUv(float3 rayDir)
            {
                rayDir = normalize(rayDir);

                float azimuth = atan2(rayDir.z, rayDir.x);
                if (azimuth < 0.0)
                {
                    azimuth += 2.0 * PI;
                }

                float elevation = asin(clamp(rayDir.y, -1.0, 1.0));

                float2 uv;
                uv.x = azimuth / (2.0 * PI);

                // -90° 到 +90° 映射到 0 到 1
                uv.y = elevation / PI + 0.5;

                return saturate(uv);
            }

            float3 SampleSkyViewLut(float3 rayDir)
            {
                float2 uv = ViewDirToSkyViewUv(rayDir);

                return SAMPLE_TEXTURE2D_LOD(
                    _SkyViewLut,
                    sampler_SkyViewLut,
                    uv,
                    0
                ).rgb;
            }
            // half4 frag (Varyings IN) : SV_Target
            // {
            //     float3 cameraPos=_WorldSpaceCameraPos;
            //     float3 rayDir=normalize(IN.dirWS);
            //     float3 sunDir=normalize(_SunDirWS);
            //     if (rayDir.y < 0.0)
            //     {
            //         return float4(0.02, 0.015, 0.01, 1.0);
            //     }
            //
            //     float atmosphereRadius=_PlanetRadius+_AtmosphereHeight;
            //     //视线和大气求交
            //     float2 atmosphereHit=RaySphere(cameraPos,rayDir,_PlanetCenterWS,atmosphereRadius);
            //     if (atmosphereHit.y<0)
            //     {
            //         return float4(0,0,0,1);
            //     }
            //     float tStart=max(0,atmosphereHit.x);
            //     float tEnd=atmosphereHit.y;
            //     float2 planetHit=RaySphere(cameraPos,rayDir,_PlanetCenterWS,_PlanetRadius);
            //     if (planetHit.x>0)
            //     {
            //         tEnd=min(tEnd,planetHit.x);
            //     }
            //     float distance=tEnd-tStart;
            //     if (distance<=0)
            //     {
            //         return float4(0,0,0,1);
            //     }
            //     float ds=distance/VIEW_SAMPLE_COUNT;
            //     float3 color=0.0;
            //     float cosTheta=dot(rayDir,sunDir);
            //     float3 p=cameraPos+rayDir*(tStart+ds*0.5);
            //     float3 opticalDepth=0.0;
            //     [loop]
            //     for (int i=0;i<VIEW_SAMPLE_COUNT;i++)
            //     {
            //         float h=GetHeight(p);
            //         float3 extinction=ExtinctionCoefficient(h);
            //         opticalDepth+=extinction*ds;
            //         //float3 t1=SunTransmittance(p,sunDir);
            //         float3 t1=TransmittanceToAtmosphereLut(p,sunDir);
            //         float3 s=ScatteringCoefficient(h,cosTheta);
            //         //float3 t2=TransmittanceSegment(cameraPos,p);
            //         float3 t2=exp(-opticalDepth);
            //         float3 inScattering=t1*s*t2*ds*_SunIntensity;
            //         color+=inScattering;
            //         p+=rayDir*ds;
            //     }
            //
            //     float sunDisk=SunDiskMask(rayDir,sunDir);
            //     float sunGlow=SunGlowMask(rayDir,sunDir);
            //
            //     color+=_SunDiskColor.rgb*_SunDiskIntensity*sunDisk;
            //     color+=_SunDiskColor.rgb*_SunGlowIntensity*sunGlow;
            //     
            //     color=1-exp(-color*_Exposure);
            //     
            //     return float4(color,1);
            //     //return float4(rayDir * 0.5 + 0.5, 1.0);
            // }
            
            half4 frag(Varyings IN) : SV_Target
            {
                float3 rayDir = normalize(IN.dirWS);
                float3 sunDir = normalize(_SunDirWS);
            
                // 1. 直接从 SkyView LUT 里查天空颜色
                float3 skyRaw = SampleSkyViewLut(rayDir);
            
                // 2. 对天空散射结果做曝光映射
                float3 skyColor = 1.0 - exp(-skyRaw * _Exposure);
            
                // 3. 单独计算太阳圆盘和太阳光晕
                float sunDisk = SunDiskMask(rayDir, sunDir);
                float sunGlow = SunGlowMask(rayDir, sunDir);
            
                float3 sunColor = _SunDiskColor.rgb * _SunDiskIntensity * sunDisk;
                sunColor = 1.0 - exp(-sunColor);
            
                float3 glowColor = _SunDiskColor.rgb * _SunGlowIntensity * sunGlow;
                glowColor = 1.0 - exp(-glowColor);
            
                // 4. 最后合成
                float3 finalColor = skyColor + sunColor + glowColor * 0.35;
            
                return float4(saturate(finalColor), 1.0);
            }
            ENDHLSL
        }
    }
}
