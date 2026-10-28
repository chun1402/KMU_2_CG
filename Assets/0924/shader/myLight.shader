Shader "Unlit/myLight"
{
    Properties
    {
        // 맨 뒤의 (1,1,0,1)이 순서대로 Red, Green, Blue, Alpha(투명도) 값
        _BaseColor ("Base Color", Color) = (1,1,0,1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // URP 배처(Batcher)를 위한 CBUFFER 선언
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
            CBUFFER_END

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct Interpolators
            {
                float4 positionCS : SV_POSITION; // Clip Space Position
                float3 normal : TEXCOORD0;
                float2 uv : TEXCOORD1;
            };

            Interpolators vert (appdata input)
            {
                Interpolators output;
                
                // 로컬 좌표를 클립 좌표로 변환
                output.positionCS = TransformObjectToHClip(input.vertex.xyz);
                
                // 노멀을 월드 공간으로 변환
                output.normal = TransformObjectToWorldNormal(input.normal);
                output.uv = input.uv;
                
                return output;
            }

            float4 frag (Interpolators i) : SV_TARGET
            {
                Light mainLight = GetMainLight();
                
                float3 L = normalize(mainLight.direction);
                float3 N = normalize(i.normal);
                float3 id = mainLight.color;
                float3 kd = _BaseColor.rgb;
                
                float dotLN = saturate(dot(N, L));
                
                return float4(id * kd * dotLN, 1);
            }
            ENDHLSL
        }
    }
}