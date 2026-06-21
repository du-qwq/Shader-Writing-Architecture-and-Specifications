using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace FlowerClouds
{
    [ExecuteAlways]
    [DefaultExecutionOrder(-1000)]
    [DisallowMultipleComponent]
    public class FlowerAtmosphereLightingController : MonoBehaviour
    {
        [Header("Compute")]
        public ComputeShader atmosphereCompute;

        [Header("References")]
        public Camera targetCamera;
        public Light sunLight;

        [Header("Planet")]
        public float planetRadius = 6371000.0f;
        public float atmosphereHeight = 100000.0f;
        public float seaLevelY = 0.0f;

        [Header("Density")]
        public float rayleighScaleHeight = 8500.0f;
        public float mieScaleHeight = 1200.0f;
        public float ozoneCenterHeight = 25000.0f;
        public float ozoneHalfWidth = 15000.0f;

        [Header("Scattering Per Meter")]
        public Vector3 rayleighScattering = new Vector3(
            5.802e-6f,
            13.558e-6f,
            33.1e-6f
        );

        public Vector3 mieScattering = new Vector3(
            3.996e-6f,
            3.996e-6f,
            3.996e-6f
        );

        public Vector3 mieAbsorption = new Vector3(
            4.4e-6f,
            4.4e-6f,
            4.4e-6f
        );

        public Vector3 ozoneAbsorption = new Vector3(
            0.650e-6f,
            1.881e-6f,
            0.085e-6f
        );

        public Color groundAlbedo = new Color(0.3f, 0.3f, 0.3f, 1.0f);

        [Header("Atmosphere Lighting")]
        [Range(0.0f, 2.0f)]
        public float multipleScatteringFactor = 1.0f;

        [Range(-0.99f, 0.99f)]
        public float miePhaseG = 0.76f;

        [Range(1, 64)]
        public int integrationSteps = 32;

        [Range(1, 64)]
        public int skyIrradianceSamples = 64;

        [Range(1, 64)]
        public int distantDirectionSamples = 64;

        [Header("Froxel")]
        public bool updateDynamicLuts = true;

        [Min(0.01f)]
        public float dynamicUpdatePositionThreshold = 0.25f;

        [Min(0.01f)]
        public float dynamicUpdateRotationThreshold = 0.1f;


        [Header("Unified Sky")]
        public Material unifiedSkyMaterial;
        public bool applyUnifiedSkybox = true;

        [Header("Generate")]
        public bool generateOnEnable = true;
        public bool regenerateStaticWhenSunChanges = true;

        private RenderTexture transmittanceLut;
        private RenderTexture multiScatterLut;
        private RenderTexture skyCapture;
        private RenderTexture skyIrradiance;
        private RenderTexture cloudDistantLit;
        private RenderTexture froxelScatter;
        private RenderTexture distantLitGrid;

        private Vector3 lastCameraPosition;
        private Quaternion lastCameraRotation;
        private Vector3 lastSunDirection;
        private bool hasDynamicHistory;
        private bool hasStaticHistory;

        private static readonly int TransmittanceGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereTransmittance");

        private static readonly int MultiScatterGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereMultiScatter");

        private static readonly int SkyCaptureGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereSkyCapture");

        private static readonly int SkyIrradianceGlobalID =
            Shader.PropertyToID("_FlowerSkyIrradiance");

        private static readonly int CloudDistantLitGlobalID =
            Shader.PropertyToID("_FlowerCloudDistantLit");

        private static readonly int FroxelScatterGlobalID =
            Shader.PropertyToID("_FlowerFroxelScatter");

        private static readonly int DistantLitGridGlobalID =
            Shader.PropertyToID("_FlowerDistantLitGrid");

        private static readonly int BottomRadiusGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereBottomRadius");

        private static readonly int TopRadiusGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereTopRadius");

        private static readonly int SunDirectionGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereSunDirection");

        private static readonly int SunLuminanceGlobalID =
            Shader.PropertyToID("_FlowerAtmosphereSunLuminance");

        private static readonly int CommonBottomRadiusGlobalID =
            Shader.PropertyToID("_AtmosphereBottomRadius");

        private static readonly int CommonTopRadiusGlobalID =
            Shader.PropertyToID("_AtmosphereTopRadius");

        private void OnEnable()
        {
            ResolveReferences();

            if (generateOnEnable && atmosphereCompute != null)
            {
                GenerateAll();
            }
        }

        private void Update()
        {
            ResolveReferences();
            BindGlobals();

            if (atmosphereCompute == null ||
                targetCamera == null ||
                targetCamera.orthographic)
            {
                return;
            }

            Vector3 sunDirection = GetSunDirection();

            bool sunChanged =
                !hasStaticHistory ||
                Vector3.Angle(lastSunDirection, sunDirection) > 0.01f;

            if (regenerateStaticWhenSunChanges && sunChanged)
            {
                GenerateStaticLuts();
            }

            if (!updateDynamicLuts)
            {
                return;
            }

            bool cameraMoved =
                !hasDynamicHistory ||
                Vector3.Distance(
                    targetCamera.transform.position,
                    lastCameraPosition
                ) >= dynamicUpdatePositionThreshold;

            bool cameraRotated =
                !hasDynamicHistory ||
                Quaternion.Angle(
                    targetCamera.transform.rotation,
                    lastCameraRotation
                ) >= dynamicUpdateRotationThreshold;

            if (cameraMoved || cameraRotated || sunChanged)
            {
                GenerateDynamicLuts();
            }
        }

        private void OnValidate()
        {
            planetRadius = Mathf.Max(1.0f, planetRadius);
            atmosphereHeight = Mathf.Max(1.0f, atmosphereHeight);
            rayleighScaleHeight = Mathf.Max(1.0f, rayleighScaleHeight);
            mieScaleHeight = Mathf.Max(1.0f, mieScaleHeight);
            ozoneHalfWidth = Mathf.Max(1.0f, ozoneHalfWidth);
            integrationSteps = Mathf.Clamp(integrationSteps, 1, 64);
            skyIrradianceSamples = Mathf.Clamp(skyIrradianceSamples, 1, 64);
            distantDirectionSamples = Mathf.Clamp(distantDirectionSamples, 1, 64);

            ResolveReferences();
            BindGlobals();
        }

        private void OnDisable()
        {
            ReleaseAll();
        }

        [ContextMenu("Generate All Flower Atmosphere LUTs")]
        public void GenerateAll()
        {
            if (!ValidateSetup())
            {
                return;
            }

            AllocateTextures();
            GenerateStaticLuts();
            GenerateDynamicLuts();

            Debug.Log(
                "Flower atmosphere LUTs generated: " +
                "Transmittance 256x64, MultiScatter 32x32, " +
                "SkyCapture 64x64x6, SkyIrradiance 32x32x6, " +
                "CloudDistantLit 64x1, Froxel 32³, DistantGrid 32³.",
                this
            );
        }

        [ContextMenu("Generate Static Flower Atmosphere LUTs")]
        public void GenerateStaticLuts()
        {
            if (!ValidateSetup())
            {
                return;
            }

            AllocateTextures();
            SetCommonParameters();

            Dispatch2D(
                "GenerateTransmittance",
                transmittanceLut.width,
                transmittanceLut.height,
                8,
                8,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_TransmittanceSize",
                        transmittanceLut.width,
                        transmittanceLut.height
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereTransmittanceRW",
                        transmittanceLut
                    );
                }
            );

            Dispatch2D(
                "GenerateMultiScatter",
                multiScatterLut.width,
                multiScatterLut.height,
                1,
                1,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_MultiScatterSize",
                        multiScatterLut.width,
                        multiScatterLut.height
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereTransmittance",
                        transmittanceLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereMultiScatterRW",
                        multiScatterLut
                    );
                }
            );

            SetCameraParameters();

            GenerateSkyCaptureAndIrradiance();

            Dispatch2D(
                "GenerateCloudDistantLit",
                cloudDistantLit.width,
                cloudDistantLit.height,
                8,
                1,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_CloudDistantLitSize",
                        cloudDistantLit.width,
                        cloudDistantLit.height
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereTransmittance",
                        transmittanceLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereMultiScatter",
                        multiScatterLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerCloudDistantLitRW",
                        cloudDistantLit
                    );
                }
            );

            lastSunDirection = GetSunDirection();
            hasStaticHistory = true;

            BindGlobals();
        }

        [ContextMenu("Generate Dynamic Flower Atmosphere LUTs")]
        public void GenerateDynamicLuts()
        {
            if (!ValidateSetup())
            {
                return;
            }

            AllocateTextures();
            SetCommonParameters();
            SetCameraParameters();

            GenerateSkyCaptureAndIrradiance();

            Dispatch3D(
                "GenerateFroxelScatter",
                froxelScatter.width,
                froxelScatter.height,
                froxelScatter.volumeDepth,
                4,
                4,
                1,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_FroxelSize",
                        froxelScatter.width,
                        froxelScatter.height,
                        froxelScatter.volumeDepth
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereTransmittance",
                        transmittanceLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereMultiScatter",
                        multiScatterLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerFroxelScatterRW",
                        froxelScatter
                    );
                }
            );

            Dispatch3D(
                "GenerateDistantLitGrid",
                distantLitGrid.width,
                distantLitGrid.height,
                distantLitGrid.volumeDepth,
                4,
                4,
                1,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_DistantGridSize",
                        distantLitGrid.width,
                        distantLitGrid.height,
                        distantLitGrid.volumeDepth
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereTransmittance",
                        transmittanceLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereMultiScatter",
                        multiScatterLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerDistantLitGridRW",
                        distantLitGrid
                    );
                }
            );

            lastCameraPosition = targetCamera.transform.position;
            lastCameraRotation = targetCamera.transform.rotation;
            lastSunDirection = GetSunDirection();

            hasDynamicHistory = true;

            BindGlobals();
        }

        private void GenerateSkyCaptureAndIrradiance()
        {
            DispatchArray(
                "GenerateSkyCapture",
                skyCapture.width,
                skyCapture.height,
                6,
                8,
                8,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_SkyCaptureSize",
                        skyCapture.width,
                        skyCapture.height
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereTransmittance",
                        transmittanceLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereMultiScatter",
                        multiScatterLut
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereSkyCaptureRW",
                        skyCapture
                    );
                }
            );

            DispatchArray(
                "GenerateSkyIrradiance",
                skyIrradiance.width,
                skyIrradiance.height,
                6,
                8,
                8,
                kernel =>
                {
                    atmosphereCompute.SetInts(
                        "_SkyIrradianceSize",
                        skyIrradiance.width,
                        skyIrradiance.height
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerAtmosphereSkyCapture",
                        skyCapture
                    );

                    atmosphereCompute.SetTexture(
                        kernel,
                        "_FlowerSkyIrradianceRW",
                        skyIrradiance
                    );
                }
            );
        }

        private bool ValidateSetup()
        {
            ResolveReferences();

            if (atmosphereCompute == null)
            {
                Debug.LogError(
                    "FlowerAtmosphereLightingController: atmosphereCompute is missing.",
                    this
                );

                return false;
            }

            if (!SystemInfo.supportsComputeShaders)
            {
                Debug.LogError(
                    "Current platform does not support Compute Shaders.",
                    this
                );

                return false;
            }

            if (targetCamera == null)
            {
                Debug.LogError(
                    "FlowerAtmosphereLightingController: targetCamera is missing.",
                    this
                );

                return false;
            }

            return true;
        }

        private void ResolveReferences()
        {
            if (targetCamera == null)
            {
                targetCamera = Camera.main;
            }

            if (sunLight == null)
            {
                sunLight = RenderSettings.sun;
            }
        }

        private Vector3 GetSunDirection()
        {
            if (sunLight == null)
            {
                return Vector3.up;
            }

            return (-sunLight.transform.forward).normalized;
        }

        private Color GetSunLuminance()
        {
            if (sunLight == null)
            {
                return Color.white;
            }

            return sunLight.color.linear * sunLight.intensity;
        }

        private Vector3 GetCameraPositionAtmosphereKm()
        {
            Vector3 cameraPositionMeter =
                targetCamera.transform.position;

            Vector3 cameraUnitPositionMeter =
                new Vector3(
                    cameraPositionMeter.x,
                    cameraPositionMeter.y - seaLevelY,
                    cameraPositionMeter.z
                );

            return
                cameraUnitPositionMeter /
                1000.0f +
                new Vector3(
                    0.0f,
                    planetRadius * 0.001f + 0.021f,
                    0.0f
                );
        }

        private void SetCommonParameters()
        {
            Vector3 sunDirection = GetSunDirection();
            Color sunLuminance = GetSunLuminance();

            atmosphereCompute.SetFloat(
                "_AtmosphereBottomRadius",
                planetRadius * 0.001f
            );

            atmosphereCompute.SetFloat(
                "_AtmosphereTopRadius",
                (planetRadius + atmosphereHeight) * 0.001f
            );

            atmosphereCompute.SetFloat(
                "_RayleighScaleHeight",
                rayleighScaleHeight * 0.001f
            );

            atmosphereCompute.SetFloat(
                "_MieScaleHeight",
                mieScaleHeight * 0.001f
            );

            atmosphereCompute.SetFloat(
                "_OzoneCenterHeight",
                ozoneCenterHeight * 0.001f
            );

            atmosphereCompute.SetFloat(
                "_OzoneHalfWidth",
                ozoneHalfWidth * 0.001f
            );

            atmosphereCompute.SetVector(
                "_RayleighScattering",
                rayleighScattering * 1000.0f
            );

            atmosphereCompute.SetVector(
                "_MieScattering",
                mieScattering * 1000.0f
            );

            atmosphereCompute.SetVector(
                "_MieAbsorption",
                mieAbsorption * 1000.0f
            );

            atmosphereCompute.SetVector(
                "_OzoneAbsorption",
                ozoneAbsorption * 1000.0f
            );

            atmosphereCompute.SetVector(
                "_GroundAlbedo",
                groundAlbedo.linear
            );

            atmosphereCompute.SetFloat(
                "_MultipleScatteringFactor",
                multipleScatteringFactor
            );

            atmosphereCompute.SetVector(
                "_AtmosphereSunDirection",
                sunDirection
            );

            atmosphereCompute.SetVector(
                "_AtmosphereSunLuminance",
                new Vector4(
                    sunLuminance.r,
                    sunLuminance.g,
                    sunLuminance.b,
                    0.0f
                )
            );

            atmosphereCompute.SetInt(
                "_AtmosphereIntegrationSteps",
                integrationSteps
            );

            atmosphereCompute.SetInt(
                "_AtmosphereDirectionSamples",
                distantDirectionSamples
            );

            atmosphereCompute.SetFloat(
                "_MiePhaseG",
                miePhaseG
            );

            atmosphereCompute.SetInt(
                "_SkyIrradianceSamples",
                skyIrradianceSamples
            );

            atmosphereCompute.SetInt(
                "_DistantDirectionSamples",
                distantDirectionSamples
            );
        }

        private void SetCameraParameters()
        {
            Transform cameraTransform = targetCamera.transform;
            Vector3 localCameraPosition =
                GetCameraPositionAtmosphereKm();

            float tanHalfFov = Mathf.Tan(
                targetCamera.fieldOfView *
                0.5f *
                Mathf.Deg2Rad
            );

            atmosphereCompute.SetVector(
                "_CameraPositionAtmosphere",
                localCameraPosition
            );

            atmosphereCompute.SetVector(
                "_CameraForwardWS",
                cameraTransform.forward.normalized
            );

            atmosphereCompute.SetVector(
                "_CameraRightWS",
                cameraTransform.right.normalized
            );

            atmosphereCompute.SetVector(
                "_CameraUpWS",
                cameraTransform.up.normalized
            );

            atmosphereCompute.SetFloat(
                "_CameraTanHalfFov",
                tanHalfFov
            );

            atmosphereCompute.SetFloat(
                "_CameraAspect",
                targetCamera.aspect
            );
        }

        private void AllocateTextures()
        {
            transmittanceLut = Ensure2D(
                transmittanceLut,
                256,
                64,
                "Flower Atmosphere Transmittance"
            );

            multiScatterLut = Ensure2D(
                multiScatterLut,
                32,
                32,
                "Flower Atmosphere Multi Scatter"
            );

            skyCapture = Ensure2DArray(
                skyCapture,
                64,
                64,
                6,
                "Flower Atmosphere Sky Capture"
            );

            skyIrradiance = Ensure2DArray(
                skyIrradiance,
                32,
                32,
                6,
                "Flower Sky Irradiance"
            );

            cloudDistantLit = Ensure2D(
                cloudDistantLit,
                64,
                1,
                "Flower Cloud Distant Lit"
            );

            froxelScatter = Ensure3D(
                froxelScatter,
                32,
                32,
                32,
                "Flower Atmosphere Froxel Scatter"
            );

            distantLitGrid = Ensure3D(
                distantLitGrid,
                32,
                32,
                32,
                "Flower Atmosphere Distant Lit Grid"
            );
        }

        private static RenderTexture Ensure2D(
            RenderTexture texture,
            int width,
            int height,
            string textureName)
        {
            if (texture != null &&
                texture.width == width &&
                texture.height == height &&
                texture.dimension == TextureDimension.Tex2D)
            {
                return texture;
            }

            ReleaseTexture(ref texture);

            RenderTextureDescriptor descriptor =
                new RenderTextureDescriptor(
                    width,
                    height
                )
                {
                    graphicsFormat =
                        GraphicsFormat.R16G16B16A16_SFloat,

                    depthBufferBits = 0,
                    msaaSamples = 1,
                    enableRandomWrite = true,
                    useMipMap = false,
                    autoGenerateMips = false,
                    dimension = TextureDimension.Tex2D
                };

            texture = new RenderTexture(descriptor)
            {
                name = textureName,
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };

            texture.Create();
            return texture;
        }

        private static RenderTexture Ensure3D(
            RenderTexture texture,
            int width,
            int height,
            int depth,
            string textureName)
        {
            if (texture != null &&
                texture.width == width &&
                texture.height == height &&
                texture.volumeDepth == depth &&
                texture.dimension == TextureDimension.Tex3D)
            {
                return texture;
            }

            ReleaseTexture(ref texture);

            RenderTextureDescriptor descriptor =
                new RenderTextureDescriptor(
                    width,
                    height
                )
                {
                    graphicsFormat =
                        GraphicsFormat.R16G16B16A16_SFloat,

                    depthBufferBits = 0,
                    msaaSamples = 1,
                    enableRandomWrite = true,
                    useMipMap = false,
                    autoGenerateMips = false,
                    dimension = TextureDimension.Tex3D,
                    volumeDepth = depth
                };

            texture = new RenderTexture(descriptor)
            {
                name = textureName,
                filterMode = FilterMode.Trilinear,
                wrapMode = TextureWrapMode.Clamp
            };

            texture.Create();
            return texture;
        }

        private static RenderTexture Ensure2DArray(
            RenderTexture texture,
            int width,
            int height,
            int slices,
            string textureName)
        {
            if (texture != null &&
                texture.width == width &&
                texture.height == height &&
                texture.volumeDepth == slices &&
                texture.dimension == TextureDimension.Tex2DArray)
            {
                return texture;
            }

            ReleaseTexture(ref texture);

            RenderTextureDescriptor descriptor =
                new RenderTextureDescriptor(
                    width,
                    height
                )
                {
                    graphicsFormat =
                        GraphicsFormat.R16G16B16A16_SFloat,

                    depthBufferBits = 0,
                    msaaSamples = 1,
                    enableRandomWrite = true,
                    useMipMap = false,
                    autoGenerateMips = false,
                    dimension = TextureDimension.Tex2DArray,
                    volumeDepth = slices
                };

            texture = new RenderTexture(descriptor)
            {
                name = textureName,
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp
            };

            texture.Create();
            return texture;
        }

        private void Dispatch2D(
            string kernelName,
            int width,
            int height,
            int threadX,
            int threadY,
            System.Action<int> bind)
        {
            int kernel = atmosphereCompute.FindKernel(kernelName);
            bind(kernel);

            atmosphereCompute.Dispatch(
                kernel,
                Mathf.CeilToInt(width / (float)threadX),
                Mathf.CeilToInt(height / (float)threadY),
                1
            );
        }

        private void Dispatch3D(
            string kernelName,
            int width,
            int height,
            int depth,
            int threadX,
            int threadY,
            int threadZ,
            System.Action<int> bind)
        {
            int kernel = atmosphereCompute.FindKernel(kernelName);
            bind(kernel);

            atmosphereCompute.Dispatch(
                kernel,
                Mathf.CeilToInt(width / (float)threadX),
                Mathf.CeilToInt(height / (float)threadY),
                Mathf.CeilToInt(depth / (float)threadZ)
            );
        }

        private void DispatchArray(
            string kernelName,
            int width,
            int height,
            int slices,
            int threadX,
            int threadY,
            System.Action<int> bind)
        {
            Dispatch3D(
                kernelName,
                width,
                height,
                slices,
                threadX,
                threadY,
                1,
                bind
            );
        }

        private void BindGlobals()
        {
            if (applyUnifiedSkybox &&
                unifiedSkyMaterial != null)
            {
                RenderSettings.skybox =
                    unifiedSkyMaterial;
            }

            if (transmittanceLut != null)
            {
                Shader.SetGlobalTexture(
                    TransmittanceGlobalID,
                    transmittanceLut
                );
            }

            if (multiScatterLut != null)
            {
                Shader.SetGlobalTexture(
                    MultiScatterGlobalID,
                    multiScatterLut
                );
            }

            if (skyCapture != null)
            {
                Shader.SetGlobalTexture(
                    SkyCaptureGlobalID,
                    skyCapture
                );
            }

            if (skyIrradiance != null)
            {
                Shader.SetGlobalTexture(
                    SkyIrradianceGlobalID,
                    skyIrradiance
                );
            }

            if (cloudDistantLit != null)
            {
                Shader.SetGlobalTexture(
                    CloudDistantLitGlobalID,
                    cloudDistantLit
                );
            }

            if (froxelScatter != null)
            {
                Shader.SetGlobalTexture(
                    FroxelScatterGlobalID,
                    froxelScatter
                );
            }

            if (distantLitGrid != null)
            {
                Shader.SetGlobalTexture(
                    DistantLitGridGlobalID,
                    distantLitGrid
                );
            }

            Shader.SetGlobalFloat(
                BottomRadiusGlobalID,
                planetRadius * 0.001f
            );

            Shader.SetGlobalFloat(
                TopRadiusGlobalID,
                (planetRadius + atmosphereHeight) * 0.001f
            );

            Shader.SetGlobalFloat(
                CommonBottomRadiusGlobalID,
                planetRadius * 0.001f
            );

            Shader.SetGlobalFloat(
                CommonTopRadiusGlobalID,
                (planetRadius + atmosphereHeight) * 0.001f
            );

            Vector3 sunDirection =
                GetSunDirection();

            Color sunLuminance =
                GetSunLuminance();

            Shader.SetGlobalVector(
                SunDirectionGlobalID,
                new Vector4(
                    sunDirection.x,
                    sunDirection.y,
                    sunDirection.z,
                    0.0f
                )
            );

            Shader.SetGlobalVector(
                SunLuminanceGlobalID,
                new Vector4(
                    sunLuminance.r,
                    sunLuminance.g,
                    sunLuminance.b,
                    0.0f
                )
            );
        }

        [ContextMenu("Release Flower Atmosphere LUTs")]
        public void ReleaseAll()
        {
            ReleaseTexture(ref transmittanceLut);
            ReleaseTexture(ref multiScatterLut);
            ReleaseTexture(ref skyCapture);
            ReleaseTexture(ref skyIrradiance);
            ReleaseTexture(ref cloudDistantLit);
            ReleaseTexture(ref froxelScatter);
            ReleaseTexture(ref distantLitGrid);

            hasStaticHistory = false;
            hasDynamicHistory = false;
        }

        private static void ReleaseTexture(ref RenderTexture texture)
        {
            if (texture == null)
            {
                return;
            }

            texture.Release();

            if (Application.isPlaying)
            {
                Object.Destroy(texture);
            }
            else
            {
                Object.DestroyImmediate(texture);
            }

            texture = null;
        }
    }
}
