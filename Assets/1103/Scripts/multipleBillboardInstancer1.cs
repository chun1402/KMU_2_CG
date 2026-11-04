// =====================================================================
//  Class 9 - GPU Instancing (슬라이드 p.29 ~ p.49)
//  Advanced Computer Graphics / Mankyu Sung
//
//  p.30  수만 개를 for 문으로 하나씩 그리면 CPU <-> GPU 전송이 너무 많다.
//  p.31  draw 함수 한 번으로 n개를 그리고, instance 마다 다른 변환 행렬만 보낸다.
//  p.40  Graphics.RenderMeshInstanced 로 한 번에 그린다.
//  p.46 ~ p.48  material 을 3개 이상 쓰는 꽃밭.
//        material 마다 RenderParams 를 따로 만들고, 3000개의 instance 를
//        1000개씩 잘라 material 별로 한 번씩 그린다.
//
//  사용법 (p.46)
//    1) sprite 가 서로 다른 material 을 3개 만든다. 전부 GPU Instancing 체크.
//    2) 기존 Quad 는 material 이 물려 있으므로 지우고, material 없는 Quad 를
//       새로 만든다. (Mesh 칸을 비워 두면 내장 Quad 를 자동으로 가져온다)
//    3) Create | Create Empty 로 빈 오브젝트를 만들고 이 스크립트를 붙인다.
//    4) Mesh 에 Quad, Materials 에 material 3개를 지정한다.
//
//  Unity 2021.2 이상 필요 (RenderParams / RenderMeshInstanced API)
// =====================================================================
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class multipleBillboardInstancer : MonoBehaviour
{
    // p.30 과 p.31 을 직접 비교해 보기 위한 모드
    public enum DrawMode
    {
        Instanced,   // p.31 : material 당 draw 한 번     -> 드로우콜 = material 수
        NaiveLoop    // p.30 : for 문으로 하나씩           -> 드로우콜 = instance 수
    }

    [Header("Instanced Mesh")]
    public Mesh mesh;                                   // Quad (비우면 내장 Quad)
    public Material[] materials = new Material[0];      // p.46 : 3개 이상

    [Header("Instances")]
    public int     instancesPerMaterial = 1000;         // p.46 : material 당 1000개
    public float   spawnRadius          = 10f;
    public Vector3 instanceScale        = new Vector3(3f, 3f, 3f);

    [Header("Placement")]
    // 꽃과 잔디는 바닥에 깔려야 하므로 Y를 눌러 평평한 원판에 뿌린다. (p.49)
    // 끄면 슬라이드 코드 그대로 구(sphere) 안에 3차원으로 흩뿌린다.
    public bool flattenToGround = true;

    // 빌보드 셰이더는 Transform 의 회전을 B 행렬로 덮어쓰므로 회전은 의미가 없고,
    // 오히려 회전이 섞이면 셰이더의 scale 추출(_m00_m11_m22)이 깨진다.
    public bool randomRotation = false;

    [Header("Shadows")]                                 // p.48
    public ShadowCastingMode shadowCastingMode = ShadowCastingMode.On;
    public bool receiveShadows = true;

    [Header("Draw")]
    public DrawMode drawMode = DrawMode.Instanced;

    // p.34 : instance 마다 다른 변환 행렬
    public struct InstanceData
    {
        public Matrix4x4 matrix;
    }

    private readonly List<InstanceData> instances = new List<InstanceData>();

    // material 별로 잘라 둔 행렬 배열. 슬라이드는 Update 마다 새 배열을
    // 만들지만(p.47), 그러면 매 프레임 GC 가 돈다. 한 번만 만들어 재사용한다.
    private Matrix4x4[][] matricesPerMaterial;

    private RenderParams[] rp;
    private bool ready;

    // RenderMeshInstanced 는 한 번 호출에 최대 1023개까지만 그린다.
    private const int MaxPerBatch = 1023;

    public int TotalInstanceCount
    {
        get { return (materials == null ? 0 : materials.Length) * instancesPerMaterial; }
    }

    // -----------------------------------------------------------------
    void Start()
    {
        if (mesh == null) mesh = GetBuiltinQuadMesh();

        if (mesh == null)
        {
            Debug.LogError("[multipleBillboardInstancer] Mesh 가 비어 있습니다.", this);
            enabled = false;
            return;
        }

        if (materials == null || materials.Length == 0)
        {
            Debug.LogError("[multipleBillboardInstancer] Materials 가 비어 있습니다. " +
                           "sprite 가 서로 다른 material 을 지정하세요. (p.46)", this);
            enabled = false;
            return;
        }

        for (int i = 0; i < materials.Length; i++)
        {
            if (materials[i] == null)
            {
                Debug.LogError($"[multipleBillboardInstancer] Materials[{i}] 가 비어 있습니다.", this);
                enabled = false;
                return;
            }
        }

        // p.48 : 모든 material 의 GPU instancing 을 켠다.
        // 꺼져 있으면 RenderMeshInstanced 가 매 프레임
        // "Material needs to enable instancing..." 예외를 던진다.
        EnsureInstancingEnabled();

        BuildInstances();
        BuildMatrixCache();
        BuildRenderParams();
        ready = true;
    }

    // -----------------------------------------------------------------
    // p.48 : foreach (var material in materials) material.enableInstancing = true;
    private void EnsureInstancingEnabled()
    {
        foreach (var material in materials)
        {
            if (material.enableInstancing) continue;

            material.enableInstancing = true;

            if (material.enableInstancing)
            {
                Debug.LogWarning(
                    $"[multipleBillboardInstancer] '{material.name}' 의 Enable GPU Instancing 이 꺼져 있어 켰습니다. " +
                    "Material 인스펙터에서도 체크해 두세요. (p.41, p.46)", this);
            }
            else
            {
                Debug.LogError(
                    $"[multipleBillboardInstancer] '{material.name}' (shader: {material.shader.name}) 가 instancing 을 " +
                    "지원하지 않습니다. 셰이더에 '#pragma multi_compile_instancing' 이 있는지 확인하세요. (p.42) " +
                    "일단 NaiveLoop 모드로 그립니다.", this);
                drawMode = DrawMode.NaiveLoop;
            }
        }
    }

    // p.48 : 3 x 1000 = 3000개의 random instance
    private void BuildInstances()
    {
        instances.Clear();

        for (int j = 0; j < materials.Length; j++)
        {
            for (int i = 0; i < instancesPerMaterial; i++)
            {
                InstanceData instance = new InstanceData();

                Vector3    position = GetRandomPositionInSphere(spawnRadius);
                Vector3    scale    = instanceScale;
                Quaternion rotation = randomRotation ? Random.rotation : Quaternion.identity;

                if (flattenToGround)
                {
                    // Quad 의 pivot 이 중심이므로 높이의 절반만큼 올려야
                    // 밑동이 땅에 닿는다.
                    position.y = scale.y * 0.5f;
                }

                instance.matrix = Matrix4x4.TRS(transform.position + position, rotation, scale);
                instances.Add(instance);
            }
        }
    }

    private Vector3 GetRandomPositionInSphere(float radius)
    {
        return Random.insideUnitSphere * radius;
    }

    // p.47 의 GetMatrices(int k) 를 미리 한 번만 수행해 캐시한다.
    // k번째 material 은 instances 의 [k*1000, (k+1)*1000) 구간을 맡는다.
    private void BuildMatrixCache()
    {
        matricesPerMaterial = new Matrix4x4[materials.Length][];

        for (int k = 0; k < materials.Length; k++)
        {
            Matrix4x4[] group = new Matrix4x4[instancesPerMaterial];
            for (int i = 0; i < instancesPerMaterial; i++)
                group[i] = instances[i + k * instancesPerMaterial].matrix;

            matricesPerMaterial[k] = group;
        }
    }

    private Matrix4x4[] GetMatrices(int k)
    {
        return matricesPerMaterial[k];
    }

    // p.48 : material 마다 RenderParams 를 따로 만든다
    private void BuildRenderParams()
    {
        rp = new RenderParams[materials.Length];

        float extent = spawnRadius * 2f + instanceScale.magnitude * 2f;
        Bounds bounds = new Bounds(transform.position, Vector3.one * extent);

        for (int i = 0; i < materials.Length; i++)
        {
            rp[i] = new RenderParams(materials[i]);

            // 반드시 설정할 것. worldBounds 가 비어 있으면 컬링 단계에서
            // 전부 걸러져 화면에 아무것도 안 나온다.
            rp[i].worldBounds = bounds;

            rp[i].shadowCastingMode = shadowCastingMode;
            rp[i].receiveShadows    = receiveShadows;
        }
    }

    // -----------------------------------------------------------------
    void Update()
    {
        if (!ready) return;

        if (drawMode == DrawMode.Instanced)
        {
            // p.48 : material 수만큼만 draw 호출
            for (int k = 0; k < materials.Length; k++)
                DrawInstancedGroup(k);
        }
        else
        {
            DrawNaive();
        }
    }

    private void DrawInstancedGroup(int k)
    {
        // 실행 중에 체크가 풀려도 예외가 매 프레임 쏟아지지 않게 막는다
        if (!materials[k].enableInstancing)
        {
            Debug.LogError(
                $"[multipleBillboardInstancer] '{materials[k].name}' 의 Enable GPU Instancing 이 꺼졌습니다. " +
                "NaiveLoop 모드로 전환합니다.", this);
            drawMode = DrawMode.NaiveLoop;
            return;
        }

        Matrix4x4[] group = GetMatrices(k);

        for (int start = 0; start < group.Length; start += MaxPerBatch)
        {
            int count = Mathf.Min(MaxPerBatch, group.Length - start);
            Graphics.RenderMeshInstanced(rp[k], mesh, 0, group, count, start);
        }
    }

    // p.30 : 비교용. 하나씩 그린다. Frame Debugger 로 드로우콜 수를 비교할 것
    private void DrawNaive()
    {
        for (int k = 0; k < materials.Length; k++)
        {
            Matrix4x4[] group = GetMatrices(k);
            for (int i = 0; i < group.Length; i++)
                Graphics.RenderMesh(rp[k], mesh, 0, group[i]);
        }
    }

    // -----------------------------------------------------------------
    // Mesh 를 비워 뒀을 때 Unity 내장 Quad 메쉬를 꺼내 온다. (p.46)
    private static Mesh GetBuiltinQuadMesh()
    {
        GameObject temp = GameObject.CreatePrimitive(PrimitiveType.Quad);
        Mesh quad = temp.GetComponent<MeshFilter>().sharedMesh;

        if (Application.isPlaying) Destroy(temp);
        else                       DestroyImmediate(temp);

        return quad;
    }

    private void OnDrawGizmosSelected()
    {
        Gizmos.color = new Color(0.3f, 0.8f, 1f, 0.35f);
        Gizmos.DrawWireSphere(transform.position, spawnRadius);
    }
}
