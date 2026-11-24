// =====================================================================
//  Class 11 - 라이팅 테스트 보정 (슬라이드 p.64 ~ p.71 기준)
//  Advanced Computer Graphics / Mankyu Sung
//
//  이미 만들어 둔 1119 씬을 PDF 와 비교해서 다른 부분만 고친다.
//  상단 메뉴 Tools > Class11 > 3. Fix Scene To PDF (p.64~71)
//  (스크립트가 처음 컴파일될 때 한 번 자동으로 실행된다)
//
//  고치는 것
//    1. p.71 6.밤 씬 : "Emission 되는 red wall 의 Global Illumination 을 realtime 으로"
//       -> 벽에 실제로 붙어 있는 M_Wall_Red 는 아직 Baked 였다.
//          (Assets/1119/Red.mat 만 Realtime 으로 바뀌어 있었는데, 이건 벽에 안 쓰이는 머티리얼)
//          Baked GI 를 꺼 놓았으므로 Baked emission 은 아무 효과가 없음 -> Realtime 으로 변경
//    2. p.71 "카메라를 모든 씬이 잘 보이도록, main camera -> align with view"
//       -> Main Camera 가 벽 뒤쪽(-z, 그림자 면)을 보고 있어서 캡슐이 벽에 가려 Game 뷰에 안 보였다.
//          Directional light 이 비추는 면(+z) 쪽, 캡슐/라이트 프로브가 있는 쪽에서 전체가 보이게 이동
//    3. p.68 "벽 가까이 Positional light 추가 : 벽의 색깔이 밝아짐"
//       p.70 "캡슐을 point 라이트 부분으로 이동시켜도 shadow 는 괜찮음"
//       -> Point Light 가 벽 반대편(-z)에 있어서 캡슐 쪽 벽면을 밝히지 못하고 캡슐이 다가갈 수도 없었다.
//          캡슐과 같은 쪽(+z) 으로 옮긴다 (x, y 는 그대로)
//    4. p.71 6. Realtime GI on / Baked GI off, p.70 Shadowmask, Point/Directional = Mixed + Soft Shadow
//       -> 이미 맞게 되어 있으면 그대로 두고 확인만
//    5. Generate Lighting
// =====================================================================
#if UNITY_EDITOR
using System.Text;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;
using UnityEditor.SceneManagement;

[InitializeOnLoad]
public static class Class11FixToPdf
{
    private const string ScenePath   = "Assets/Scenes/1119.unity";
    private const string RedWallMat  = "Assets/1119/Class11_Lighting/Materials/M_Wall_Red.mat";
    private const string AutoRunKey  = "KMU_2_CG.Class11FixToPdf.autorun.v1";
    private const string ReportPath  = "Temp/1119_fix_report.txt";
    private const string PreviewPath = "Temp/1119_fix_preview.png";

    static Class11FixToPdf()
    {
        if (Application.isBatchMode || EditorPrefs.GetBool(AutoRunKey, false)) return;
        EditorApplication.delayCall += () =>
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode || EditorApplication.isCompiling) return;
            EditorPrefs.SetBool(AutoRunKey, true);
            Fix();
        };
    }

    [MenuItem("Tools/Class11/3. Fix Scene To PDF (p.64~71)", false, 3)]
    public static void Fix()
    {
        var log = new StringBuilder();

        // ---- 1119 씬이 열려 있는지 ----
        var scene = EditorSceneManager.GetActiveScene();
        if (scene.path != ScenePath)
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
            {
                Debug.LogWarning("[Class11 Fix] 취소됨. 1119 씬을 연 뒤 Tools > Class11 > 3 을 다시 실행하세요.");
                return;
            }
            scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        }

        // ---- 1. Red wall emission -> Realtime GI (p.71) ----
        Material red = AssetDatabase.LoadAssetAtPath<Material>(RedWallMat);
        if (red != null)
        {
            var before = red.globalIlluminationFlags;
            red.EnableKeyword("_EMISSION");
            red.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
            EditorUtility.SetDirty(red);
            log.AppendLine($"[1] M_Wall_Red GI : {before} -> {red.globalIlluminationFlags}, emission = {red.GetColor("_EmissionColor")}");
        }
        else log.AppendLine("[1] M_Wall_Red.mat 을 찾지 못함");

        // ---- 오브젝트 찾기 ----
        GameObject capsule = FindInScene("Capsule");
        Light pointLight   = FindLight(LightType.Point);
        Light dirLight     = FindLight(LightType.Directional);
        Camera cam         = Camera.main;

        // ---- 3. Point Light 를 캡슐 쪽(+z) 벽 가까이 (p.68, p.70) ----
        if (pointLight != null)
        {
            Vector3 p = pointLight.transform.position;
            if (p.z < 0f)
            {
                Vector3 np = new Vector3(p.x, p.y, Mathf.Abs(p.z));
                Undo.RecordObject(pointLight.transform, "Move Point Light");
                pointLight.transform.position = np;
                log.AppendLine($"[3] Point Light 위치 {p} -> {np} (캡슐/조명받는 벽면 쪽)");
            }
            else log.AppendLine($"[3] Point Light 위치 OK {p}");

            Undo.RecordObject(pointLight, "Point Light settings");
            pointLight.lightmapBakeType = LightmapBakeType.Mixed;   // p.70 Light mode = mixed
            pointLight.shadows          = LightShadows.Soft;        // p.70 soft shadow
            pointLight.enabled          = true;
            pointLight.gameObject.SetActive(true);
        }

        // ---- Directional : Mixed + soft shadow (p.70) ----
        if (dirLight != null)
        {
            Undo.RecordObject(dirLight, "Directional settings");
            dirLight.lightmapBakeType = LightmapBakeType.Mixed;
            dirLight.shadows          = LightShadows.Soft;
            log.AppendLine($"[4] Directional : mode={dirLight.lightmapBakeType}, shadows={dirLight.shadows}, intensity={dirLight.intensity}, forward={dirLight.transform.forward}");
        }

        // ---- Capsule : non static (p.70) ----
        if (capsule != null)
        {
            GameObjectUtility.SetStaticEditorFlags(capsule, 0);
            var mr = capsule.GetComponent<MeshRenderer>();
            if (mr != null) mr.receiveGI = ReceiveGI.LightProbes;   // p.71 Light Probe 로부터 간접광
            log.AppendLine($"[4] Capsule non-static, pos={capsule.transform.position}");
        }

        // ---- 2. Main Camera : 씬 전체 + 캡슐이 보이도록 (p.71 align with view) ----
        if (cam != null)
        {
            Undo.RecordObject(cam.transform, "Move Main Camera");
            Vector3 before = cam.transform.position;
            cam.transform.position = new Vector3(14f, 7.5f, 16f);
            cam.transform.LookAt(new Vector3(3f, 1f, 0f));
            log.AppendLine($"[2] Main Camera {before} -> {cam.transform.position}, rot={cam.transform.eulerAngles}");

            // Scene 뷰도 같은 시점으로 (align with view 의 반대 방향 : align view to selected)
            SceneView sv = SceneView.lastActiveSceneView;
            if (sv != null) { sv.AlignViewToObject(cam.transform); sv.Repaint(); }
        }

        // ---- 4. Lighting settings 확인 (p.70 Shadowmask, p.71 Realtime GI on / Baked GI off) ----
        LightingSettings ls = null;
        try { ls = Lightmapping.lightingSettings; } catch { ls = null; }
        if (ls != null)
        {
            ls.realtimeGI     = true;
            ls.bakedGI        = false;
            ls.mixedBakeMode  = MixedLightingMode.Shadowmask;
            EditorUtility.SetDirty(ls);
            log.AppendLine($"[4] LightingSettings '{ls.name}' realtimeGI={ls.realtimeGI} bakedGI={ls.bakedGI} mixed={ls.mixedBakeMode}");
        }
        else log.AppendLine("[4] LightingSettings 없음");

        log.AppendLine($"[4] Light probe groups = {Object.FindObjectsByType<LightProbeGroup>().Length}");

        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);
        AssetDatabase.SaveAssets();

        // ---- 5. Generate Lighting ----
        if (!Lightmapping.isRunning)
        {
            Lightmapping.bakeCompleted -= OnBakeCompleted;
            Lightmapping.bakeCompleted += OnBakeCompleted;
            bool started = Lightmapping.BakeAsync();
            log.AppendLine($"[5] Generate Lighting 시작 : {started}");
        }

        string report = log.ToString();
        System.IO.File.WriteAllText(ReportPath, report);
        Debug.Log("[Class11 Fix]\n" + report);
    }

    private static void OnBakeCompleted()
    {
        Lightmapping.bakeCompleted -= OnBakeCompleted;
        var scene = EditorSceneManager.GetActiveScene();
        EditorSceneManager.SaveScene(scene);
        System.IO.File.AppendAllText(ReportPath, "[5] Generate Lighting 완료\n");
        Debug.Log("[Class11 Fix] Generate Lighting 완료 + 씬 저장");
        CapturePreview();
    }

    private static GameObject FindInScene(string name)
    {
        foreach (var t in Object.FindObjectsByType<Transform>(FindObjectsInactive.Include))
            if (t.name == name) return t.gameObject;
        return null;
    }

    private static Light FindLight(LightType type)
    {
        foreach (var l in Object.FindObjectsByType<Light>(FindObjectsInactive.Include))
            if (l.type == type) return l;
        return null;
    }

    private static void CapturePreview()
    {
        Camera cam = Camera.main;
        if (cam == null) return;
        try
        {
            var rt = new RenderTexture(1280, 720, 24);
            var old = cam.targetTexture;
            cam.targetTexture = rt;
            cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(1280, 720, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0);
            tex.Apply();
            System.IO.File.WriteAllBytes(PreviewPath, tex.EncodeToPNG());
            cam.targetTexture = old;
            RenderTexture.active = null;
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(tex);
        }
        catch (System.Exception e)
        {
            Debug.LogWarning("[Class11 Fix] Preview failed : " + e.Message);
        }
    }
}
#endif
