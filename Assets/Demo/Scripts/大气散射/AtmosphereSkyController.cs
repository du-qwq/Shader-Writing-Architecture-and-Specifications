using UnityEngine;

[ExecuteAlways]
public class AtmosphereSkyController : MonoBehaviour
{
    [Header("References")]
    public Material skyMaterial;
    public Light sunLight;

    [Header("Transmittance LUT")]
    public ComputeShader transmittanceLutCompute;
    public int transmittanceLutWidth = 256;
    public int transmittanceLutHeight = 64;

    [Header("Multi Scattering LUT")]
    public ComputeShader multiScatteringLutCompute;
    public int multiScatteringLutWidth = 32;
    public int multiScatteringLutHeight = 32;

    [Range(0.0f, 5.0f)]
    public float multiScatteringIntensity = 1.0f;

    [Header("Sky View LUT")]
    public ComputeShader skyViewLutCompute;
    public int skyViewLutWidth = 256;
    public int skyViewLutHeight = 128;

    [Header("Planet")]
    public float planetRadius = 6371000.0f;
    public float atmosphereHeight = 100000.0f;
    public float seaLevelY = 0.0f;

    [Header("Scattering")]
    public float sunIntensity = 20.0f;
    public float exposure = 1.0f;
    public float rayleighScaleHeight = 8500.0f;
    public float mieScaleHeight = 1200.0f;

    [Range(-0.99f, 0.99f)]
    public float mieG = 0.76f;

    private RenderTexture transmittanceLut;
    private RenderTexture multiScatteringLut;
    private RenderTexture skyViewLut;

    private int lastTransmittanceLutWidth;
    private int lastTransmittanceLutHeight;

    private float lastPlanetRadius;
    private float lastAtmosphereHeight;
    private float lastRayleighScaleHeight;
    private float lastMieScaleHeight;

    private void OnEnable()
    {
        CreateTransmittanceLut();
        CreateMultiScatteringLut();
        CreateSkyViewLut();

        PrecomputeTransmittanceLut();
        PrecomputeMultiScatteringLut();
        PrecomputeSkyViewLut();

        Apply();
    }

    private void OnDisable()
    {
        ReleaseTransmittanceLut();
        ReleaseMultiScatteringLut();
        ReleaseSkyViewLut();
    }

    private void OnDestroy()
    {
        ReleaseTransmittanceLut();
        ReleaseMultiScatteringLut();
        ReleaseSkyViewLut();
    }

    private void Update()
    {
        if (NeedRecomputeTransmittanceLut())
        {
            PrecomputeTransmittanceLut();
        }

        // 先每帧重算，方便你调参数和太阳方向。
        // 稳定后可以改成参数变化才重算。
        PrecomputeMultiScatteringLut();
        PrecomputeSkyViewLut();

        Apply();
    }

    private bool NeedRecomputeTransmittanceLut()
    {
        if (transmittanceLut == null)
        {
            return true;
        }

        if (lastTransmittanceLutWidth != transmittanceLutWidth)
        {
            return true;
        }

        if (lastTransmittanceLutHeight != transmittanceLutHeight)
        {
            return true;
        }

        if (!Mathf.Approximately(lastPlanetRadius, planetRadius))
        {
            return true;
        }

        if (!Mathf.Approximately(lastAtmosphereHeight, atmosphereHeight))
        {
            return true;
        }

        if (!Mathf.Approximately(lastRayleighScaleHeight, rayleighScaleHeight))
        {
            return true;
        }

        if (!Mathf.Approximately(lastMieScaleHeight, mieScaleHeight))
        {
            return true;
        }

        return false;
    }

    private Vector3 GetSunDir()
    {
        if (sunLight == null)
        {
            return Vector3.up;
        }

        // Unity Directional Light 的 forward 是光线照射方向。
        // Shader / Compute 里需要的是“从采样点指向太阳”的方向，所以取反。
        return (-sunLight.transform.forward).normalized;
    }

    private float GetCameraHeight()
    {
        Camera cam = Camera.main;

        if (cam == null)
        {
            return 0.0f;
        }

        return Mathf.Max(0.0f, cam.transform.position.y - seaLevelY);
    }

    private Vector3 GetPlanetCenter()
    {
        Camera cam = Camera.main;
        Vector3 camPos = cam != null ? cam.transform.position : Vector3.zero;

        // 地球中心始终放在相机水平位置正下方，海平面为 seaLevelY
        return new Vector3(
            camPos.x,
            seaLevelY - planetRadius,
            camPos.z
        );
    }

    private void CreateTransmittanceLut()
    {
        ReleaseTransmittanceLut();

        transmittanceLut = new RenderTexture(
            transmittanceLutWidth,
            transmittanceLutHeight,
            0,
            RenderTextureFormat.ARGBHalf
        );

        transmittanceLut.name = "Transmittance LUT";
        transmittanceLut.enableRandomWrite = true;
        transmittanceLut.wrapMode = TextureWrapMode.Clamp;
        transmittanceLut.filterMode = FilterMode.Bilinear;
        transmittanceLut.Create();

        lastTransmittanceLutWidth = transmittanceLutWidth;
        lastTransmittanceLutHeight = transmittanceLutHeight;
    }

    private void CreateMultiScatteringLut()
    {
        ReleaseMultiScatteringLut();

        multiScatteringLut = new RenderTexture(
            multiScatteringLutWidth,
            multiScatteringLutHeight,
            0,
            RenderTextureFormat.ARGBHalf
        );

        multiScatteringLut.name = "Multi Scattering LUT";
        multiScatteringLut.enableRandomWrite = true;
        multiScatteringLut.wrapMode = TextureWrapMode.Clamp;
        multiScatteringLut.filterMode = FilterMode.Bilinear;
        multiScatteringLut.Create();
    }

    private void CreateSkyViewLut()
    {
        ReleaseSkyViewLut();

        skyViewLut = new RenderTexture(
            skyViewLutWidth,
            skyViewLutHeight,
            0,
            RenderTextureFormat.ARGBHalf
        );

        skyViewLut.name = "Sky View LUT";
        skyViewLut.enableRandomWrite = true;
        skyViewLut.wrapMode = TextureWrapMode.Repeat;
        skyViewLut.filterMode = FilterMode.Bilinear;
        skyViewLut.Create();
    }

    private void ReleaseTransmittanceLut()
    {
        if (transmittanceLut == null)
        {
            return;
        }

        if (Application.isPlaying)
        {
            Destroy(transmittanceLut);
        }
        else
        {
            DestroyImmediate(transmittanceLut);
        }

        transmittanceLut = null;
    }

    private void ReleaseMultiScatteringLut()
    {
        if (multiScatteringLut == null)
        {
            return;
        }

        if (Application.isPlaying)
        {
            Destroy(multiScatteringLut);
        }
        else
        {
            DestroyImmediate(multiScatteringLut);
        }

        multiScatteringLut = null;
    }

    private void ReleaseSkyViewLut()
    {
        if (skyViewLut == null)
        {
            return;
        }

        if (Application.isPlaying)
        {
            Destroy(skyViewLut);
        }
        else
        {
            DestroyImmediate(skyViewLut);
        }

        skyViewLut = null;
    }

    private void PrecomputeTransmittanceLut()
    {
        if (transmittanceLutCompute == null)
        {
            Debug.LogWarning("Transmittance LUT Compute Shader is missing.");
            return;
        }

        if (transmittanceLut == null ||
            transmittanceLut.width != transmittanceLutWidth ||
            transmittanceLut.height != transmittanceLutHeight)
        {
            CreateTransmittanceLut();
        }

        int kernel = transmittanceLutCompute.FindKernel("CSMain");

        transmittanceLutCompute.SetTexture(kernel, "Result", transmittanceLut);

        transmittanceLutCompute.SetInt("_LutWidth", transmittanceLutWidth);
        transmittanceLutCompute.SetInt("_LutHeight", transmittanceLutHeight);

        transmittanceLutCompute.SetFloat("_PlanetRadius", planetRadius);
        transmittanceLutCompute.SetFloat("_AtmosphereHeight", atmosphereHeight);
        transmittanceLutCompute.SetFloat("_RayleighScaleHeight", rayleighScaleHeight);
        transmittanceLutCompute.SetFloat("_MieScaleHeight", mieScaleHeight);

        int groupsX = Mathf.CeilToInt(transmittanceLutWidth / 8.0f);
        int groupsY = Mathf.CeilToInt(transmittanceLutHeight / 8.0f);

        transmittanceLutCompute.Dispatch(kernel, groupsX, groupsY, 1);

        lastTransmittanceLutWidth = transmittanceLutWidth;
        lastTransmittanceLutHeight = transmittanceLutHeight;

        lastPlanetRadius = planetRadius;
        lastAtmosphereHeight = atmosphereHeight;
        lastRayleighScaleHeight = rayleighScaleHeight;
        lastMieScaleHeight = mieScaleHeight;

        if (skyMaterial != null)
        {
            skyMaterial.SetTexture("_TransmittanceLut", transmittanceLut);
        }
    }

    private void PrecomputeMultiScatteringLut()
    {
        if (multiScatteringLutCompute == null)
        {
            Debug.LogWarning("Multi Scattering LUT Compute Shader is missing.");
            return;
        }

        if (transmittanceLut == null)
        {
            Debug.LogWarning("Transmittance LUT is missing.");
            return;
        }

        if (multiScatteringLut == null ||
            multiScatteringLut.width != multiScatteringLutWidth ||
            multiScatteringLut.height != multiScatteringLutHeight)
        {
            CreateMultiScatteringLut();
        }

        int kernel = multiScatteringLutCompute.FindKernel("CSMain");

        multiScatteringLutCompute.SetTexture(kernel, "Result", multiScatteringLut);
        multiScatteringLutCompute.SetTexture(kernel, "_TransmittanceLut", transmittanceLut);

        multiScatteringLutCompute.SetInt("_LutWidth", multiScatteringLutWidth);
        multiScatteringLutCompute.SetInt("_LutHeight", multiScatteringLutHeight);

        multiScatteringLutCompute.SetFloat("_PlanetRadius", planetRadius);
        multiScatteringLutCompute.SetFloat("_AtmosphereHeight", atmosphereHeight);
        multiScatteringLutCompute.SetFloat("_RayleighScaleHeight", rayleighScaleHeight);
        multiScatteringLutCompute.SetFloat("_MieScaleHeight", mieScaleHeight);
        multiScatteringLutCompute.SetFloat("_MieG", mieG);
        multiScatteringLutCompute.SetFloat("_MultiScatteringIntensity", multiScatteringIntensity);

        int groupsX = Mathf.CeilToInt(multiScatteringLutWidth / 8.0f);
        int groupsY = Mathf.CeilToInt(multiScatteringLutHeight / 8.0f);

        multiScatteringLutCompute.Dispatch(kernel, groupsX, groupsY, 1);

        if (skyMaterial != null)
        {
            skyMaterial.SetTexture("_MultiScatteringLut", multiScatteringLut);
        }
    }

    private void PrecomputeSkyViewLut()
    {
        if (skyViewLutCompute == null)
        {
            Debug.LogWarning("Sky View LUT Compute Shader is missing.");
            return;
        }

        if (transmittanceLut == null)
        {
            Debug.LogWarning("Transmittance LUT is missing.");
            return;
        }

        if (multiScatteringLut == null)
        {
            Debug.LogWarning("Multi Scattering LUT is missing.");
            return;
        }

        if (skyViewLut == null ||
            skyViewLut.width != skyViewLutWidth ||
            skyViewLut.height != skyViewLutHeight)
        {
            CreateSkyViewLut();
        }

        int kernel = skyViewLutCompute.FindKernel("CSMain");

        Vector3 sunDir = GetSunDir();
        float cameraHeight = GetCameraHeight();

        skyViewLutCompute.SetTexture(kernel, "Result", skyViewLut);
        skyViewLutCompute.SetTexture(kernel, "_TransmittanceLut", transmittanceLut);
        skyViewLutCompute.SetTexture(kernel, "_MultiScatteringLut", multiScatteringLut);

        skyViewLutCompute.SetInt("_LutWidth", skyViewLutWidth);
        skyViewLutCompute.SetInt("_LutHeight", skyViewLutHeight);

        skyViewLutCompute.SetFloat("_PlanetRadius", planetRadius);
        skyViewLutCompute.SetFloat("_AtmosphereHeight", atmosphereHeight);
        skyViewLutCompute.SetFloat("_RayleighScaleHeight", rayleighScaleHeight);
        skyViewLutCompute.SetFloat("_MieScaleHeight", mieScaleHeight);
        skyViewLutCompute.SetFloat("_MieG", mieG);
        skyViewLutCompute.SetFloat("_SunIntensity", sunIntensity);
        skyViewLutCompute.SetFloat("_CameraHeight", cameraHeight);

        // 这里控制 SkyViewLUT 里多重散射项的贡献强度
        skyViewLutCompute.SetFloat("_MultiScatteringContribution", 1.0f);

        skyViewLutCompute.SetVector("_SunDirWS", sunDir);

        int groupsX = Mathf.CeilToInt(skyViewLutWidth / 8.0f);
        int groupsY = Mathf.CeilToInt(skyViewLutHeight / 8.0f);

        skyViewLutCompute.Dispatch(kernel, groupsX, groupsY, 1);

        if (skyMaterial != null)
        {
            skyMaterial.SetTexture("_SkyViewLut", skyViewLut);
        }
    }

    private void Apply()
    {
        if (skyMaterial == null)
        {
            return;
        }

        RenderSettings.skybox = skyMaterial;

        Vector3 sunDir = GetSunDir();
        Vector3 planetCenter = GetPlanetCenter();

        skyMaterial.SetVector("_SunDirWS", sunDir);
        skyMaterial.SetVector("_PlanetCenterWS", planetCenter);

        skyMaterial.SetFloat("_PlanetRadius", planetRadius);
        skyMaterial.SetFloat("_AtmosphereHeight", atmosphereHeight);

        skyMaterial.SetFloat("_SunIntensity", sunIntensity);
        skyMaterial.SetFloat("_Exposure", exposure);

        skyMaterial.SetFloat("_RayleighScaleHeight", rayleighScaleHeight);
        skyMaterial.SetFloat("_MieScaleHeight", mieScaleHeight);
        skyMaterial.SetFloat("_MieG", mieG);

        if (transmittanceLut != null)
        {
            skyMaterial.SetTexture("_TransmittanceLut", transmittanceLut);
        }

        if (multiScatteringLut != null)
        {
            skyMaterial.SetTexture("_MultiScatteringLut", multiScatteringLut);
        }

        if (skyViewLut != null)
        {
            skyMaterial.SetTexture("_SkyViewLut", skyViewLut);
        }
    }
}