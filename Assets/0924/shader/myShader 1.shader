Shader "Unlit/myShader"
{
    SubShader
    {
        // URP에서 사용하려면 RenderPipeline 태그를 UniversalPipeline으로 지정
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP 기본 함수 (TransformObjectToHClip 등) 제공
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Mesh 데이터 (app -> vertex shader)
            struct appdata
            {
                float4 vertex : POSITION;   // local coordinate
                float2 uv     : TEXCOORD0;  // uv coordinates
                float3 normal : NORMAL;     // normal
            };

            // vertex shader -> fragment shader (rasterization 시 보간됨)
            struct Interpolators
            {
                float4 position : SV_POSITION; // clip coordinate (gl_Position 역할)
                float3 normal   : TEXCOORD0;   // 이걸 color로 이용
            };

            Interpolators vert (appdata input)
            {
                Interpolators i;
                // 원래 normal은 [-1,1] -> 색상으로 쓰기 위해 [0,1]로 변경
                i.normal = (input.normal + 1.0) * 0.5;
                // local -> clip (함수가 float3를 받으므로 xyz만 전달)
                i.position = TransformObjectToHClip(input.vertex.xyz);
                return i;
            }

            // SV_TARGET == GLSL의 out vec4 FragColor
            float4 frag (Interpolators i) : SV_TARGET
            {
               
                return float4(i.normal, 1); // normal을 색상으로 (float3 -> float4), 변환된 X, Y, Z 방향 값을 각각 빨강(R), 초록(G), 파랑(B) 색상 데이터로 그대로 사용
            }
            ENDHLSL
        } // Pass
    } // SubShader
} // Shader
