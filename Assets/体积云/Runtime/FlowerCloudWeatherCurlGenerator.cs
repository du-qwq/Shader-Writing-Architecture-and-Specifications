using UnityEngine;
using UnityEngine.Experimental.Rendering;

namespace FlowerClouds
{
    [ExecuteAlways]
    [DisallowMultipleComponent]
    public class FlowerCloudWeatherCurlGenerator : MonoBehaviour
    {
        [Header("Compute Shader")]
        public ComputeShader weatherCurlCompute;

        [Header("Resolution")]
        [Min(32)]
        public int weatherResolution = 512;

        [Min(32)]
        public int curlResolution = 256;

        [Min(32)]
        public int coverageResolution = 256;

        [Header("Generation")]
        public bool generateOnEnable = true;
        public float seed = 7.31f;

        private RenderTexture weatherTexture;
        private RenderTexture curlTexture;
        private RenderTexture coverageTexture;

        private static readonly int TextureSizeID = Shader.PropertyToID("_TextureSize");
        private static readonly int SeedID = Shader.PropertyToID("_Seed");
        private static readonly int WeatherMapID = Shader.PropertyToID("_WeatherMap");
        private static readonly int CurlMapID = Shader.PropertyToID("_CurlMap");
        private static readonly int CoverageMapID = Shader.PropertyToID("_CoverageMap");

        public RenderTexture WeatherTexture => weatherTexture;
        public RenderTexture CurlTexture => curlTexture;
        public RenderTexture CoverageTexture => coverageTexture;

        private void OnEnable()
        {
            if (generateOnEnable && weatherCurlCompute != null)
            {
                GenerateTextures();
            }
        }

        private void OnValidate()
        {
            weatherResolution = Mathf.Max(32, weatherResolution);
            curlResolution = Mathf.Max(32, curlResolution);
            coverageResolution = Mathf.Max(32, coverageResolution);
        }

        private void OnDisable()
        {
            ReleaseTextures();
        }

        [ContextMenu("Generate Flower Weather And Curl")]
        public void GenerateTextures()
        {
            if (weatherCurlCompute == null)
            {
                Debug.LogError("没有绑定 FlowerCloudWeatherCurl.compute。", this);
                return;
            }

            if (!SystemInfo.supportsComputeShaders)
            {
                Debug.LogError("当前平台不支持 Compute Shader。", this);
                return;
            }

            ReleaseTextures();

            GraphicsFormat scalarFormat = GetScalarFormat();
            GraphicsFormat vectorFormat = GetVectorFormat();

            weatherTexture = CreateTexture(
                "Flower Cloud Weather",
                weatherResolution,
                scalarFormat
            );

            curlTexture = CreateTexture(
                "Flower Cloud Curl",
                curlResolution,
                vectorFormat
            );

            coverageTexture = CreateTexture(
                "Flower Cloud Coverage",
                coverageResolution,
                scalarFormat
            );

            Dispatch(
                "GenerateWeather",
                WeatherMapID,
                weatherTexture,
                weatherResolution
            );

            Dispatch(
                "GenerateCurl",
                CurlMapID,
                curlTexture,
                curlResolution
            );

            Dispatch(
                "GenerateCoverage",
                CoverageMapID,
                coverageTexture,
                coverageResolution
            );

            Shader.SetGlobalTexture("_FlowerCloudWeather", weatherTexture);
            Shader.SetGlobalTexture("_FlowerCloudCurl", curlTexture);
            Shader.SetGlobalTexture("_FlowerCloudCoverageNoise", coverageTexture);

            Debug.Log(
                $"Flower Weather/Curl 生成完成：Weather {weatherResolution}²，Curl {curlResolution}²，Coverage {coverageResolution}²。",
                this
            );
        }

        private void Dispatch(
            string kernelName,
            int texturePropertyID,
            RenderTexture target,
            int resolution
        )
        {
            int kernel = weatherCurlCompute.FindKernel(kernelName);

            weatherCurlCompute.SetInts(TextureSizeID, resolution, resolution);
            weatherCurlCompute.SetFloat(SeedID, seed);
            weatherCurlCompute.SetTexture(kernel, texturePropertyID, target);

            int groupCount = Mathf.CeilToInt(resolution / 8.0f);
            weatherCurlCompute.Dispatch(kernel, groupCount, groupCount, 1);
        }

        private static RenderTexture CreateTexture(
            string textureName,
            int resolution,
            GraphicsFormat format
        )
        {
            RenderTextureDescriptor descriptor = new RenderTextureDescriptor(
                resolution,
                resolution
            );

            descriptor.graphicsFormat = format;
            descriptor.depthBufferBits = 0;
            descriptor.msaaSamples = 1;
            descriptor.enableRandomWrite = true;
            descriptor.useMipMap = false;
            descriptor.autoGenerateMips = false;

            RenderTexture texture = new RenderTexture(descriptor);
            texture.name = textureName;
            texture.wrapMode = TextureWrapMode.Repeat;
            texture.filterMode = FilterMode.Bilinear;

            if (!texture.Create())
            {
                DestroyUnityObject(texture);
                throw new System.Exception($"创建 RenderTexture 失败：{textureName}");
            }

            return texture;
        }

        private static GraphicsFormat GetScalarFormat()
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

        private static GraphicsFormat GetVectorFormat()
        {
            if (SystemInfo.IsFormatSupported(
                GraphicsFormat.R16G16B16A16_SFloat,
                FormatUsage.LoadStore
            ))
            {
                return GraphicsFormat.R16G16B16A16_SFloat;
            }

            return GraphicsFormat.R32G32B32A32_SFloat;
        }

        [ContextMenu("Release Flower Weather And Curl")]
        public void ReleaseTextures()
        {
            ReleaseTexture(ref weatherTexture);
            ReleaseTexture(ref curlTexture);
            ReleaseTexture(ref coverageTexture);
        }

        private static void ReleaseTexture(ref RenderTexture texture)
        {
            if (texture == null)
            {
                return;
            }

            texture.Release();
            DestroyUnityObject(texture);
            texture = null;
        }

        private static void DestroyUnityObject(Object target)
        {
            if (target == null)
            {
                return;
            }

            if (Application.isPlaying)
            {
                Object.Destroy(target);
            }
            else
            {
                Object.DestroyImmediate(target);
            }
        }
    }
}