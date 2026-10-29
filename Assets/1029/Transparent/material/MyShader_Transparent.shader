// =====================================================================
//  Class 9 - Transparency (슬라이드 p.1 ~ p.13)
//  Advanced Computer Graphics / Mankyu Sung
//
//  투명 오브젝트가 제대로 그려지려면 세 가지가 모두 맞아야 한다.
//
//   1) Queue = "Transparent" (3000)
//      불투명(Geometry, 2000)을 먼저 다 그린 뒤에 그려야, 프레임 버퍼에
//      섞을 "배경 색"이 이미 들어 있다.                        (p.5 ~ p.8)
//
//   2) ZWrite Off
//      깊이를 쓰면 뒤쪽 투명 오브젝트가 깊이 테스트에서 잘려 나가
//      블렌딩 자체가 일어나지 않는다.                              (p.11)
//
//   3) Blend SrcAlpha OneMinusSrcAlpha
//      result = a * src + (1 - a) * dst                          (p.4)
//
//  Queue가 Transparent인 오브젝트끼리는 Unity가 카메라로부터 먼 것부터
//  자동 정렬해 그린다.                                        (p.9, p.10)
// =====================================================================
Shader "Unlit/myShader_Transparent"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _MainTex   ("Texture", 2D)       = "white" {}
        _Alpha     ("Alpha", Range(0, 1)) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Transparent"
            "Queue"          = "Transparent"
        }

        // depth를 쓰지 말 것 : 거리에 따라 가려지는 문제를 사용하지 않는다
        ZWrite Off
        // 프레임 버퍼에 들어 있는 값과 새로운 값을 어떻게 블렌딩하나
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);  SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;     // tiling and offset
                float4 _BaseColor;
                float  _Alpha;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 finalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * _BaseColor;

                finalColor.w = _Alpha;   // alpha값 지정 (p.12)

                return finalColor;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
