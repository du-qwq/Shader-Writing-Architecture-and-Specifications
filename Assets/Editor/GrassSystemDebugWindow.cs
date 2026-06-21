using UnityEditor;
using UnityEngine;

public class GrassSystemDebugWindow : EditorWindow
{
    private GrassDebugTextureType selectedTexture = GrassDebugTextureType.SlopeHistory;
    private Vector2 scrollPosition;
    private uint nearCount;
    private uint farCount;
    private double nextCountReadTime;
    private const double CountReadInterval = 0.5;

    [MenuItem("Tools/Infinite Grass/Grass Debug Window")]
    public static void OpenWindow()
    {
        GrassSystemDebugWindow window = GetWindow<GrassSystemDebugWindow>("Grass Debug");
        window.minSize = new Vector2(380, 560);
        window.Show();
    }

    private void OnEnable()
    {
        EditorApplication.update += OnEditorUpdate;
    }

    private void OnDisable()
    {
        EditorApplication.update -= OnEditorUpdate;
    }

    private void OnEditorUpdate()
    {
        if (EditorApplication.timeSinceStartup >= nextCountReadTime)
        {
            nextCountReadTime = EditorApplication.timeSinceStartup + CountReadInterval;
            UpdateGrassCounts();
            Repaint();
        }
    }

    private void UpdateGrassCounts()
    {
        InfiniteGrassRenderer renderer = GetGrassRenderer();

        if (renderer == null)
        {
            nearCount = 0;
            farCount = 0;
            return;
        }

        renderer.TryGetVisibleGrassCounts(out nearCount, out farCount);
    }

    private void OnGUI()
    {
        scrollPosition = EditorGUILayout.BeginScrollView(scrollPosition);

        InfiniteGrassRenderer renderer = GetGrassRenderer();
        GrassDataRendererFeature feature = GrassDataRendererFeature.activeInstance;

        DrawTitle("GPU Grass Debug");

        if (renderer == null)
        {
            EditorGUILayout.HelpBox("场景里没有找到 InfiniteGrassRenderer。", MessageType.Warning);
            EditorGUILayout.EndScrollView();
            return;
        }

        EditorGUILayout.BeginHorizontal();

        if (GUILayout.Button("选中 GrassSystem"))
        {
            Selection.activeGameObject = renderer.gameObject;
            EditorGUIUtility.PingObject(renderer.gameObject);
        }

        if (feature != null && GUILayout.Button("定位 Renderer Feature"))
        {
            Selection.activeObject = feature;
            EditorGUIUtility.PingObject(feature);
        }

        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(6);
        DrawTitle("调试显示");

        EditorGUI.BeginChangeCheck();
        GrassDebugMode newDebugMode = (GrassDebugMode)EditorGUILayout.EnumPopup("Debug Mode", renderer.debugMode);

        if (EditorGUI.EndChangeCheck())
        {
            Undo.RecordObject(renderer, "Change Grass Debug Mode");
            renderer.debugMode = newDebugMode;
            EditorUtility.SetDirty(renderer);
            SceneView.RepaintAll();
        }

        EditorGUILayout.HelpBox(
            "LOD：Near红、Far蓝\n" +
            "Mask：黑白密度遮罩\n" +
            "Slope：RG方向、B强度\n" +
            "Wind：RG方向、B强度\n" +
            "Burn：R历史烧焦、G当前燃烧\n" +
            "Height：高度编码\n" +
            "Color：颜色Modifier",
            MessageType.Info
        );

        EditorGUILayout.Space(6);
        DrawTitle("运行数据");

        EditorGUILayout.LabelField("Near Grass Count", nearCount.ToString("N0"));
        EditorGUILayout.LabelField("Far Grass Count", farCount.ToString("N0"));
        EditorGUILayout.LabelField("Visible Grass Count", (nearCount + farCount).ToString("N0"));

        long perBufferCapacity = Mathf.Max(1, Mathf.CeilToInt(renderer.maxBufferCount * 1000000f));
        long totalCapacity = perBufferCapacity * 2;
        float totalPositionBufferMB = totalCapacity * sizeof(float) * 3f / (1024f * 1024f);

        EditorGUILayout.LabelField("Near Buffer Capacity", perBufferCapacity.ToString("N0"));
        EditorGUILayout.LabelField("Far Buffer Capacity", perBufferCapacity.ToString("N0"));
        EditorGUILayout.LabelField("Position Buffer Memory", totalPositionBufferMB.ToString("F1") + " MB");
        EditorGUILayout.LabelField("RT Resolution", feature != null ? feature.DebugTextureSize + " × " + feature.DebugTextureSize : "Feature未激活");
        EditorGUILayout.LabelField("Draw Distance", renderer.drawDistance.ToString("F1"));
        EditorGUILayout.LabelField("LOD Distance", renderer.lodDistance.ToString("F1"));
        EditorGUILayout.LabelField("Spacing", renderer.spacing.ToString("F3"));
        EditorGUILayout.LabelField("Near Subdivision", renderer.nearGrassMeshSubdivision.ToString());
        EditorGUILayout.LabelField("Far Subdivision", renderer.farGrassMeshSubdivision.ToString());

        EditorGUILayout.Space(6);
        DrawTitle("历史数据控制");

        EditorGUI.BeginDisabledGroup(feature == null);

        EditorGUILayout.BeginHorizontal();

        if (GUILayout.Button("重置压草历史"))
        {
            feature.ResetSlopeHistory();
            SceneView.RepaintAll();
        }

        if (GUILayout.Button("重置燃烧历史"))
        {
            feature.ResetBurnHistory();
            SceneView.RepaintAll();
        }

        EditorGUILayout.EndHorizontal();

        if (GUILayout.Button("全部重置"))
        {
            feature.ResetSlopeHistory();
            feature.ResetBurnHistory();
            SceneView.RepaintAll();
        }

        EditorGUI.EndDisabledGroup();

        if (feature == null)
        {
            EditorGUILayout.HelpBox("当前没有找到已激活的 GrassDataRendererFeature，RT预览和历史重置暂不可用。", MessageType.Warning);
        }

        EditorGUILayout.Space(6);
        DrawTitle("数据 RT 预览");

        selectedTexture = (GrassDebugTextureType)EditorGUILayout.EnumPopup("Texture", selectedTexture);
        Texture previewTexture = feature != null ? feature.GetDebugTexture(selectedTexture) : null;

        float previewSize = Mathf.Min(position.width - 32f, 420f);
        Rect previewRect = GUILayoutUtility.GetRect(previewSize, previewSize, GUILayout.ExpandWidth(false));

        if (previewTexture != null)
        {
            EditorGUI.DrawPreviewTexture(previewRect, previewTexture, null, ScaleMode.ScaleToFit);
        }
        else
        {
            EditorGUI.DrawRect(previewRect, new Color(0.12f, 0.12f, 0.12f));
            GUI.Label(previewRect, "RT 尚未生成\n请确保场景相机和草系统正在渲染", CenteredLabelStyle());
        }

        EditorGUILayout.HelpBox("Terrain Layer 权重目前还没有接入草系统；完成 Terrain SplatMap 采样后，才能在这里增加 Terrain Layer 调试视图。", MessageType.None);

        EditorGUILayout.Space(8);
        EditorGUILayout.EndScrollView();
    }

    private static InfiniteGrassRenderer GetGrassRenderer()
    {
        if (InfiniteGrassRenderer.instance != null) return InfiniteGrassRenderer.instance;
        return FindObjectOfType<InfiniteGrassRenderer>();
    }

    private static void DrawTitle(string title)
    {
        EditorGUILayout.LabelField(title, EditorStyles.boldLabel);
    }

    private static GUIStyle CenteredLabelStyle()
    {
        GUIStyle style = new GUIStyle(EditorStyles.centeredGreyMiniLabel);
        style.alignment = TextAnchor.MiddleCenter;
        style.wordWrap = true;
        return style;
    }
}
