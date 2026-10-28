Shader "Unlit/triangleShader"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct AppData
            {
                float4 vertex : POSITION;
                float4 color : COLOR;
            };

            struct Interpolators
            {
                float4 position : SV_POSITION;
                float4 color : COLOR;
            };

            Interpolators vert(AppData input)
            {
                Interpolators output;

                output.position = TransformObjectToHClip(input.vertex.xyz);
                output.color = input.color;

                return output;
            }

            float4 frag(Interpolators input) : SV_Target
            {
                return input.color;
            }

            ENDHLSL
        }
    }
}