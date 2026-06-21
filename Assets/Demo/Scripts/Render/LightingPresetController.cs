using UnityEngine;

public class LightingPresetController : MonoBehaviour
{
    [System.Serializable]
    public class LightingPreset
    {
        [Header("Preset Info")]
        public string presetName = "New Preset";

        [Header("Main Light")]
        public Color mainLightColor = Color.white;
        [Range(0f, 5f)] public float mainLightIntensity = 1f;
        public Vector3 mainLightRotation = new Vector3(50f, -30f, 0f);

        [Header("Environment")]
        public Color ambientSkyColor = Color.gray;
        public Color ambientEquatorColor = Color.gray;
        public Color ambientGroundColor = Color.gray;

        [Header("Fog")]
        public bool enableFog = false;
        public Color fogColor = Color.gray;
        [Range(0f, 0.1f)] public float fogDensity = 0.01f;

        [Header("Global Toon Params")]
        public Color globalShadowColor = new Color(0.75f, 0.8f, 0.9f, 1f);
        [Range(0f, 1f)] public float globalToonThreshold = 0.5f;
        [Range(0.001f, 0.3f)] public float globalToonSmoothness = 0.06f;
    }

    [Header("References")]
    [SerializeField] private Light mainDirectionalLight;

    [Header("Presets")]
    [SerializeField] private LightingPreset dayPreset = new LightingPreset();
    [SerializeField] private LightingPreset sunsetPreset = new LightingPreset();
    [SerializeField] private LightingPreset nightPreset = new LightingPreset();

    [Header("Startup")]
    [SerializeField] private bool applyOnStart = true;

    public enum PresetType
    {
        Day,
        Sunset,
        Night
    }

    private void Start()
    {
        if (applyOnStart)
        {
            ApplyPreset(PresetType.Day);
        }
    }

    private void Reset()
    {
        mainDirectionalLight = FindMainDirectionalLight();

        SetupDefaultPresets();
    }

    [ContextMenu("Setup Default Presets")]
    public void SetupDefaultPresets()
    {
        dayPreset.presetName = "Day";
        dayPreset.mainLightColor = new Color(1f, 0.95f, 0.85f);
        dayPreset.mainLightIntensity = 1.2f;
        dayPreset.mainLightRotation = new Vector3(50f, -30f, 0f);
        dayPreset.ambientSkyColor = new Color(0.65f, 0.75f, 0.9f);
        dayPreset.ambientEquatorColor = new Color(0.55f, 0.6f, 0.7f);
        dayPreset.ambientGroundColor = new Color(0.35f, 0.35f, 0.35f);
        dayPreset.enableFog = false;
        dayPreset.fogColor = new Color(0.7f, 0.85f, 1f);
        dayPreset.fogDensity = 0.003f;
        dayPreset.globalShadowColor = new Color(0.75f, 0.8f, 0.9f, 1f);
        dayPreset.globalToonThreshold = 0.5f;
        dayPreset.globalToonSmoothness = 0.06f;

        sunsetPreset.presetName = "Sunset";
        sunsetPreset.mainLightColor = new Color(1f, 0.65f, 0.4f);
        sunsetPreset.mainLightIntensity = 1.0f;
        sunsetPreset.mainLightRotation = new Vector3(18f, -45f, 0f);
        sunsetPreset.ambientSkyColor = new Color(0.55f, 0.4f, 0.45f);
        sunsetPreset.ambientEquatorColor = new Color(0.45f, 0.3f, 0.35f);
        sunsetPreset.ambientGroundColor = new Color(0.25f, 0.2f, 0.2f);
        sunsetPreset.enableFog = true;
        sunsetPreset.fogColor = new Color(0.8f, 0.55f, 0.45f);
        sunsetPreset.fogDensity = 0.008f;
        sunsetPreset.globalShadowColor = new Color(0.55f, 0.45f, 0.6f, 1f);
        sunsetPreset.globalToonThreshold = 0.45f;
        sunsetPreset.globalToonSmoothness = 0.08f;

        nightPreset.presetName = "Night";
        nightPreset.mainLightColor = new Color(0.45f, 0.55f, 0.8f);
        nightPreset.mainLightIntensity = 0.45f;
        nightPreset.mainLightRotation = new Vector3(25f, -60f, 0f);
        nightPreset.ambientSkyColor = new Color(0.12f, 0.18f, 0.28f);
        nightPreset.ambientEquatorColor = new Color(0.08f, 0.1f, 0.16f);
        nightPreset.ambientGroundColor = new Color(0.04f, 0.05f, 0.07f);
        nightPreset.enableFog = true;
        nightPreset.fogColor = new Color(0.08f, 0.12f, 0.2f);
        nightPreset.fogDensity = 0.015f;
        nightPreset.globalShadowColor = new Color(0.35f, 0.45f, 0.7f, 1f);
        nightPreset.globalToonThreshold = 0.38f;
        nightPreset.globalToonSmoothness = 0.1f;
    }

    public void ApplyPreset(PresetType presetType)
    {
        LightingPreset preset = GetPreset(presetType);
        if (preset == null)
        {
            Debug.LogWarning("LightingPresetController: 预设为空");
            return;
        }

        ApplyPresetInternal(preset);
    }

    public void ApplyDay()
    {
        ApplyPreset(PresetType.Day);
    }

    public void ApplySunset()
    {
        ApplyPreset(PresetType.Sunset);
    }

    public void ApplyNight()
    {
        ApplyPreset(PresetType.Night);
    }

    private LightingPreset GetPreset(PresetType presetType)
    {
        switch (presetType)
        {
            case PresetType.Day:
                return dayPreset;
            case PresetType.Sunset:
                return sunsetPreset;
            case PresetType.Night:
                return nightPreset;
            default:
                return dayPreset;
        }
    }

    private void ApplyPresetInternal(LightingPreset preset)
    {
        if (mainDirectionalLight == null)
        {
            mainDirectionalLight = FindMainDirectionalLight();
        }

        if (mainDirectionalLight != null)
        {
            mainDirectionalLight.color = preset.mainLightColor;
            mainDirectionalLight.intensity = preset.mainLightIntensity;
            mainDirectionalLight.transform.rotation = Quaternion.Euler(preset.mainLightRotation);
        }
        else
        {
            Debug.LogWarning("LightingPresetController: 没找到主方向光");
        }

        RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
        RenderSettings.ambientSkyColor = preset.ambientSkyColor;
        RenderSettings.ambientEquatorColor = preset.ambientEquatorColor;
        RenderSettings.ambientGroundColor = preset.ambientGroundColor;

        RenderSettings.fog = preset.enableFog;
        RenderSettings.fogColor = preset.fogColor;
        RenderSettings.fogDensity = preset.fogDensity;

        Shader.SetGlobalColor("_GlobalToonShadowColor", preset.globalShadowColor);
        Shader.SetGlobalFloat("_GlobalToonThreshold", preset.globalToonThreshold);
        Shader.SetGlobalFloat("_GlobalToonSmoothness", preset.globalToonSmoothness);

        Debug.Log($"已应用光照预设: {preset.presetName}");
    }

    private Light FindMainDirectionalLight()
    {
        if (RenderSettings.sun != null)
            return RenderSettings.sun;

        Light[] lights = FindObjectsOfType<Light>();
        foreach (Light light in lights)
        {
            if (light.type == LightType.Directional)
                return light;
        }

        return null;
    }
}