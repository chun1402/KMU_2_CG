// =====================================================================
//  Class 11 - 라이팅 테스트 (슬라이드 p.64 ~ p.68 까지만)
//  Advanced Computer Graphics / Mankyu Sung
//
//  사용 (상단 메뉴 Tools > Class11)  — 1119 씬을 열고 실행
//    1. Build Test Scene : p.64 ~ p.67 씬 구성 + p.68 설정
//    2. Bake Lighting    : p.68 Generate Lighting
//    0. Clear Test Scene : 만든 것들을 지운다
//
//  p.68 "GI 를 위해 Baked Light 테스트" 가 목표
//    - 모든 light 을 disable (directional / point / spot)
//    - wall, plane, 캡슐 모두 static -> Generate Lighting
//    - Red wall 의 emission 을 red, intensity 2.0 으로
//      -> 벽 아래 바닥이 불그스름해지고, 캡슐의 벽 쪽 면이 붉게 물든다
//    - 바닥 green 은 순수 (0,1,0) 이면 안 된다 (R 이 0 이면 붉은빛이 곱해져 0 이 됨)
// =====================================================================
#if UNITY_EDITOR
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;
using UnityEditor.SceneManagement;

public static class IndirectLightingTestSetup
{
    private const string RootName   = "Class11_LightingTest";
    private const string ScenePath  = "Assets/Scenes/1119.unity";
    private const string FolderPath = "Assets/1119/Class11_Lighting";
    private const string MatPath    = FolderPath + "/Materials";

    // p.64 : 완벽한 green 이면 x -> 다른 채널을 조금씩 섞는다
    private static readonly Color GreenCol  = new Color(0.20f, 0.55f, 0.22f);
    private static readonly Color RedCol    = new Color(0.80f, 0.12f, 0.10f);
    private static readonly Color BlueCol   = new Color(0.14f, 0.20f, 0.70f);
    private static readonly Color YellowCol = new Color(0.72f, 0.65f, 0.15f);
    private static readonly Color WhiteCol  = new Color(0.90f, 0.90f, 0.90f);

    // p.68 : Red wall emission intensity = 2.0  (HDR 피커의 intensity 는 2^i 배)
    private const float RedEmissionIntensity = 2.0f;

    // =================================================================
    [MenuItem("Tools/Class11/1. Build Test Scene", false, 1)]
    public static void BuildScene()
    {
        Clear();
        EnsureFolders();

        GameObject root = new GameObject(RootName);

        // ---- 바닥 (p.66) : Position(0,0,0)  Scale(10,1,10) ----
        Material greenMat = MakeMaterial("M_Ground_Green", GreenCol);
        GameObject plane = MakePrimitive(PrimitiveType.Plane, "Ground",
            new Vector3(0f, 0f, 0f), new Vector3(10f, 1f, 10f), greenMat, root.transform);

        // ---- 벽 3개 (p.67) : 모두 Scale(10,4,1), y = 2 ----
        Material yellowMat = MakeMaterial("M_Wall_Yellow", YellowCol);
        Material blueMat   = MakeMaterial("M_Wall_Blue",   BlueCol);
        Material redMat    = MakeMaterial("M_Wall_Red",    RedCol);
        SetBakedEmission(redMat, RedCol, RedEmissionIntensity);   // p.68

        GameObject wallY = MakePrimitive(PrimitiveType.Cube, "Wall_Yellow",
            new Vector3(-10f, 2f, 0f), new Vector3(10f, 4f, 1f), yellowMat, root.transform);
        GameObject wallB = MakePrimitive(PrimitiveType.Cube, "Wall_Blue",
            new Vector3(0f, 2f, 0f), new Vector3(10f, 4f, 1f), blueMat, root.transform);
        GameObject wallR = MakePrimitive(PrimitiveType.Cube, "Wall_Red",
            new Vector3(10f, 2f, 0f), new Vector3(10f, 4f, 1f), redMat, root.transform);

        // ---- 캡슐 (p.64) : 벽 왼쪽 가까이, 흰색 ----
        // 빨간 벽(x 5~15) 의 왼쪽 부분, 벽 앞면(z = -0.5) 바로 앞
        Material whiteMat = MakeMaterial("M_Capsule_White", WhiteCol);
        GameObject capsule = MakePrimitive(PrimitiveType.Capsule, "Capsule",
            new Vector3(6.5f, 1f, -1.3f), Vector3.one, whiteMat, root.transform);

        // ---- p.68 : wall, plane, 캡슐 모두 static ----
        MarkStatic(plane);
        MarkStatic(wallY);
        MarkStatic(wallB);
        MarkStatic(wallR);
        MarkStatic(capsule);

        // ---- p.68 : 모든 light 을 disable ----
        DisableAllLights();

        // ---- 환경광 (p.68 : Environment intensity 1) ----
        RenderSettings.ambientMode      = AmbientMode.Skybox;
        RenderSettings.ambientIntensity = 1.0f;
        RenderSettings.sun              = null;

        // ---- Lighting Settings (Window | Rendering | Lighting | Scene) ----
        SetupLightingSettings();

        // ---- 카메라 : 캡슐과 빨간 벽이 잘 보이게 ----
        SetupCamera();

        Selection.activeGameObject = root;
        EditorSceneManager.MarkSceneDirty(EditorSceneManager.GetActiveScene());

        Debug.Log("[Class11] 씬 생성 완료 (p.64~68). 다음 : Tools > Class11 > 2. Bake Lighting");
    }

    // =================================================================
    [MenuItem("Tools/Class11/2. Bake Lighting", false, 2)]
    public static void BakeLighting()
    {
        if (Lightmapping.isRunning)
        {
            Debug.LogWarning("[Class11] 이미 베이크 중입니다.");
            return;
        }
        Debug.Log("[Class11] Generate Lighting 시작. 에디터 우측 하단 진행률을 확인하세요.");
        Lightmapping.BakeAsync();
    }

    // =================================================================
    [MenuItem("Tools/Class11/0. Clear Test Scene", false, 20)]
    public static void Clear()
    {
        GameObject old = GameObject.Find(RootName);
        if (old != null) Object.DestroyImmediate(old);
    }

    // =================================================================
    //  배치 모드용 : 1119 씬을 열어서 만들고, 굽고, 저장한다.
    //  Unity.exe -batchmode -projectPath <프로젝트> -executeMethod IndirectLightingTestSetup.BatchBuildAndBake -quit
    // =================================================================
    public static void BatchBuildAndBake()
    {
        EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        BuildScene();

        bool ok = Lightmapping.Bake();
        Debug.Log("[Class11] Bake result : " + ok);

        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene());
        AssetDatabase.SaveAssets();

        CapturePreview("Temp/1119_preview.png");
    }

    // =================================================================
    //  내부 헬퍼
    // =================================================================
    private static void EnsureFolders()
    {
        if (!AssetDatabase.IsValidFolder(FolderPath))
            AssetDatabase.CreateFolder("Assets/1119", "Class11_Lighting");
        if (!AssetDatabase.IsValidFolder(MatPath))
            AssetDatabase.CreateFolder(FolderPath, "Materials");
    }

    private static Material MakeMaterial(string name, Color color)
    {
        Shader shader = Shader.Find("Universal Render Pipeline/Lit");
        if (shader == null) shader = Shader.Find("Standard");

        string path = MatPath + "/" + name + ".mat";
        Material mat = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (mat == null)
        {
            mat = new Material(shader);
            AssetDatabase.CreateAsset(mat, path);
        }
        else
        {
            mat.shader = shader;
        }

        mat.color = color;
        if (mat.HasProperty("_BaseColor"))  mat.SetColor("_BaseColor", color);
        if (mat.HasProperty("_Smoothness")) mat.SetFloat("_Smoothness", 0.3f);
        if (mat.HasProperty("_Metallic"))   mat.SetFloat("_Metallic", 0f);

        // 기본은 emission 없음 (빨간 벽만 따로 켠다)
        mat.DisableKeyword("_EMISSION");
        if (mat.HasProperty("_EmissionColor")) mat.SetColor("_EmissionColor", Color.black);
        mat.globalIlluminationFlags = MaterialGlobalIlluminationFlags.EmissiveIsBlack;

        EditorUtility.SetDirty(mat);
        return mat;
    }

    // p.68 : Red material -> Emission 체크 -> red color, intensity 2.0
    //        Global Illumination = Baked 여야 라이트맵에 빛이 구워진다
    private static void SetBakedEmission(Material mat, Color color, float intensity)
    {
        Color hdr = color * Mathf.Pow(2f, intensity);
        mat.EnableKeyword("_EMISSION");
        mat.SetColor("_EmissionColor", hdr);
        mat.globalIlluminationFlags = MaterialGlobalIlluminationFlags.BakedEmissive;
        EditorUtility.SetDirty(mat);
    }

    private static GameObject MakePrimitive(PrimitiveType type, string name,
        Vector3 pos, Vector3 scale, Material mat, Transform parent)
    {
        GameObject go = GameObject.CreatePrimitive(type);
        go.name = name;
        go.transform.SetParent(parent, false);
        go.transform.position      = pos;
        go.transform.localRotation = Quaternion.identity;
        go.transform.localScale    = scale;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        return go;
    }

    // Static 체크. 이게 빠지면 Generate Lighting 해도 아무 변화 없음 (p.68)
    private static void MarkStatic(GameObject go)
    {
        GameObjectUtility.SetStaticEditorFlags(go,
            StaticEditorFlags.ContributeGI |
            StaticEditorFlags.BatchingStatic |
            StaticEditorFlags.OccluderStatic |
            StaticEditorFlags.OccludeeStatic |
            StaticEditorFlags.ReflectionProbeStatic);

        MeshRenderer mr = go.GetComponent<MeshRenderer>();
        if (mr != null) mr.receiveGI = ReceiveGI.Lightmaps;
    }

    private static void DisableAllLights()
    {
        Light[] lights = Object.FindObjectsByType<Light>(FindObjectsInactive.Include);
        foreach (Light l in lights)
            l.gameObject.SetActive(false);
    }

    private static void SetupCamera()
    {
        Camera cam = Camera.main;
        if (cam == null)
        {
            Camera[] cams = Object.FindObjectsByType<Camera>();
            if (cams.Length > 0) cam = cams[0];
        }
        if (cam == null) return;

        cam.transform.position = new Vector3(2.5f, 3.5f, -7f);
        cam.transform.LookAt(new Vector3(8f, 1f, 0f));
    }

    private static LightingSettings GetOrCreateLightingSettings()
    {
        LightingSettings ls = null;
        try { ls = Lightmapping.lightingSettings; }
        catch { ls = null; }
        if (ls != null) return ls;

        EnsureFolders();
        string path = FolderPath + "/Class11_LightingSettings.lighting";
        ls = AssetDatabase.LoadAssetAtPath<LightingSettings>(path);
        if (ls == null)
        {
            ls = new LightingSettings();
            ls.name = "Class11_LightingSettings";
            AssetDatabase.CreateAsset(ls, path);
        }
        Lightmapping.lightingSettings = ls;
        return ls;
    }

    // p.68 : Lighting setting 에 new 로 생성 -> Baked GI
    private static void SetupLightingSettings()
    {
        LightingSettings ls = GetOrCreateLightingSettings();

        ls.bakedGI    = true;
        ls.realtimeGI = false;

        ls.lightmapper        = LightingSettings.Lightmapper.ProgressiveCPU;
        ls.lightmapResolution = 10f;
        ls.indirectResolution = 2f;
        ls.lightmapPadding    = 2;
        ls.lightmapMaxSize    = 1024;
        ls.ao                 = false;

        ls.indirectScale = 1f;
        ls.albedoBoost   = 1f;

        ls.maxBounces               = 2;
        ls.directSampleCount        = 32;
        ls.indirectSampleCount      = 256;
        ls.environmentSampleCount   = 256;

        EditorUtility.SetDirty(ls);
        AssetDatabase.SaveAssets();
    }

    // 배치 모드에서 결과 확인용 스크린샷
    private static void CapturePreview(string path)
    {
        Camera cam = Camera.main;
        if (cam == null) return;
        try
        {
            RenderTexture rt = new RenderTexture(960, 540, 24);
            cam.targetTexture = rt;
            cam.Render();
            RenderTexture.active = rt;
            Texture2D tex = new Texture2D(960, 540, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 960, 540), 0, 0);
            tex.Apply();
            System.IO.File.WriteAllBytes(path, tex.EncodeToPNG());
            cam.targetTexture = null;
            RenderTexture.active = null;
            Object.DestroyImmediate(rt);
            Debug.Log("[Class11] Preview saved : " + path);
        }
        catch (System.Exception e)
        {
            Debug.LogWarning("[Class11] Preview failed : " + e.Message);
        }
    }
}
#endif
