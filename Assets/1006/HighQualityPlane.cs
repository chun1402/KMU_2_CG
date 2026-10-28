using UnityEngine;
using UnityEngine.Rendering;

[ExecuteAlways]
[RequireComponent(typeof(MeshFilter))]
[RequireComponent(typeof(MeshRenderer))]
public class HighQualityPlane : MonoBehaviour
{
    [Header("Plane Size")]
    [Min(0.01f)]
    public float width = 10.0f;

    [Min(0.01f)]
    public float depth = 10.0f;

    [Header("Resolution")]
    [Range(1, 500)]
    public int xSegments = 100;

    [Range(1, 500)]
    public int zSegments = 100;

    private Mesh mesh;

    void OnEnable()
    {
        GenerateMesh();
    }

    void OnValidate()
    {
        GenerateMesh();
    }

    public void GenerateMesh()
    {
        MeshFilter meshFilter = GetComponent<MeshFilter>();

        if (mesh != null)
        {
            if (Application.isPlaying)
                Destroy(mesh);
            else
                DestroyImmediate(mesh);
        }

        mesh = new Mesh();
        mesh.name = "High Quality Plane";

        int vertexCountX = xSegments + 1;
        int vertexCountZ = zSegments + 1;

        int vertexCount = vertexCountX * vertexCountZ;

        if (vertexCount > 65535)
        {
            mesh.indexFormat = IndexFormat.UInt32;
        }

        Vector3[] vertices = new Vector3[vertexCount];
        Vector3[] normals = new Vector3[vertexCount];
        Vector2[] uvs = new Vector2[vertexCount];

        int[] triangles = new int[xSegments * zSegments * 6];

        int vertexIndex = 0;

        for (int z = 0; z <= zSegments; z++)
        {
            float vz = (float)z / zSegments;

            for (int x = 0; x <= xSegments; x++)
            {
                float vx = (float)x / xSegments;

                float posX = (vx - 0.5f) * width;
                float posZ = (vz - 0.5f) * depth;

                vertices[vertexIndex] =
                    new Vector3(posX, 0.0f, posZ);

                normals[vertexIndex] = Vector3.up;
                uvs[vertexIndex] = new Vector2(vx, vz);

                vertexIndex++;
            }
        }

        int triangleIndex = 0;

        for (int z = 0; z < zSegments; z++)
        {
            for (int x = 0; x < xSegments; x++)
            {
                int i0 = z * vertexCountX + x;
                int i1 = i0 + 1;
                int i2 = i0 + vertexCountX;
                int i3 = i2 + 1;

                triangles[triangleIndex++] = i0;
                triangles[triangleIndex++] = i2;
                triangles[triangleIndex++] = i1;

                triangles[triangleIndex++] = i1;
                triangles[triangleIndex++] = i2;
                triangles[triangleIndex++] = i3;
            }
        }

        mesh.vertices = vertices;
        mesh.normals = normals;
        mesh.uv = uvs;
        mesh.triangles = triangles;

        mesh.RecalculateBounds();

        meshFilter.sharedMesh = mesh;
    }
}