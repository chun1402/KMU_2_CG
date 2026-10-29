// =====================================================================
//  Class 9 - Transparency 실험용 셰이더
//  Advanced Computer Graphics / Mankyu Sung
//
//  MyShader_Transparent 와 결과는 같지만, 슬라이드가 "이렇게 해야 한다"고
//  말한 세 가지를 인스펙터에서 켜고 끌 수 있게 노출했다.
//  왜 그렇게 해야 하는지는 틀린 설정을 직접 보는 쪽이 빠르다.
//
//    Src Blend / Dst Blend  : Blend 인자        (p.4)
//    ZWrite                 : 깊이 기록 여부     (p.11)
//    Cull                   : 어느 면을 버릴지   (p.9 정렬 문제 관찰용)
//
//  기본값은 슬라이드와 동일하다.
//    Src = SrcAlpha(5), Dst = OneMinusSrcAlpha(10), ZWrite = Off(0), Cull = Back(2)
// =====================================================================
Shader "Unlit/myShader_TransparentLab"
{
    Properties
    {
        _BaseColor ("Base Color", Color)  = (1, 1, 1, 1)
        _MainTex   ("Texture", 2D)        = "white" {}
        _Alpha     ("Alpha", Range(0, 1)) = 0.5

        [Header(Alpha Source)]
        // 텍스처의 알파 채널까지 곱해 쓸지 (알파를 가진 PNG용)
        [Toggle(_USE_TEX_ALPHA)] _UseTexAlpha ("Multiply texture alpha", Float) = 0

        [Header(Blend State)]
        // SrcAlpha = 5, OneMinusSrcAlpha = 10, One = 1, Zero = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 10

        [Header(Depth and Culling)]
        [Enum(Off, 0, On, 1)]                   _ZWrite ("ZWrite", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)]  _Cull   ("Cull", Float)   = 2
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Transparent"
            "Queue"          = "Transparent"
        }

        // 머티리얼 프로퍼티로 렌더 상태를 결정한다
        ZWrite [_ZWrite]
        Cull   [_Cull]
        Blend  [_SrcBlend] [_DstBlend]

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature_local _USE_TEX_ALPHA

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);  SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _BaseColor;
                float  _Alpha;
                float  _UseTexAlpha;    // 인스펙터 토글용 (SRP Batcher 호환)
                float  _SrcBlend;
                float  _DstBlend;
                float  _ZWrite;
                float  _Cull;
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
                half4 tex        = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                half4 finalColor = tex * _BaseColor;

            #if defined(_USE_TEX_ALPHA)
                finalColor.w = _Alpha * tex.a * _BaseColor.a;
            #else
                finalColor.w = _Alpha;
            #endif

                return finalColor;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
