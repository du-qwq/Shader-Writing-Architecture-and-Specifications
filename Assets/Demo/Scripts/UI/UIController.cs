using UnityEngine;
using UnityEngine.UI;
using TMPro;

public class UIController : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private LightingPresetController lightingPresetController;

    [Header("Optional UI")]
    [SerializeField] private Button dayButton;
    [SerializeField] private Button sunsetButton;
    [SerializeField] private Button nightButton;
    [SerializeField] private TMP_Text currentModeText;

    [Header("Keyboard Test")]
    [SerializeField] private bool enableKeyboardTest = true;

    private void Start()
    {
        BindButtons();
        UpdateModeText("Day");
    }

    private void OnDestroy()
    {
        UnbindButtons();
    }

    private void Update()
    {
        if (!enableKeyboardTest || lightingPresetController == null)
            return;

        if (Input.GetKeyDown(KeyCode.Alpha1))
        {
            ApplyDay();
        }

        if (Input.GetKeyDown(KeyCode.Alpha2))
        {
            ApplySunset();
        }

        if (Input.GetKeyDown(KeyCode.Alpha3))
        {
            ApplyNight();
        }
    }

    private void BindButtons()
    {
        if (dayButton != null)
            dayButton.onClick.AddListener(ApplyDay);

        if (sunsetButton != null)
            sunsetButton.onClick.AddListener(ApplySunset);

        if (nightButton != null)
            nightButton.onClick.AddListener(ApplyNight);
    }

    private void UnbindButtons()
    {
        if (dayButton != null)
            dayButton.onClick.RemoveListener(ApplyDay);

        if (sunsetButton != null)
            sunsetButton.onClick.RemoveListener(ApplySunset);

        if (nightButton != null)
            nightButton.onClick.RemoveListener(ApplyNight);
    }

    public void ApplyDay()
    {
        if (lightingPresetController == null)
        {
            Debug.LogWarning("UIController: LightingPresetController 没拖");
            return;
        }

        lightingPresetController.ApplyDay();
        UpdateModeText("Day");
    }

    public void ApplySunset()
    {
        if (lightingPresetController == null)
        {
            Debug.LogWarning("UIController: LightingPresetController 没拖");
            return;
        }

        lightingPresetController.ApplySunset();
        UpdateModeText("Sunset");
    }

    public void ApplyNight()
    {
        if (lightingPresetController == null)
        {
            Debug.LogWarning("UIController: LightingPresetController 没拖");
            return;
        }

        lightingPresetController.ApplyNight();
        UpdateModeText("Night");
    }

    private void UpdateModeText(string modeName)
    {
        if (currentModeText != null)
        {
            currentModeText.text = "Lighting Mode: " + modeName;
        }
    }
}