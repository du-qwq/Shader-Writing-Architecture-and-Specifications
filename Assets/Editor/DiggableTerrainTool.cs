using UnityEditor;
using UnityEngine;

public class DiggableTerrainTool : EditorWindow
{
    private Terrain targetTerrain;

    [Range(0.01f, 0.95f)]
    private float flatBaseHeight01 = 0.35f;

    [Range(0.01f, 0.95f)]
    private float liftAmount01 = 0.25f;

    private bool normalizeBeforeLift = false;

    [MenuItem("Tools/Terrain/Make Terrain Diggable")]
    public static void Open()
    {
        GetWindow<DiggableTerrainTool>("Diggable Terrain");
    }

    private void OnGUI()
    {
        GUILayout.Label("Make Terrain Diggable", EditorStyles.boldLabel);

        EditorGUILayout.HelpBox(
            "Unity 新建 Terrain 默认高度是 0，所以 Shift 往下刷不会有变化。\n\n" +
            "如果是新 Terrain，可以用 Set Flat Base Height。\n" +
            "如果已经刷过地形，建议用 Lift Existing Terrain，它会保留原地形形状，只整体抬高高度图。",
            MessageType.Info
        );

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

        DrawFlatTerrainSection();

        GUILayout.Space(12);

        DrawLiftTerrainSection();
    }

    private void DrawFlatTerrainSection()
    {
        GUILayout.Label("新 Terrain：设置统一基准高度", EditorStyles.boldLabel);

        flatBaseHeight01 = EditorGUILayout.Slider(
            "Base Height",
            flatBaseHeight01,
            0.01f,
            0.95f
        );

        GUI.enabled = targetTerrain != null;

        if (GUILayout.Button("Set Flat Base Height"))
        {
            SetFlatBaseHeight(targetTerrain, flatBaseHeight01);
        }

        GUI.enabled = true;
    }

    private void DrawLiftTerrainSection()
    {
        GUILayout.Label("已有地形：保留形状并整体抬高", EditorStyles.boldLabel);

        liftAmount01 = EditorGUILayout.Slider(
            "Lift Amount",
            liftAmount01,
            0.01f,
            0.95f
        );

        normalizeBeforeLift = EditorGUILayout.Toggle(
            "Normalize Before Lift",
            normalizeBeforeLift
        );

        EditorGUILayout.HelpBox(
            "Lift Amount：在现有高度基础上整体增加。\n" +
            "Normalize Before Lift：先把当前最低点压到 0，再整体抬高。一般不勾也可以。\n\n" +
            "推荐：Lift Amount 先用 0.2 或 0.3。",
            MessageType.None
        );

        GUI.enabled = targetTerrain != null;

        if (GUILayout.Button("Lift Existing Terrain"))
        {
            LiftExistingTerrain(targetTerrain, liftAmount01, normalizeBeforeLift);
        }

        GUI.enabled = true;
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

    private static void SetFlatBaseHeight(Terrain terrain, float height01)
    {
        if (!CheckTerrain(terrain))
        {
            return;
        }

        TerrainData terrainData = terrain.terrainData;

        Undo.RegisterCompleteObjectUndo(terrainData, "Set Flat Terrain Base Height");

        int resolution = terrainData.heightmapResolution;
        float[,] heights = new float[resolution, resolution];

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                heights[y, x] = height01;
            }
        }

        terrainData.SetHeights(0, 0, heights);

        EditorUtility.SetDirty(terrainData);
        EditorUtility.SetDirty(terrain);

        Debug.Log($"已设置统一基准高度：{height01}");
    }

    private static void LiftExistingTerrain(
        Terrain terrain,
        float liftAmount01,
        bool normalizeBeforeLift
    )
    {
        if (!CheckTerrain(terrain))
        {
            return;
        }

        TerrainData terrainData = terrain.terrainData;

        Undo.RegisterCompleteObjectUndo(terrainData, "Lift Existing Terrain");

        int resolution = terrainData.heightmapResolution;
        float[,] heights = terrainData.GetHeights(0, 0, resolution, resolution);

        float minHeight = 1f;
        float maxHeight = 0f;

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                float h = heights[y, x];

                if (h < minHeight)
                {
                    minHeight = h;
                }

                if (h > maxHeight)
                {
                    maxHeight = h;
                }
            }
        }

        float availableUpSpace;

        if (normalizeBeforeLift)
        {
            availableUpSpace = 1f - (maxHeight - minHeight);
        }
        else
        {
            availableUpSpace = 1f - maxHeight;
        }

        float safeLiftAmount = Mathf.Min(liftAmount01, availableUpSpace);

        if (safeLiftAmount <= 0f)
        {
            Debug.LogWarning("当前地形已经接近最高高度，无法继续整体抬高。");
            return;
        }

        for (int y = 0; y < resolution; y++)
        {
            for (int x = 0; x < resolution; x++)
            {
                float h = heights[y, x];

                if (normalizeBeforeLift)
                {
                    h -= minHeight;
                }

                h += safeLiftAmount;
                h = Mathf.Clamp01(h);

                heights[y, x] = h;
            }
        }

        terrainData.SetHeights(0, 0, heights);

        EditorUtility.SetDirty(terrainData);
        EditorUtility.SetDirty(terrain);

        Debug.Log(
            $"已保留地形形状并整体抬高。\n" +
            $"原最低高度：{minHeight:F3}，原最高高度：{maxHeight:F3}，实际抬高：{safeLiftAmount:F3}"
        );
    }

    private static bool CheckTerrain(Terrain terrain)
    {
        if (terrain == null)
        {
            Debug.LogError("没有指定 Terrain。");
            return false;
        }

        if (terrain.terrainData == null)
        {
            Debug.LogError("Terrain 没有 TerrainData。");
            return false;
        }

        return true;
    }
}