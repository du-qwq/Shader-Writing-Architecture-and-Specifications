using UnityEngine;

[ExecuteAlways]
public class ToonRenderSettings : MonoBehaviour
{
    [Header("Global Toon Params")]
    [SerializeField] private Color globalShadowColor = new Color(0.75f, 0.8f, 0.9f, 1f);

    [Range(0f, 1f)]
    [SerializeField] private float globalToonThreshold = 0.5f;

    [Range(0.001f, 0.3f)]
    [SerializeField] private float globalToonSmoothness = 0.06f;

    [Header("Auto Apply")]
    [SerializeField] private bool applyOnEnable = true;
    [SerializeField] private bool applyEveryFrameInEditor = true;

    private static readonly int GlobalShadowColorID = Shader.PropertyToID("_GlobalToonShadowColor");
    private static readonly int GlobalToonThresholdID = Shader.PropertyToID("_GlobalToonThreshold");
    private static readonly int GlobalToonSmoothnessID = Shader.PropertyToID("_GlobalToonSmoothness");

    private void OnEnable()
    {
        if (applyOnEnable)
        {
            ApplySettings();
        }
    }

    private void OnValidate()
    {
        ApplySettings();
    }

    private void Update()
    {
#if UNITY_EDITOR
        if (!Application.isPlaying && applyEveryFrameInEditor)
        {
            ApplySettings();
        }
#endif
    }

    [ContextMenu("Apply Toon Settings")]
    public void ApplySettings()
    {
        Shader.SetGlobalColor(GlobalShadowColorID, globalShadowColor);
        Shader.SetGlobalFloat(GlobalToonThresholdID, globalToonThreshold);
        Shader.SetGlobalFloat(GlobalToonSmoothnessID, globalToonSmoothness);
    }

    public void SetShadowColor(Color color)
    {
        globalShadowColor = color;
        ApplySettings();
    }

    public void SetToonThreshold(float value)
    {
        globalToonThreshold = Mathf.Clamp01(value);
        ApplySettings();
    }

    public void SetToonSmoothness(float value)
    {
        globalToonSmoothness = Mathf.Clamp(value, 0.001f, 0.3f);
        ApplySettings();
    }

    public Color GetShadowColor()
    {
        return globalShadowColor;
    }

    public float GetToonThreshold()
    {
        return globalToonThreshold;
    }

    public float GetToonSmoothness()
    {
        return globalToonSmoothness;
    }
}