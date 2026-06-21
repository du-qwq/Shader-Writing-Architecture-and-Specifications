#if UNITY_EDITOR

using System.IO;
using UnityEditor;
using UnityEngine;

namespace FlowerClouds.Editor
{
    public class FlowerCloudOriginalTextureImporter : AssetPostprocessor
    {
        private static bool IsFlowerControlTexture(string assetPath)
        {
            string fileName = Path.GetFileName(assetPath);

            return fileName == "T_CurlNoise.png" ||
                   fileName == "cloudweather.png" ||
                   fileName == "cloudnoise.png";
        }

        private void OnPreprocessTexture()
        {
            if (!IsFlowerControlTexture(assetPath))
            {
                return;
            }

            TextureImporter importer = (TextureImporter)assetImporter;

            importer.textureType = TextureImporterType.Default;
            importer.textureShape = TextureImporterShape.Texture2D;
            importer.sRGBTexture = false;
            importer.alphaSource = TextureImporterAlphaSource.None;
            importer.wrapMode = TextureWrapMode.Repeat;
            importer.filterMode = FilterMode.Bilinear;
            importer.mipmapEnabled = false;
            importer.textureCompression = TextureImporterCompression.Uncompressed;
            importer.npotScale = TextureImporterNPOTScale.None;
        }
    }
}

#endif
