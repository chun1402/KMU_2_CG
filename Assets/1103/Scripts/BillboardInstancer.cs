// =====================================================================
//  Class 9 - GPU Instancing (슬라이드 p.29 ~ p.39)
//  Advanced Computer Graphics / Mankyu Sung
//
//  p.30  수만 개를 for 문으로 하나씩 그리면 CPU <-> GPU 전송이 너무 많다.
//  p.31  draw 함수 한 번으로 n개를 그리고, instance 마다 다른 변환 행렬만
//        따로 보낸다.
//  p.33  ~ p.35  InstanceData 리스트를 만들고 Graphics.RenderMeshInstanced 로
//        한 번에 그린다.
//
//  사용법
//    1) 빈 GameObject 에 이 스크립트를 붙인다.
//    2) Mesh 에 Quad 를, Material 에 spriteMaterial(Unlit/spriteShader)을 넣는다.
//       Mesh 를 비워 두면 Unity 내장 Quad 를 자동으로 가져온다.
//    3) Material 의 Enable GPU Instancing 을 켠다. (p.36)
//    4) 씬에 원본 Quad 오브젝트가 남아 있다면 꺼 둔다.
//       RenderMeshInstanced 는 GameObject 의 Transform 을 전혀 쓰지 않는다.
//
//  Unity 2021.2 이상 필요 (RenderParams / RenderMeshInstanced API)
// =====================================================================
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class BillboardInstancer : MonoBehaviour
{
    // p.30 과 p.31 을 직접 비교해 보기 위한 모드
    public enum DrawMode
    {
        Instanced,   // p.31 : draw 한 번으로 n개          -> 드로우콜 1
        NaiveLoop    // p.30 : for 문으로 하나씩            -> 드로우콜 n
    }

    [Header("Instanced Mesh")]
    public Mesh mesh;               // Quad
    public Material material;       // Unlit/spriteShader, GPU Instancing 체크

    [Header("Instances")]
    public int     instanceCount = 1000;
    public float   spawnRadius   = 10f;
    public Vector3 instanceScale = new Vector3(3f, 3f, 3f);

    [Header("Placement")]
    // 꽃과 잔디는 바닥에 깔려야 하므로 Y를 0으로 눌러 평평한 원판에 뿌린다.
    // 끄면 슬라이드 그대로 구(sphere) 안에 3차원으로 흩뿌린다.
    public bool flattenToGround = true;

    // 빌보드 셰이더는 Transform 의 회전을 B 행렬로 덮어쓰므로 회전은 의미가 없고,
    // 오히려 회전이 섞이면 셰이더의 scale 추출(_m00_m11_m22)이 깨진다.
    // 빌보드가 아닌 일반 메쉬를 뿌릴 때만 켤 것. (README 참고)
    public bool randomRotation = false;

    [Header("Draw")]
    public DrawMode drawMode = DrawMode.Instanced;

    // p.34 : instance 마다 다른 변환 행렬
    public struct InstanceData
    {
        public Matrix4x4 matrix;
    }

    private readonly List<InstanceData> instances = new List<InstanceData>();
    private Matrix4x4[] matrices;
    private RenderParams rp;
    private bool ready;

    // RenderMeshInstanced 는 한 번 호출에 최대 1023개까지만 그린다.
    // 슬라이드의 1000개는 이 한계 바로 아래 값이다.
    private const int MaxPerBatch = 1023;

    // -----------------------------------------------------------------
    void Start()
    {
        if (mesh == null) mesh = GetBuiltinQuadMesh();

        if (mesh == null || material == null)
        {
            Debug.LogError("[BillboardInstancer] Mesh 또는 Material 이 비어 있습니다.", this);
            enabled = false;
            return;
        }

        BuildInstances();
        BuildRenderParams();
        ready = true;
    }

    // p.34 : 1000개의 instance 에 대해 random 위치, 방향 설정
    private void BuildInstances()
    {
        instances.Clear();

        for (int i = 0; i < instanceCount; i++)
        {
            InstanceData instance = new InstanceData();

            Vector3    position = GetRandomPositionInSphere(spawnRadius);
            Vector3    scale    = instanceScale;
            Quaternion rotation = randomRotation ? Random.rotation : Quaternion.identity;

            if (flattenToGround)
            {
                // 바닥에 세운다. Quad 의 pivot 이 중심이므로 높이의 절반만큼 올려야
                // 밑동이 땅에 닿는다.
                position.y = scale.y * 0.5f;
            }

            instance.matrix = Matrix4x4.TRS(transform.position + position, rotation, scale);
            instances.Add(instance);
        }

        matrices = GetMatrices();
    }

    private Vector3 GetRandomPositionInSphere(float radius)
    {
        return Random.insideUnitSphere * radius;
    }

    // p.35
    private Matrix4x4[] GetMatrices()
    {
        Matrix4x4[] result = new Matrix4x4[instances.Count];
        for (int i = 0; i < instances.Count; i++)
            result[i] = instances[i].matrix;
        return result;
    }

    private void BuildRenderParams()
    {
        rp = new RenderParams(material);

        // 반드시 설정할 것. worldBounds 가 비어 있으면 컬링 단계에서
        // 전부 걸러져 화면에 아무것도 안 나온다.
        float extent = spawnRadius * 2f + instanceScale.magnitude * 2f;
        rp.worldBounds = new Bounds(transform.position, Vector3.one * extent);

        rp.shadowCastingMode = ShadowCastingMode.Off;
        rp.receiveShadows    = false;
    }

    // -----------------------------------------------------------------
    void Update()
    {
        if (!ready) return;

        if (drawMode == DrawMode.Instanced)
            DrawInstanced();
        else
            DrawNaive();
    }

    // p.31, p.35 : 한 개의 draw 함수로 n개를 동시에 그린다
    private void DrawInstanced()
    {
        for (int start = 0; start < matrices.Length; start += MaxPerBatch)
        {
            int count = Mathf.Min(MaxPerBatch, matrices.Length - start);
            Graphics.RenderMeshInstanced(rp, mesh, 0, matrices, count, start);
        }
    }

    // p.30 : 비교용. 하나씩 그린다. Frame Debugger 로 드로우콜 수를 비교할 것
    private void DrawNaive()
    {
        for (int i = 0; i < matrices.Length; i++)
            Graphics.RenderMesh(rp, mesh, 0, matrices[i]);
    }

    // -----------------------------------------------------------------
    // Mesh 를 비워 뒀을 때 Unity 내장 Quad 메쉬를 꺼내 온다.
    private static Mesh GetBuiltinQuadMesh()
    {
        GameObject temp = GameObject.CreatePrimitive(PrimitiveType.Quad);
        Mesh quad = temp.GetComponent<MeshFilter>().sharedMesh;

        if (Application.isPlaying) Destroy(temp);
        else                       DestroyImmediate(temp);

        return quad;
    }

    // 스폰 영역을 씬 뷰에 표시
    private void OnDrawGizmosSelected()
    {
        Gizmos.color = new Color(0.3f, 0.8f, 1f, 0.35f);
        Gizmos.DrawWireSphere(transform.position, spawnRadius);
    }
}
