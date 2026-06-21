Flower Original Control Textures - Unity URP Port

Source:
https://github.com/qiutang98/flower/tree/dark/install/image

Texture mapping:
T_CurlNoise.png  -> _FlowerCloudCurl
cloudweather.png -> _FlowerCloudWeather
cloudnoise.png   -> _FlowerCloudCoverageNoise

Unity setup:
1. Copy this folder into Assets/FlowerClouds/OriginalControlTextures.
2. Wait for Unity compilation.
3. Select the three PNG files and Reimport once, so the included AssetPostprocessor applies:
   - sRGB Off
   - Wrap Repeat
   - Filter Bilinear
   - Compression None
   - Mip Maps Off
4. Create an empty GameObject named FlowerCloudOriginalTextures.
5. Add FlowerCloudOriginalControlTextures.cs.
6. Assign:
   Curl Texture = T_CurlNoise
   Weather Texture = cloudweather
   Cloud Curl Noise Texture = cloudnoise
7. Disable the old FlowerCloudWeatherCurlGenerator component/GameObject.
8. Keep FlowerCloudNoiseGenerator enabled, because Basic/Detail 3D noise still come from it.

Recommended renderer parameters for the original density port:
Cloud Bottom = 500
Cloud Top = 11000
Cloud Coverage = 0.5
Cloud Density = 1
Weather UV Scale = 0.03
Basic Noise Scale X = 0.15
Detail Noise Scale X = 0.8
Cloud Direction = (1, 0, 0)
Cloud Speed = 0.05
