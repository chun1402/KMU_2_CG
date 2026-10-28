using UnityEngine;
[ExecuteAlways]
public class AssignTriangleColors : MonoBehaviour
{
    private void OnEnable()
    {
        ApplyColors();
    }
    [ContextMenu("Apply Triangle Colors")]
    private void ApplyColors()
    {
        MeshFilter[] meshFilters = GetComponentsInChildren<MeshFilter>(true);
        bool applied = false;
        foreach (MeshFilter meshFilter in meshFilters)
        {
            Mesh mesh = Application.isPlaying
            ? meshFilter.mesh
            : meshFilter.sharedMesh;
            // Ignore the empty MeshFilter that can exist on the imported model root.
            if (mesh == null || mesh.vertexCount < 3)
                continue;
            Color[] colors = new Color[mesh.vertexCount];
            for (int i = 0; i < colors.Length; i++)
                colors[i] = Color.white;
            colors[0] = Color.red;
            colors[1] = Color.green;
            colors[2] = Color.blue;
            mesh.colors = colors;
            applied = true;
        }
        if (!applied)
        {
            Debug.LogError(
            "AssignTriangleColors could not find a child mesh with at least three vertices.",
            this);
        }
    }
}
