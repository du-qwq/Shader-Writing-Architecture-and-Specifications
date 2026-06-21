using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

namespace FlowerClouds
{
    [ExecuteAlways]
    [DisallowMultipleComponent]
    public sealed class FlowerCloudNoiseGenerator : MonoBehaviour
    {
        public enum PreviewNoise
        {
            Basic,
            Detail
        }

        [Header("Compute Shaders")]
        [SerializeField]
        private ComputeShader basicNoiseCompute;

        [SerializeField]
        private ComputeShader detailNoiseCompute;

        [Header("Unity Texture Sizes")]
        [Min(8)]
        [SerializeField]
        private int basicResolution = 128;

        [Min(8)]
        [SerializeField]
        private int detailResolution = 32;

        [Tooltip(
            "Generates the 3D textures when this component becomes enabled."
        )]
        [SerializeField]
        private bool generateOnEnable = true;

        [Header("Optional Slice Preview")]
        [SerializeField]
        private Renderer previewRenderer;

        [SerializeField]
        private PreviewNoise previewNoise = PreviewNoise.Basic;

        [Range(0.0f, 1.0f)]
        [SerializeField]
        private float previewSlice = 0.5f;

        [Range(0.1f, 8.0f)]
        [SerializeField]
        private float previewContrast = 1.0f;

        [SerializeField]
        private bool invertPreview;

        private RenderTexture basicNoise;
        private RenderTexture detailNoise;

        private Material previewMaterial;
        private Material previousPreviewMaterial;

        private static readonly int TextureSizeID =
            Shader.PropertyToID("_TextureSize");

        private static readonly int BasicNoiseID =
            Shader.PropertyToID("_BasicNoise");

        private static readonly int DetailNoiseID =
            Shader.PropertyToID("_DetailNoise");

        private static readonly int PreviewNoiseTextureID =
            Shader.PropertyToID("_NoiseTex");

        private static readonly int PreviewSliceID =
            Shader.PropertyToID("_Slice");

        private static readonly int PreviewContrastID =
            Shader.PropertyToID("_Contrast");

        private static readonly int PreviewInvertID =
            Shader.PropertyToID("_Invert");

        public RenderTexture BasicNoise => basicNoise;
        public RenderTexture DetailNoise => detailNoise;

        private void OnEnable()
        {
            if (generateOnEnable)
            {
                GenerateNoise();
            }

            UpdatePreview();
        }

        private void Update()
        {
            UpdatePreview();
        }

        private void OnValidate()
        {
            basicResolution = Mathf.Max(8, basicResolution);
            detailResolution = Mathf.Max(8, detailResolution);

            UpdatePreview();
        }

        private void OnDisable()
        {
            ReleaseNoiseTextures();
            DestroyPreviewMaterial();
        }

        [ContextMenu("Generate Flower Cloud Noise")]
        public void GenerateNoise()
        {
            if (!SystemInfo.supportsComputeShaders)
            {
                Debug.LogError(
                    "This platform does not support compute shaders.",
                    this
                );
                return;
            }

            if (basicNoiseCompute == null)
            {
                Debug.LogError(
                    "Assign FlowerCloudBasicNoise.compute.",
                    this
                );
                return;
            }

            if (detailNoiseCompute == null)
            {
                Debug.LogError(
                    "Assign FlowerCloudDetailNoise.compute.",
                    this
                );
                return;
            }

            ReleaseNoiseTextures();

            GraphicsFormat noiseFormat = GetNoiseGraphicsFormat();

            basicNoise = Create3DRenderTexture(
                "Flower Cloud Basic Noise",
                basicResolution,
                noiseFormat
            );

            detailNoise = Create3DRenderTexture(
                "Flower Cloud Detail Noise",
                detailResolution,
                noiseFormat
            );

            DispatchNoise(
                basicNoiseCompute,
                basicNoise,
                BasicNoiseID,
                basicResolution
            );

            DispatchNoise(
                detailNoiseCompute,
                detailNoise,
                DetailNoiseID,
                detailResolution
            );

            // Later cloud passes can read these globals directly.
            Shader.SetGlobalTexture(
                "_FlowerCloudBasicNoise",
                basicNoise
            );

            Shader.SetGlobalTexture(
                "_FlowerCloudDetailNoise",
                detailNoise
            );

            UpdatePreview();

            Debug.Log(
                $"Generated Flower cloud noise: "
                + $"basic {basicResolution}³, "
                + $"detail {detailResolution}³.",
                this
            );
        }

        private static GraphicsFormat GetNoiseGraphicsFormat()
        {
            if (SystemInfo.IsFormatSupported(
                GraphicsFormat.R16_SFloat,
                FormatUsage.LoadStore
            ))
            {
                return GraphicsFormat.R16_SFloat;
            }

            return GraphicsFormat.R32_SFloat;
        }

        private static RenderTexture Create3DRenderTexture(
            string textureName,
            int resolution,
            GraphicsFormat graphicsFormat)
        {
            RenderTextureDescriptor descriptor =
                new RenderTextureDescriptor(
                    resolution,
                    resolution
                )
                {
                    graphicsFormat = graphicsFormat,
                    depthBufferBits = 0,
                    dimension = TextureDimension.Tex3D,
                    volumeDepth = resolution,
                    enableRandomWrite = true,
                    msaaSamples = 1,
                    useMipMap = false,
                    autoGenerateMips = false
                };

            RenderTexture texture =
                new RenderTexture(descriptor)
                {
                    name = textureName,
                    wrapMode = TextureWrapMode.Repeat,
                    filterMode = FilterMode.Trilinear,
                    anisoLevel = 0
                };

            if (!texture.Create())
            {
                DestroyUnityObject(texture);

                throw new System.InvalidOperationException(
                    $"Failed to create 3D RenderTexture "
                    + $"{textureName} ({resolution}³)."
                );
            }

            return texture;
        }

        private static void DispatchNoise(
            ComputeShader computeShader,
            RenderTexture target,
            int targetPropertyID,
            int resolution)
        {
            int kernel = computeShader.FindKernel("CSMain");

            computeShader.SetInts(
                TextureSizeID,
                resolution,
                resolution,
                resolution
            );

            computeShader.SetTexture(
                kernel,
                targetPropertyID,
                target
            );

            int groupCountXY =
                Mathf.CeilToInt(resolution / 8.0f);

            // The port keeps flower's 8×8×1 local group size.
            computeShader.Dispatch(
                kernel,
                groupCountXY,
                groupCountXY,
                resolution
            );
        }

        private void UpdatePreview()
        {
            if (previewRenderer == null)
            {
                return;
            }

            EnsurePreviewMaterial();

            if (previewMaterial == null)
            {
                return;
            }

            Texture selectedTexture =
                previewNoise == PreviewNoise.Basic
                ? basicNoise
                : detailNoise;

            previewMaterial.SetTexture(
                PreviewNoiseTextureID,
                selectedTexture
            );

            previewMaterial.SetFloat(
                PreviewSliceID,
                previewSlice
            );

            previewMaterial.SetFloat(
                PreviewContrastID,
                previewContrast
            );

            previewMaterial.SetFloat(
                PreviewInvertID,
                invertPreview ? 1.0f : 0.0f
            );
        }

        private void EnsurePreviewMaterial()
        {
            if (previewMaterial != null)
            {
                return;
            }

            Shader previewShader = Shader.Find(
                "FlowerClouds/Debug/Noise Slice"
            );

            if (previewShader == null)
            {
                return;
            }

            previousPreviewMaterial =
                previewRenderer.sharedMaterial;

            previewMaterial = new Material(previewShader)
            {
                name = "Flower Cloud Noise Preview (Runtime)",
                hideFlags = HideFlags.HideAndDontSave
            };

            previewRenderer.sharedMaterial =
                previewMaterial;
        }

        [ContextMenu("Release Flower Cloud Noise")]
        public void ReleaseNoiseTextures()
        {
            ReleaseRenderTexture(ref basicNoise);
            ReleaseRenderTexture(ref detailNoise);
        }

        private void DestroyPreviewMaterial()
        {
            if (previewRenderer != null
                && previewRenderer.sharedMaterial == previewMaterial)
            {
                previewRenderer.sharedMaterial =
                    previousPreviewMaterial;
            }

            previousPreviewMaterial = null;

            if (previewMaterial != null)
            {
                DestroyUnityObject(previewMaterial);
                previewMaterial = null;
            }
        }

        private static void ReleaseRenderTexture(
            ref RenderTexture texture)
        {
            if (texture == null)
            {
                return;
            }

            texture.Release();
            DestroyUnityObject(texture);
            texture = null;
        }

        private static void DestroyUnityObject(
            Object unityObject)
        {
            if (unityObject == null)
            {
                return;
            }

            if (Application.isPlaying)
            {
                Object.Destroy(unityObject);
            }
            else
            {
                Object.DestroyImmediate(unityObject);
            }
        }
    }
}
