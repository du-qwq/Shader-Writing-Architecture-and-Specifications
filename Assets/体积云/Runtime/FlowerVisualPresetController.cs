using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace FlowerClouds
{
    [ExecuteAlways]
    [DisallowMultipleComponent]
    public class FlowerVisualPresetController : MonoBehaviour
    {
        [Header("References")]
        public Volume targetVolume;
        public Material flowerSkyMaterial;
        public Light sunLight;

        [Header("Exposure")]
        public float postExposure = 1.5f;

        [Header("Bloom")]
        public bool bloomEnabled = true;

        [Range(0.0f, 10.0f)]
        public float bloomIntensity = 0.55f;

        [Range(0.0f, 1.0f)]
        public float bloomThreshold = 0.8f;

        [Range(0.0f, 1.0f)]
        public float bloomScatter = 0.7f;

        [Header("Color")]
        [Range(-100.0f, 100.0f)]
        public float contrast = 5.0f;

        [Range(-100.0f, 100.0f)]
        public float saturation = 8.0f;

        [Header("Sun")]
        [Range(0.0f, 100.0f)]
        public float sunDiskIntensity = 16.0f;

        public float sunAngularRadius = 0.00465f;
        public float sunDiskSoftness = 0.0015f;

        [Header("Apply")]
        public bool applyOnEnable = true;
        public bool keepApplied = false;

        private static readonly int SunDiskIntensityID =
            Shader.PropertyToID("_SunDiskIntensity");

        private static readonly int SunAngularRadiusID =
            Shader.PropertyToID("_SunAngularRadius");

        private static readonly int SunDiskSoftnessID =
            Shader.PropertyToID("_SunDiskSoftness");

        private void OnEnable()
        {
            ResolveReferences();

            if (applyOnEnable)
            {
                ApplyPreset();
            }
        }

        private void OnValidate()
        {
            ResolveReferences();

            if (!Application.isPlaying &&
                applyOnEnable)
            {
                ApplyPreset();
            }
        }

        private void Update()
        {
            if (keepApplied)
            {
                ApplyPreset();
            }
        }

        [ContextMenu("Apply Flower Visual Preset")]
        public void ApplyPreset()
        {
            ResolveReferences();

            if (flowerSkyMaterial != null)
            {
                flowerSkyMaterial.SetFloat(
                    SunDiskIntensityID,
                    sunDiskIntensity
                );

                flowerSkyMaterial.SetFloat(
                    SunAngularRadiusID,
                    sunAngularRadius
                );

                flowerSkyMaterial.SetFloat(
                    SunDiskSoftnessID,
                    sunDiskSoftness
                );

                if (RenderSettings.skybox !=
                    flowerSkyMaterial)
                {
                    RenderSettings.skybox =
                        flowerSkyMaterial;

                    DynamicGI.UpdateEnvironment();
                }
            }

            if (targetVolume == null)
            {
                return;
            }

            VolumeProfile profile =
                targetVolume.profile;

            Tonemapping tonemapping =
                GetOrAdd<Tonemapping>(profile);

            tonemapping.active = true;
            tonemapping.mode.Override(
                TonemappingMode.ACES
            );

            ColorAdjustments colorAdjustments =
                GetOrAdd<ColorAdjustments>(
                    profile
                );

            colorAdjustments.active = true;
            colorAdjustments.postExposure.Override(
                postExposure
            );

            colorAdjustments.contrast.Override(
                contrast
            );

            colorAdjustments.saturation.Override(
                saturation
            );

            Bloom bloom =
                GetOrAdd<Bloom>(profile);

            bloom.active =
                bloomEnabled;

            bloom.intensity.Override(
                bloomIntensity
            );

            bloom.threshold.Override(
                bloomThreshold
            );

            bloom.scatter.Override(
                bloomScatter
            );
        }

        private void ResolveReferences()
        {
            if (targetVolume == null)
            {
                targetVolume =
                    FindObjectOfType<Volume>();
            }

            if (sunLight == null)
            {
                sunLight =
                    RenderSettings.sun;
            }
        }

        private static T GetOrAdd<T>(
            VolumeProfile profile)
            where T : VolumeComponent
        {
            if (!profile.TryGet(out T component))
            {
                component =
                    profile.Add<T>(true);
            }

            return component;
        }
    }
}
