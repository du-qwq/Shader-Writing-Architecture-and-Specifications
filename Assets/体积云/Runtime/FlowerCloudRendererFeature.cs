using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FlowerClouds
{
    public class FlowerCloudRendererFeature : ScriptableRendererFeature
    {
        [Serializable]
        public class Settings
        {
            [Header("Shaders")]
            public ComputeShader raymarchCompute;
            public ComputeShader reconstructCompute;
            public Shader compositeShader;

            [Header("Lighting")]
            [Range(0.0f, 2.0f)]
            public float cloudAmbientScale = 0.25f;

            [Header("Flower Lighting")]
            [ColorUsage(false, true)]
            public Color cloudAlbedo = Color.white;

            [Range(0.0f, 50.0f)]
            public float sunLightScale = 10.0f;

            [Min(0.1f)]
            public float cloudLightBasicStepKm = 15.0f;

            [Range(0.01f, 1.0f)]
            public float multiScatterExtinction = 0.5f;

            [Range(0.01f, 1.0f)]
            public float multiScatterScatter = 0.5f;

            [Header("Powder Effect")]
            public bool enablePowder = true;

            [Range(0.0f, 4.0f)]
            public float powderPow = 1.0f;

            [Range(0.05f, 2.0f)]
            public float powderScale = 1.0f;

            [Header("Ground Contribution")]
            public bool enableGroundContribution = true;

            [Header("Planet")]
            public Vector3 planetCenter = new Vector3(0.0f, -6371000.0f, 0.0f);
            public float planetRadius = 6371000.0f;
            public float cloudBottom = 500.0f;
            public float cloudTop = 11000.0f;

            [Header("Cloud Density")]
            [Range(0.0f, 1.0f)]
            public float cloudCoverage = 0.5f;

            [Range(0.0f, 10.0f)]
            public float cloudDensity = 1.0f;

            public Vector2 weatherUVScale = new Vector2(0.03f, 0.03f);

            public Vector3 basicNoiseScale = new Vector3(0.15f, 0.15f, 0.15f);
            public Vector3 detailNoiseScale = new Vector3(0.8f, 0.8f, 0.8f);
            public Vector3 cloudDirection = new Vector3(1.0f, 0.0f, 0.0f);

            [Range(0.0f, 2.0f)]
            public float cloudSpeed = 0.05f;

            [Header("Ray Marching")]
            [Range(1, 4)]
            public int downsample = 4;

            [Header("Temporal Reconstruction")]
            public bool enableTemporalReconstruction = true;

            [Range(0.0f, 0.98f)]
            public float temporalBlend = 0.90f;

            [Range(8, 128)]
            public int viewStepCount = 64;

            [Range(1, 16)]
            public int lightStepCount = 6;

            [Min(1.0f)]
            public float cloudMaxTracingDistanceKm = 50.0f;

            [Min(1.0f)]
            public float cloudTracingStartMaxDistanceKm = 350.0f;

            [Header("Phase")]
            [Range(0.0f, 0.95f)]
            public float phaseForward = 0.65f;

            [Range(-0.95f, 0.0f)]
            public float phaseBackward = -0.2f;

            [Range(0.0f, 1.0f)]
            public float phaseBlend = 0.2f;
        }

        public Settings settings = new Settings();

        private FlowerCloudRenderPass renderPass;
        private Material compositeMaterial;

        public override void Create()
        {
            CoreUtils.Destroy(compositeMaterial);
            compositeMaterial = null;

            if (settings.compositeShader != null)
            {
                compositeMaterial = CoreUtils.CreateEngineMaterial(
                    settings.compositeShader
                );
            }

            renderPass = new FlowerCloudRenderPass(
                settings,
                compositeMaterial
            );

            renderPass.renderPassEvent =
                RenderPassEvent.BeforeRenderingTransparents;
        }

        public override void SetupRenderPasses(
            ScriptableRenderer renderer,
            in RenderingData renderingData
        )
        {
            if (renderPass == null)
            {
                return;
            }

            if (renderingData.cameraData.cameraType != CameraType.Game ||
                renderingData.cameraData.renderType != CameraRenderType.Base)
            {
                return;
            }

            renderPass.ConfigureInput(ScriptableRenderPassInput.Depth);
            renderPass.SetCameraColorTarget(renderer.cameraColorTargetHandle);
        }

        public override void AddRenderPasses(
            ScriptableRenderer renderer,
            ref RenderingData renderingData
        )
        {
            if (renderPass == null ||
                settings.raymarchCompute == null ||
                compositeMaterial == null)
            {
                return;
            }

            if (renderingData.cameraData.cameraType != CameraType.Game ||
                renderingData.cameraData.renderType != CameraRenderType.Base)
            {
                return;
            }

            renderer.EnqueuePass(renderPass);
        }

        protected override void Dispose(bool disposing)
        {
            renderPass?.Dispose();
            renderPass = null;

            CoreUtils.Destroy(compositeMaterial);
            compositeMaterial = null;
        }

        private class FlowerCloudRenderPass : ScriptableRenderPass
        {
            private readonly Settings settings;
            private readonly Material compositeMaterial;
            private readonly ProfilingSampler cloudProfilingSampler;

            private RTHandle cameraColorTarget;
            private RTHandle cloudColorTexture;
            private RTHandle cloudDepthTexture;
            private RTHandle cloudReconstructionTexture;
            private RTHandle cloudHistoryTexture;
            private RTHandle cameraColorCopy;

            private uint frameIndex;
            private bool hasHistory;
            private Matrix4x4 previousViewProjectionMatrix = Matrix4x4.identity;

            private static readonly int OutputSizeID =
                Shader.PropertyToID("_OutputSize");

            private static readonly int FullResolutionID =
                Shader.PropertyToID("_FullResolution");

            private static readonly int CameraPositionID =
                Shader.PropertyToID("_CameraPositionWS");

            private static readonly int CameraForwardID =
                Shader.PropertyToID("_CameraForwardWS");

            private static readonly int CameraRightID =
                Shader.PropertyToID("_CameraRightWS");

            private static readonly int CameraUpID =
                Shader.PropertyToID("_CameraUpWS");

            private static readonly int CameraTanHalfFovID =
                Shader.PropertyToID("_CameraTanHalfFov");

            private static readonly int CameraAspectID =
                Shader.PropertyToID("_CameraAspect");

            private static readonly int PreviousViewProjectionMatrixID =
                Shader.PropertyToID("_PreviousViewProjectionMatrix");

            private static readonly int TemporalBlendID =
                Shader.PropertyToID("_TemporalBlend");

            private static readonly int FrameIndexID =
                Shader.PropertyToID("_FrameIndex");

            private static readonly int PlanetCenterID =
                Shader.PropertyToID("_PlanetCenter");

            private static readonly int PlanetRadiusID =
                Shader.PropertyToID("_PlanetRadius");

            private static readonly int CloudBottomID =
                Shader.PropertyToID("_CloudBottom");

            private static readonly int CloudTopID =
                Shader.PropertyToID("_CloudTop");

            private static readonly int CloudCoverageID =
                Shader.PropertyToID("_CloudCoverage");

            private static readonly int CloudDensityID =
                Shader.PropertyToID("_CloudDensity");

            private static readonly int CloudWeatherUVScaleID =
                Shader.PropertyToID("_CloudWeatherUVScale");

            private static readonly int BasicNoiseScaleID =
                Shader.PropertyToID("_CloudBasicNoiseScale");

            private static readonly int DetailNoiseScaleID =
                Shader.PropertyToID("_CloudDetailNoiseScale");

            private static readonly int CloudDirectionID =
                Shader.PropertyToID("_CloudDirection");

            private static readonly int CloudSpeedID =
                Shader.PropertyToID("_CloudSpeed");

            private static readonly int ViewStepCountID =
                Shader.PropertyToID("_ViewStepCount");

            private static readonly int LightStepCountID =
                Shader.PropertyToID("_LightStepCount");

            private static readonly int CloudMaxTracingDistanceKmID =
                Shader.PropertyToID("_CloudMaxTracingDistanceKm");

            private static readonly int CloudTracingStartMaxDistanceKmID =
                Shader.PropertyToID("_CloudTracingStartMaxDistanceKm");

            private static readonly int CloudLightBasicStepKmID =
                Shader.PropertyToID("_CloudLightBasicStepKm");

            private static readonly int MultiScatterExtinctionID =
                Shader.PropertyToID("_MultiScatterExtinction");

            private static readonly int MultiScatterScatterID =
                Shader.PropertyToID("_MultiScatterScatter");

            private static readonly int CloudAlbedoID =
                Shader.PropertyToID("_CloudAlbedo");

            private static readonly int SunLightScaleID =
                Shader.PropertyToID("_SunLightScale");

            private static readonly int EnablePowderID =
                Shader.PropertyToID("_EnablePowder");

            private static readonly int PowderPowID =
                Shader.PropertyToID("_PowderPow");

            private static readonly int PowderScaleID =
                Shader.PropertyToID("_PowderScale");

            private static readonly int EnableGroundContributionID =
                Shader.PropertyToID("_EnableGroundContribution");

            private static readonly int SunDirectionID =
                Shader.PropertyToID("_SunDirection");

            private static readonly int SunColorID =
                Shader.PropertyToID("_SunColor");

            private static readonly int CloudAmbientScaleID =
                Shader.PropertyToID("_CloudAmbientScale");

            private static readonly int PhaseForwardID =
                Shader.PropertyToID("_PhaseForward");

            private static readonly int PhaseBackwardID =
                Shader.PropertyToID("_PhaseBackward");

            private static readonly int PhaseBlendID =
                Shader.PropertyToID("_PhaseBlend");

            private static readonly int CloudColorOutputID =
                Shader.PropertyToID("_CloudColorTexture");

            private static readonly int CloudDepthOutputID =
                Shader.PropertyToID("_CloudDepthTexture");

            private static readonly int CloudLowResColorID =
                Shader.PropertyToID("_CloudLowResColorTexture");

            private static readonly int CloudLowResDepthID =
                Shader.PropertyToID("_CloudLowResDepthTexture");

            private static readonly int CloudHistoryID =
                Shader.PropertyToID("_CloudHistoryTexture");

            private static readonly int CloudReconstructionOutputID =
                Shader.PropertyToID("_CloudReconstructionTexture");

            private static readonly int GlobalBasicNoiseID =
                Shader.PropertyToID("_FlowerCloudBasicNoise");

            private static readonly int GlobalDetailNoiseID =
                Shader.PropertyToID("_FlowerCloudDetailNoise");

            private static readonly int GlobalWeatherID =
                Shader.PropertyToID("_FlowerCloudWeather");

            private static readonly int GlobalCurlID =
                Shader.PropertyToID("_FlowerCloudCurl");

            private static readonly int GlobalCoverageNoiseID =
                Shader.PropertyToID("_FlowerCloudCoverageNoise");

            private static readonly int AtmosphereTransmittanceID =
                Shader.PropertyToID("_FlowerAtmosphereTransmittance");

            private static readonly int AtmosphereMultiScatterID =
                Shader.PropertyToID("_FlowerAtmosphereMultiScatter");

            private static readonly int CloudDistantLitID =
                Shader.PropertyToID("_FlowerCloudDistantLit");

            private static readonly int FroxelScatterID =
                Shader.PropertyToID("_FlowerFroxelScatter");

            private static readonly int DistantLitGridID =
                Shader.PropertyToID("_FlowerDistantLitGrid");

            private static readonly int AtmosphereBottomRadiusID =
                Shader.PropertyToID("_AtmosphereBottomRadius");

            private static readonly int AtmosphereTopRadiusID =
                Shader.PropertyToID("_AtmosphereTopRadius");

            private static readonly int CompositeCloudColorID =
                Shader.PropertyToID("_CloudColorTexture");

            public FlowerCloudRenderPass(
                Settings settings,
                Material compositeMaterial
            )
            {
                this.settings = settings;
                this.compositeMaterial = compositeMaterial;

                cloudProfilingSampler =
                    new ProfilingSampler("Flower Volumetric Clouds");
            }

            public void SetCameraColorTarget(RTHandle target)
            {
                cameraColorTarget = target;
            }

            public override void OnCameraSetup(
                CommandBuffer commandBuffer,
                ref RenderingData renderingData
            )
            {
                RenderTextureDescriptor cameraDescriptor =
                    renderingData.cameraData.cameraTargetDescriptor;

                int downsample = Mathf.Max(1, settings.downsample);

                RenderTextureDescriptor cloudColorDescriptor =
                    cameraDescriptor;

                cloudColorDescriptor.width = Mathf.Max(
                    1,
                    cameraDescriptor.width / downsample
                );

                cloudColorDescriptor.height = Mathf.Max(
                    1,
                    cameraDescriptor.height / downsample
                );

                cloudColorDescriptor.depthBufferBits = 0;
                cloudColorDescriptor.msaaSamples = 1;
                cloudColorDescriptor.enableRandomWrite = true;
                cloudColorDescriptor.graphicsFormat =
                    GraphicsFormat.R16G16B16A16_SFloat;

                RenderingUtils.ReAllocateIfNeeded(
                    ref cloudColorTexture,
                    cloudColorDescriptor,
                    FilterMode.Bilinear,
                    TextureWrapMode.Clamp,
                    name: "_FlowerCloudColorQuarter"
                );

                RenderTextureDescriptor cloudDepthDescriptor =
                    cloudColorDescriptor;

                cloudDepthDescriptor.graphicsFormat =
                    GraphicsFormat.R32_SFloat;

                RenderingUtils.ReAllocateIfNeeded(
                    ref cloudDepthTexture,
                    cloudDepthDescriptor,
                    FilterMode.Bilinear,
                    TextureWrapMode.Clamp,
                    name: "_FlowerCloudDepthQuarter"
                );

                RenderTextureDescriptor reconstructionDescriptor =
                    cameraDescriptor;

                reconstructionDescriptor.depthBufferBits = 0;
                reconstructionDescriptor.msaaSamples = 1;
                reconstructionDescriptor.enableRandomWrite = true;
                reconstructionDescriptor.graphicsFormat =
                    GraphicsFormat.R16G16B16A16_SFloat;

                RenderingUtils.ReAllocateIfNeeded(
                    ref cloudReconstructionTexture,
                    reconstructionDescriptor,
                    FilterMode.Bilinear,
                    TextureWrapMode.Clamp,
                    name: "_FlowerCloudReconstruction"
                );

                RenderTextureDescriptor historyDescriptor =
                    reconstructionDescriptor;

                historyDescriptor.enableRandomWrite = false;

                RenderingUtils.ReAllocateIfNeeded(
                    ref cloudHistoryTexture,
                    historyDescriptor,
                    FilterMode.Bilinear,
                    TextureWrapMode.Clamp,
                    name: "_FlowerCloudReconstructionHistory"
                );

                RenderTextureDescriptor colorCopyDescriptor =
                    cameraDescriptor;

                colorCopyDescriptor.depthBufferBits = 0;
                colorCopyDescriptor.msaaSamples = 1;
                colorCopyDescriptor.enableRandomWrite = false;

                RenderingUtils.ReAllocateIfNeeded(
                    ref cameraColorCopy,
                    colorCopyDescriptor,
                    FilterMode.Bilinear,
                    TextureWrapMode.Clamp,
                    name: "_FlowerCloudCameraColorCopy"
                );
            }

            public override void Execute(
                ScriptableRenderContext context,
                ref RenderingData renderingData
            )
            {
                if (cameraColorTarget == null ||
                    cloudColorTexture == null ||
                    cloudDepthTexture == null)
                {
                    return;
                }

                Texture basicNoise =
                    Shader.GetGlobalTexture(GlobalBasicNoiseID);

                Texture detailNoise =
                    Shader.GetGlobalTexture(GlobalDetailNoiseID);

                Texture weather =
                    Shader.GetGlobalTexture(GlobalWeatherID);

                Texture curl =
                    Shader.GetGlobalTexture(GlobalCurlID);

                Texture coverageNoise =
                    Shader.GetGlobalTexture(GlobalCoverageNoiseID);

                Texture atmosphereTransmittance =
                    Shader.GetGlobalTexture(AtmosphereTransmittanceID);

                Texture atmosphereMultiScatter =
                    Shader.GetGlobalTexture(AtmosphereMultiScatterID);

                Texture cloudDistantLit =
                    Shader.GetGlobalTexture(CloudDistantLitID);

                Texture froxelScatter =
                    Shader.GetGlobalTexture(FroxelScatterID);

                Texture distantLitGrid =
                    Shader.GetGlobalTexture(DistantLitGridID);

                if (basicNoise == null ||
                    detailNoise == null ||
                    weather == null ||
                    curl == null ||
                    coverageNoise == null ||
                    atmosphereTransmittance == null ||
                    atmosphereMultiScatter == null ||
                    cloudDistantLit == null ||
                    froxelScatter == null ||
                    distantLitGrid == null)
                {
                    return;
                }

                CommandBuffer commandBuffer =
                    CommandBufferPool.Get();

                Matrix4x4 currentViewProjectionMatrix = Matrix4x4.identity;

                using (new ProfilingScope(commandBuffer, cloudProfilingSampler))
                {
                    Camera camera = renderingData.cameraData.camera;

                    Vector3 cameraForward = camera.transform.forward.normalized;
                    Vector3 cameraRight = camera.transform.right.normalized;
                    Vector3 cameraUp = camera.transform.up.normalized;
                    float cameraTanHalfFov = Mathf.Tan(camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
                    float cameraAspect = camera.aspect;
                    currentViewProjectionMatrix = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false) * camera.worldToCameraMatrix;

                    if (!hasHistory)
                    {
                        previousViewProjectionMatrix = currentViewProjectionMatrix;
                    }

                    Light sunLight = RenderSettings.sun;

                    Vector3 sunDirection = Vector3.up;
                    Color sunColor = Color.white;

                    if (sunLight != null)
                    {
                        sunDirection =
                            -sunLight.transform.forward;

                        sunColor =
                            sunLight.color.linear *
                            sunLight.intensity;
                    }

                    int kernel =
                        settings.raymarchCompute.FindKernel("CSMain");

                    int cloudWidth =
                        cloudColorTexture.rt.width;

                    int cloudHeight =
                        cloudColorTexture.rt.height;

                    commandBuffer.SetComputeIntParams(
                        settings.raymarchCompute,
                        OutputSizeID,
                        cloudWidth,
                        cloudHeight
                    );

                    commandBuffer.SetComputeIntParams(
                        settings.raymarchCompute,
                        FullResolutionID,
                        camera.pixelWidth,
                        camera.pixelHeight
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CameraPositionID,
                        camera.transform.position
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CameraForwardID,
                        new Vector4(cameraForward.x, cameraForward.y, cameraForward.z, 0.0f)
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CameraRightID,
                        new Vector4(cameraRight.x, cameraRight.y, cameraRight.z, 0.0f)
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CameraUpID,
                        new Vector4(cameraUp.x, cameraUp.y, cameraUp.z, 0.0f)
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CameraTanHalfFovID,
                        cameraTanHalfFov
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CameraAspectID,
                        cameraAspect
                    );

                    commandBuffer.SetComputeIntParam(
                        settings.raymarchCompute,
                        FrameIndexID,
                        (int)frameIndex
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        PlanetCenterID,
                        settings.planetCenter
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        PlanetRadiusID,
                        settings.planetRadius
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudBottomID,
                        settings.cloudBottom
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudTopID,
                        settings.cloudTop
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudCoverageID,
                        settings.cloudCoverage
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudDensityID,
                        settings.cloudDensity
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CloudWeatherUVScaleID,
                        settings.weatherUVScale
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        BasicNoiseScaleID,
                        settings.basicNoiseScale
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        DetailNoiseScaleID,
                        settings.detailNoiseScale
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CloudDirectionID,
                        settings.cloudDirection
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudSpeedID,
                        settings.cloudSpeed
                    );

                    commandBuffer.SetComputeIntParam(
                        settings.raymarchCompute,
                        ViewStepCountID,
                        settings.viewStepCount
                    );

                    commandBuffer.SetComputeIntParam(
                        settings.raymarchCompute,
                        LightStepCountID,
                        settings.lightStepCount
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudMaxTracingDistanceKmID,
                        settings.cloudMaxTracingDistanceKm
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudTracingStartMaxDistanceKmID,
                        settings.cloudTracingStartMaxDistanceKm
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudLightBasicStepKmID,
                        settings.cloudLightBasicStepKm
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        MultiScatterExtinctionID,
                        settings.multiScatterExtinction
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        MultiScatterScatterID,
                        settings.multiScatterScatter
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        CloudAlbedoID,
                        settings.cloudAlbedo.linear
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        SunLightScaleID,
                        settings.sunLightScale
                    );

                    commandBuffer.SetComputeIntParam(
                        settings.raymarchCompute,
                        EnablePowderID,
                        settings.enablePowder ? 1 : 0
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        PowderPowID,
                        settings.powderPow
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        PowderScaleID,
                        settings.powderScale
                    );

                    commandBuffer.SetComputeIntParam(
                        settings.raymarchCompute,
                        EnableGroundContributionID,
                        settings.enableGroundContribution ? 1 : 0
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        SunDirectionID,
                        sunDirection.normalized
                    );

                    commandBuffer.SetComputeVectorParam(
                        settings.raymarchCompute,
                        SunColorID,
                        sunColor
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        CloudAmbientScaleID,
                        settings.cloudAmbientScale
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        PhaseForwardID,
                        settings.phaseForward
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        PhaseBackwardID,
                        settings.phaseBackward
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        PhaseBlendID,
                        settings.phaseBlend
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        GlobalBasicNoiseID,
                        basicNoise
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        GlobalDetailNoiseID,
                        detailNoise
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        GlobalWeatherID,
                        weather
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        GlobalCurlID,
                        curl
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        GlobalCoverageNoiseID,
                        coverageNoise
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        AtmosphereTransmittanceID,
                        atmosphereTransmittance
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        AtmosphereMultiScatterID,
                        atmosphereMultiScatter
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        CloudDistantLitID,
                        cloudDistantLit
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        FroxelScatterID,
                        froxelScatter
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        DistantLitGridID,
                        distantLitGrid
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        AtmosphereBottomRadiusID,
                        Shader.GetGlobalFloat(AtmosphereBottomRadiusID)
                    );

                    commandBuffer.SetComputeFloatParam(
                        settings.raymarchCompute,
                        AtmosphereTopRadiusID,
                        Shader.GetGlobalFloat(AtmosphereTopRadiusID)
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        CloudColorOutputID,
                        cloudColorTexture
                    );

                    commandBuffer.SetComputeTextureParam(
                        settings.raymarchCompute,
                        kernel,
                        CloudDepthOutputID,
                        cloudDepthTexture
                    );

                    int groupCountX =
                        Mathf.CeilToInt(cloudWidth / 8.0f);

                    int groupCountY =
                        Mathf.CeilToInt(cloudHeight / 8.0f);

                    commandBuffer.DispatchCompute(
                        settings.raymarchCompute,
                        kernel,
                        groupCountX,
                        groupCountY,
                        1
                    );

                    RTHandle cloudTextureForComposite =
                        cloudColorTexture;

                    if (settings.enableTemporalReconstruction &&
                        settings.reconstructCompute != null &&
                        cloudReconstructionTexture != null &&
                        cloudHistoryTexture != null)
                    {
                        int reconstructKernel =
                            settings.reconstructCompute.FindKernel("CSMain");

                        commandBuffer.SetComputeIntParams(
                            settings.reconstructCompute,
                            OutputSizeID,
                            cloudWidth,
                            cloudHeight
                        );

                        commandBuffer.SetComputeIntParams(
                            settings.reconstructCompute,
                            FullResolutionID,
                            camera.pixelWidth,
                            camera.pixelHeight
                        );

                        commandBuffer.SetComputeVectorParam(
                            settings.reconstructCompute,
                            CameraPositionID,
                            camera.transform.position
                        );

                        commandBuffer.SetComputeVectorParam(
                            settings.reconstructCompute,
                            CameraForwardID,
                            new Vector4(cameraForward.x, cameraForward.y, cameraForward.z, 0.0f)
                        );

                        commandBuffer.SetComputeVectorParam(
                            settings.reconstructCompute,
                            CameraRightID,
                            new Vector4(cameraRight.x, cameraRight.y, cameraRight.z, 0.0f)
                        );

                        commandBuffer.SetComputeVectorParam(
                            settings.reconstructCompute,
                            CameraUpID,
                            new Vector4(cameraUp.x, cameraUp.y, cameraUp.z, 0.0f)
                        );

                        commandBuffer.SetComputeFloatParam(
                            settings.reconstructCompute,
                            CameraTanHalfFovID,
                            cameraTanHalfFov
                        );

                        commandBuffer.SetComputeFloatParam(
                            settings.reconstructCompute,
                            CameraAspectID,
                            cameraAspect
                        );

                        commandBuffer.SetComputeMatrixParam(
                            settings.reconstructCompute,
                            PreviousViewProjectionMatrixID,
                            previousViewProjectionMatrix
                        );

                        commandBuffer.SetComputeFloatParam(
                            settings.reconstructCompute,
                            TemporalBlendID,
                            hasHistory ? settings.temporalBlend : 0.0f
                        );

                        commandBuffer.SetComputeIntParam(
                            settings.reconstructCompute,
                            FrameIndexID,
                            (int)frameIndex
                        );

                        commandBuffer.SetComputeTextureParam(
                            settings.reconstructCompute,
                            reconstructKernel,
                            CloudLowResColorID,
                            cloudColorTexture
                        );

                        commandBuffer.SetComputeTextureParam(
                            settings.reconstructCompute,
                            reconstructKernel,
                            CloudLowResDepthID,
                            cloudDepthTexture
                        );

                        commandBuffer.SetComputeTextureParam(
                            settings.reconstructCompute,
                            reconstructKernel,
                            CloudHistoryID,
                            cloudHistoryTexture
                        );

                        commandBuffer.SetComputeTextureParam(
                            settings.reconstructCompute,
                            reconstructKernel,
                            CloudReconstructionOutputID,
                            cloudReconstructionTexture
                        );

                        int reconstructGroupCountX =
                            Mathf.CeilToInt(camera.pixelWidth / 8.0f);

                        int reconstructGroupCountY =
                            Mathf.CeilToInt(camera.pixelHeight / 8.0f);

                        commandBuffer.DispatchCompute(
                            settings.reconstructCompute,
                            reconstructKernel,
                            reconstructGroupCountX,
                            reconstructGroupCountY,
                            1
                        );

                        commandBuffer.CopyTexture(
                            cloudReconstructionTexture,
                            cloudHistoryTexture
                        );

                        cloudTextureForComposite =
                            cloudReconstructionTexture;
                    }

                    commandBuffer.SetGlobalTexture(
                        CompositeCloudColorID,
                        cloudTextureForComposite
                    );

                    Blitter.BlitCameraTexture(
                        commandBuffer,
                        cameraColorTarget,
                        cameraColorCopy
                    );

                    Blitter.BlitCameraTexture(
                        commandBuffer,
                        cameraColorCopy,
                        cameraColorTarget,
                        compositeMaterial,
                        0
                    );
                }

                context.ExecuteCommandBuffer(commandBuffer);
                commandBuffer.Clear();
                CommandBufferPool.Release(commandBuffer);

                previousViewProjectionMatrix = currentViewProjectionMatrix;
                hasHistory = true;
                frameIndex++;
            }

            public void Dispose()
            {
                cloudColorTexture?.Release();
                cloudColorTexture = null;

                cloudDepthTexture?.Release();
                cloudDepthTexture = null;

                cloudReconstructionTexture?.Release();
                cloudReconstructionTexture = null;

                cloudHistoryTexture?.Release();
                cloudHistoryTexture = null;

                cameraColorCopy?.Release();
                cameraColorCopy = null;
            }
        }
    }
}