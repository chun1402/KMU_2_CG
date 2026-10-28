using UnityEngine;
using UnityEngine.UIElements;

public class quadScript : MonoBehaviour
{
    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {
        Debug.Log("Start called!");
        Mesh mesh = GetComponent<MeshFilter>().mesh;
        Vector3 localPos = mesh.vertices[0];
        Debug.Log("Vertex Count = " + mesh.vertexCount);
        Debug.Log("Local Position = " + localPos);
        Vector3 worldPos = transform.TransformPoint(localPos);
        Debug.Log("World Position = " + worldPos);
        Matrix4x4 M = transform.localToWorldMatrix;
        Vector4 world =
        M * new Vector4(
        localPos.x,
        localPos.y,
        localPos.z,
        1);
        Debug.Log("World Position = " + world);
        Camera cam = Camera.main;
        Vector4 viewPos =
        cam.worldToCameraMatrix * world;
        Debug.Log("Camera Position = " + viewPos);

        Vector4 clipPos = cam.projectionMatrix * viewPos;
        Debug.Log("ClipPosition =" +clipPos);
        Vector3 ndc = new Vector3(
        clipPos.x / clipPos.w,
        clipPos.y / clipPos.w,
        clipPos.z / clipPos.w);
        Debug.Log("NDC Position = " + ndc);
        float screenX = (ndc.x + 1.0f) * 0.5f * Screen.width;
        float screenY = (ndc.y + 1.0f) * 0.5f * Screen.height;
        Vector3 unityScreen = cam.WorldToScreenPoint(worldPos);
    }

    // Update is called once per frame
    void Update()
    {
        
    }
}
