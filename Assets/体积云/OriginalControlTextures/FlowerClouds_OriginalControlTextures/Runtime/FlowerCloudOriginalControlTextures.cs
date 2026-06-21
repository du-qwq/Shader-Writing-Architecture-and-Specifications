using UnityEngine;

namespace FlowerClouds
{
    [ExecuteAlways]
    [DefaultExecutionOrder(10000)]
    [DisallowMultipleComponent]
    public class FlowerCloudOriginalControlTextures : MonoBehaviour
    {
        [Header("Flower Original Textures")]
        [Tooltip("Flower install/image/T_CurlNoise.png")]
        public Texture2D curlTexture;

        [Tooltip("Flower install/image/cloudweather.png")]
        public Texture2D weatherTexture;

        [Tooltip("Flower install/image/cloudnoise.png")]
        public Texture2D cloudCurlNoiseTexture;

        [Header("Binding")]
        public bool keepBound = true;
        public bool logWhenBound = false;

        private static readonly int CurlTextureID =
            Shader.PropertyToID("_FlowerCloudCurl");

        private static readonly int WeatherTextureID =
            Shader.PropertyToID("_FlowerCloudWeather");

        private static readonly int CloudCurlNoiseTextureID =
            Shader.PropertyToID("_FlowerCloudCoverageNoise");

        private void OnEnable()
        {
            BindTextures();
        }

        private void OnValidate()
        {
            BindTextures();
        }

        private void Update()
        {
            if (keepBound)
            {
                BindTextures(false);
            }
        }

        [ContextMenu("Bind Flower Original Control Textures")]
        public void BindTextures()
        {
            BindTextures(logWhenBound);
        }

        private void BindTextures(bool shouldLog)
        {
            if (curlTexture != null)
            {
                Shader.SetGlobalTexture(CurlTextureID, curlTexture);
            }

            if (weatherTexture != null)
            {
                Shader.SetGlobalTexture(WeatherTextureID, weatherTexture);
            }

            if (cloudCurlNoiseTexture != null)
            {
                Shader.SetGlobalTexture(
                    CloudCurlNoiseTextureID,
                    cloudCurlNoiseTexture
                );
            }

            if (shouldLog)
            {
                Debug.Log(
                    "Flower original control textures bound: " +
                    $"Curl={(curlTexture != null ? curlTexture.name : "None")}, " +
                    $"Weather={(weatherTexture != null ? weatherTexture.name : "None")}, " +
                    $"CloudCurlNoise={(cloudCurlNoiseTexture != null ? cloudCurlNoiseTexture.name : "None")}.",
                    this
                );
            }
        }
    }
}
