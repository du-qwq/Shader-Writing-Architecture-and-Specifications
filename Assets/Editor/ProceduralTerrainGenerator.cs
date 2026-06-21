using UnityEditor;
using UnityEngine;

public class ProceduralTerrainGenerator : EditorWindow
{
    private Terrain targetTerrain;

    [Header("Height")]
    [Range(0f, 1f)]
    private float baseHeight = 0.18f;

    [Range(0f, 1f)]
    private float heightStrength = 0.22f;

    [Header("Noise")]
    private int seed = 12345;

    [Range(0.02f, 1f)]
    private float mainNoiseScale = 0.25f;

    [Range(1, 8)]
    private int octaves = 3;

    [Range(0.1f, 0.9f)]
    private float persistence = 0.4f;

    [Range(1.2f, 4f)]
    private float lacunarity = 1.8f;

    [Header("Shape")]
    [Range(0f, 1f)]
    private float edgeFalloff = 0.15f;

    [Range(0.5f, 5f)]
    private float mountainPower = 1.1f;

    [Range(0, 10)]
    private int smoothIterations = 4;

    [Header("Terrain Layers")]
    private TerrainLayer lowLayer;
    private TerrainLayer grassLayer;
    private TerrainLayer rockLayer;
    private TerrainLayer snowLayer;

    [Header("Height Paint")]
    [Range(0f, 1f)]
    private float grassStartHeight = 0.18f;

    [Range(0f, 1f)]
    private float rockStartHeight = 0.34f;

    [Range(0f, 1f)]
    private float snowStartHeight = 0.55f;

    [Range(0.001f, 0.3f)]
    private float blendRange = 0.08f;

    [Header("Slope Paint")]
    [Range(0f, 90f)]
    private float rockSlopeStart = 28f;

    [Range(0f, 90f)]
    private float rockSlopeFull = 48f;

    [Range(0f, 90f)]
    private float snowSlopeLimit = 50f;

    [Range(0f, 2f)]
    private float slopeRockStrength = 1.2f;

    private bool autoPaintAfterGenerate = true;

    [MenuItem("Tools/Terrain/Procedural Terrain Generator")]
    public static void Open()
    {
        GetWindow<ProceduralTerrainGenerator>("Terrain Generator");
    }

    private void OnGUI()
    {
        GUILayout.Label("Procedural Terrain Generator", EditorStyles.boldLabel);

        targetTerrain = (Terrain)EditorGUILayout.ObjectField(
            "Target Terrain",
            targetTerrain,
            typeof(Terrain),
            true
        );

        GUILayout.Space(8);

        if (GUILayout.Button("Use Selected Terrain"))
        {
            UseSelectedTerrain();
        }

        GUILayout.Space(12);

        GUILayout.Label("Height", EditorStyles.boldLabel);

        baseHeight = EditorGUILayout.Slider("Base Height", baseHeight, 0f, 1f);
        heightStrength = EditorGUILayout.Slider("Height Strength", heightStrength, 0f, 1f);

        GUILayout.Space(8);

        GUILayout.Label("Noise", EditorStyles.boldLabel);

        seed = EditorGUILayout.IntField("Seed", seed);

        mainNoiseScale = EditorGUILayout.Slider(
            "Main Noise Scale",
            mainNoiseScale,
            0.02f,
            1f
        );

        octaves = EditorGUILayout.IntSlider("Octaves", octaves, 1, 8);
        persistence = EditorGUILayout.Slider("Persistence", persistence, 0.1f, 0.9f);
        lacunarity = EditorGUILayout.Slider("Lacunarity", lacunarity, 1.2f, 4f);

        GUILayout.Space(8);

        GUILayout.Label("Shape", EditorStyles.boldLabel);

        edgeFalloff = EditorGUILayout.Slider("Edge Falloff", edgeFalloff, 0f, 1f);
        mountainPower = EditorGUILayout.Slider("Mountain Power", mountainPower, 0.5f, 5f);
        smoothIterations = EditorGUILayout.IntSlider("Smooth Iterations", smoothIterations, 0, 10);

        EditorGUILayout.HelpBox(
            "Main Noise Scale 越大，山越大块、越平缓。\n" +
            "Main Noise Scale 越小，山越密、越碎。\n\n" +
            "如果还太陡：降低 Height Strength，增加 Smooth Iterations。\n" +
            "如果太平：提高 Height Strength，降低 Smooth Iterations。",
            MessageType.Info
        );

        GUILayout.Space(12);

        GUILayout.Label("Auto Paint Layers", EditorStyles.boldLabel);

        autoPaintAfterGenerate = EditorGUILayout.Toggle(
            "Auto Paint After Generate",
            autoPaintAfterGenerate
        );

        lowLayer = (TerrainLayer)EditorGUILayout.ObjectField(
            "Low Layer",
            lowLayer,
            typeof(TerrainLayer),
            false
        );

        grassLayer = (TerrainLayer)EditorGUILayout.ObjectField(
            "Grass Layer",
            grassLayer,
            typeof(TerrainLayer),
            false
        );

        rockLayer = (TerrainLayer)EditorGUILayout.ObjectField(
            "Rock Layer",
            rockLayer,
            typeof(TerrainLayer),
            false
        );

        snowLayer = (TerrainLayer)EditorGUILayout.ObjectField(
            "Snow Layer",
            snowLayer,
            typeof(TerrainLayer),
            false
        );

        GUILayout.Space(8);

        GUILayout.Label("Height Paint", EditorStyles.boldLabel);

        grassStartHeight = EditorGUILayout.Slider(
            "Grass Start Height",
            grassStartHeight,
            0f,
            1f
        );

        rockStartHeight = EditorGUILayout.Slider(
            "Rock Start Height",
            rockStartHeight,
            0f,
            1f
        );

        snowStartHeight = EditorGUILayout.Slider(
            "Snow Start Height",
            snowStartHeight,
            0f,
            1f
        );

        blendRange = EditorGUILayout.Slider(
            "Blend Range",
            blendRange,
            0.001f,
            0.3f
        );

        GUILayout.Space(8);

        GUILayout.Label("Slope Paint", EditorStyles.boldLabel);

        rockSlopeStart = EditorGUILayout.Slider(
            "Rock Slope Start",
            rockSlopeStart,
            0f,
            90f
        );

        rockSlopeFull = EditorGUILayout.Slider(
            "Rock Slope Full",
            rockSlopeFull,
            0f,
            90f
        );

        snowSlopeLimit = EditorGUILayout.Slider(
            "Snow Slope Limit",
            snowSlopeLimit,
            0f,
            90f
        );

        slopeRockStrength = EditorGUILayout.Slider(
            "Slope Rock Strength",
            slopeRockStrength,
            0f,
            2f
        );

        EditorGUILayout.HelpBox(
            "低处平坦区域更容易刷 Low Layer。\n" +
            "中低处平坦区域更容易刷 Grass Layer。\n" +
            "坡度越陡越容易刷 Rock Layer。\n" +
            "高处且坡度不要太陡的地方更容易刷 Snow Layer。\n\n" +
            "Rock Slope Start：从多少度开始出现岩石。\n" +
            "Rock Slope Full：到多少度时岩石最明显。\n" +
            "Snow Slope Limit：超过这个坡度，雪会减少，避免陡峭悬崖全是雪。",
            MessageType.Info
        );

        GUILayout.Space(12);

        GUI.enabled = targetTerrain != null;

        if (GUILayout.Button("Generate Terrain"))
        {
            GenerateTerrain();
        }

        if (GUILayout.Button("Only Paint Layers"))
        {
            PaintTerrainLayers();
        }

        GUI.enabled = true;

        GUILayout.Space(8);

        if (GUILayout.Button("Random Seed"))
        {
            seed = Random.Range(0, 999999);
        }
    }

    private void UseSelectedTerrain()
    {
        if (Selection.activeGameObject == null)
        {
            Debug.LogWarning("当前没有选中物体。");
            return;
        }

        targetTerrain = Selection.activeGameObject.GetComponent<Terrain>();

        if (targetTerrain == null)
        {
            Debug.LogWarning("当前选中的物体不是 Terrain。");
        }
    }

    private void GenerateTerrain()
    {
        if (targetTerrain == null)
        {
            Debug.LogError("请先指定 Terrain。");
            return;
        }

        TerrainData terrainData = targetTerrain.terrainData;

        if (terrainData == null)
        {
            Debug.LogError("目标对象没有 TerrainData。");
            return;
        }

        Undo.RegisterCompleteObjectUndo(terrainData, "Generate Procedural Terrain");

        int resolution = terrainData.heightmapResolution;
        float[,] heights = new float[resolution, resolution];

        System.Random random = new System.Random(seed);
        Vector2[] octaveOffsets = new Vector2[octaves];

        for (int i = 0; i < octaves; i++)
        {
            float offsetX = random.Next(-100000, 100000);
            float offsetY = random.Next(-100000, 100000);
            octaveOffsets[i] = new Vector2(offsetX, offsetY);
        }

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                float u = x / (float)(resolution - 1);
                float v = y / (float)(resolution - 1);

                float noise = FractalNoise(
                    u,
                    v,
                    mainNoiseScale,
                    octaves,
                    persistence,
                    lacunarity,
                    octaveOffsets
                );

                noise = Mathf.SmoothStep(0f, 1f, noise);
                noise = Mathf.Pow(noise, mountainPower);

                float falloff = CalculateEdgeFalloff(u, v, edgeFalloff);

                float finalHeight = baseHeight + noise * heightStrength * falloff;

                heights[y, x] = Mathf.Clamp01(finalHeight);
            }
        }

        for (int i = 0; i < smoothIterations; i++)
        {
            heights = SmoothHeights(heights, resolution);
        }

        terrainData.SetHeights(0, 0, heights);

        if (autoPaintAfterGenerate)
        {
            PaintTerrainLayers();
        }

        EditorUtility.SetDirty(terrainData);
        EditorUtility.SetDirty(targetTerrain);

        Debug.Log("程序化地形生成完成。");
    }

    private void PaintTerrainLayers()
    {
        if (targetTerrain == null || targetTerrain.terrainData == null)
        {
            Debug.LogError("请先指定 Terrain。");
            return;
        }

        TerrainData terrainData = targetTerrain.terrainData;

        TerrainLayer[] layers = new TerrainLayer[]
        {
            lowLayer,
            grassLayer,
            rockLayer,
            snowLayer
        };

        for (int i = 0; i < layers.Length; i++)
        {
            if (layers[i] == null)
            {
                Debug.LogError("Terrain Layer 没有设置完整。请先拖入 Low / Grass / Rock / Snow 四个 TerrainLayer。");
                return;
            }
        }

        Undo.RegisterCompleteObjectUndo(terrainData, "Auto Paint Terrain Layers");

        terrainData.terrainLayers = layers;

        int alphaWidth = terrainData.alphamapWidth;
        int alphaHeight = terrainData.alphamapHeight;
        int layerCount = layers.Length;

        float[,,] splatmapData = new float[alphaHeight, alphaWidth, layerCount];

        for (int y = 0; y < alphaHeight; y++)
        {
            for (int x = 0; x < alphaWidth; x++)
            {
                float u = x / (float)(alphaWidth - 1);
                float v = y / (float)(alphaHeight - 1);

                float height01 = terrainData.GetInterpolatedHeight(u, v) / terrainData.size.y;
                float slopeDegree = terrainData.GetSteepness(u, v);

                float slopeRockMask = Mathf.SmoothStep(
                    0f,
                    1f,
                    Mathf.InverseLerp(rockSlopeStart, rockSlopeFull, slopeDegree)
                );

                slopeRockMask = Mathf.Clamp01(slopeRockMask * slopeRockStrength);

                float flatMask = 1f - slopeRockMask;

                float grassHeightMask = SmoothHeightMask(
                    height01,
                    grassStartHeight,
                    blendRange
                );

                float rockHeightMask = SmoothHeightMask(
                    height01,
                    rockStartHeight,
                    blendRange
                );

                float snowHeightMask = SmoothHeightMask(
                    height01,
                    snowStartHeight,
                    blendRange
                );

                float snowSlopeMask = 1f - Mathf.SmoothStep(
                    snowSlopeLimit - 10f,
                    snowSlopeLimit,
                    slopeDegree
                );

                float lowWeight =
                    (1f - grassHeightMask) *
                    flatMask;

                float grassWeight =
                    grassHeightMask *
                    (1f - rockHeightMask) *
                    flatMask;

                float rockWeight =
                    Mathf.Max(
                        rockHeightMask * 0.35f,
                        slopeRockMask
                    );

                rockWeight *= 1f - snowHeightMask * 0.4f;

                float snowWeight =
                    snowHeightMask *
                    snowSlopeMask *
                    flatMask;

                float total =
                    lowWeight +
                    grassWeight +
                    rockWeight +
                    snowWeight;

                if (total <= 0.0001f)
                {
                    lowWeight = 1f;
                    grassWeight = 0f;
                    rockWeight = 0f;
                    snowWeight = 0f;
                    total = 1f;
                }

                splatmapData[y, x, 0] = lowWeight / total;
                splatmapData[y, x, 1] = grassWeight / total;
                splatmapData[y, x, 2] = rockWeight / total;
                splatmapData[y, x, 3] = snowWeight / total;
            }
        }

        terrainData.SetAlphamaps(0, 0, splatmapData);

        EditorUtility.SetDirty(terrainData);
        EditorUtility.SetDirty(targetTerrain);

        Debug.Log("Terrain 材质层已按高度 + 坡度自动刷完。");
    }

    private static float SmoothHeightMask(float height01, float startHeight, float range)
    {
        float min = startHeight - range;
        float max = startHeight + range;
        return Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(min, max, height01));
    }

    private static float FractalNoise(
        float u,
        float v,
        float scale,
        int octaves,
        float persistence,
        float lacunarity,
        Vector2[] octaveOffsets
    )
    {
        scale = Mathf.Max(scale, 0.0001f);

        float amplitude = 1f;
        float frequency = 1f;
        float noiseHeight = 0f;
        float maxPossibleHeight = 0f;

        for (int i = 0; i < octaves; i++)
        {
            float sampleX = u / scale * frequency + octaveOffsets[i].x;
            float sampleY = v / scale * frequency + octaveOffsets[i].y;

            float perlin = Mathf.PerlinNoise(sampleX, sampleY);

            noiseHeight += perlin * amplitude;

            maxPossibleHeight += amplitude;
            amplitude *= persistence;
            frequency *= lacunarity;
        }

        return noiseHeight / maxPossibleHeight;
    }

    private static float CalculateEdgeFalloff(float u, float v, float strength)
    {
        if (strength <= 0f)
        {
            return 1f;
        }

        float distanceX = Mathf.Abs(u - 0.5f) * 2f;
        float distanceY = Mathf.Abs(v - 0.5f) * 2f;

        float distanceToEdge = Mathf.Max(distanceX, distanceY);

        float falloff = Mathf.SmoothStep(1f, 0f, distanceToEdge);

        return Mathf.Lerp(1f, falloff, strength);
    }

    private static float[,] SmoothHeights(float[,] heights, int resolution)
    {
        float[,] result = new float[resolution, resolution];

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                float sum = 0f;
                int count = 0;

                for (int oy = -1; oy <= 1; oy++)
                {
                    for (int ox = -1; ox <= 1; ox++)
                    {
                        int nx = x + ox;
                        int ny = y + oy;

                        if (nx >= 0 && nx < resolution && ny >= 0 && ny < resolution)
                        {
                            sum += heights[ny, nx];
                            count++;
                        }
                    }
                }

                result[y, x] = sum / count;
            }
        }

        return result;
    }
}