// =====================================================================
//  Class 9 - Billboard Rendering (슬라이드 p.14 ~ p.28)
//  Advanced Computer Graphics / Mankyu Sung
//
//  Quad 하나에 sprite 를 입히고, vertex shader 에서 그 quad 가 항상 카메라를
//  바라보도록 돌려 세운다. 나무 / 꽃 / 잔디처럼 복잡한 오브젝트를 아주 싸게
//  "그럴듯하게" 그리는 기법.                                   (p.16, p.17)
//
//  두 축이 핵심이다.
//
//   1) 빌보드 행렬 B (p.22 ~ p.24)
//      View 행렬의 upper-left 3x3 은 카메라의 월드 공간 축(right/up/forward)
//      이다. 이 세 축을 quad 의 축으로 그대로 쓰면 quad 가 카메라 평면과
//      나란해진다. 거기에 quad 중심점 q 를 평행이동으로 얹는다.
//
//   2) Alpha cutout (p.21, p.27)
//      sprite 의 알파가 _Cutoff 보다 작은 픽셀은 clip() 으로 버린다.
//      Queue = AlphaTest(2450) : 불투명 뒤, 투명 앞에서 그려진다.
//
//  알파 블렌딩(Transparent)과 달리 cutout 은 픽셀을 "버리거나 그리거나"
//  둘 중 하나라 반투명이 없다. 그래서 ZWrite 를 켜 둘 수 있고, 덕분에
//  정렬 문제에서 자유롭다.
// =====================================================================
Shader "Unlit/spriteShader"
{
    Properties
    {
        _BaseMap   ("Base Map", 2D)             = "white" {}
        _BaseColor ("Base Color", Color)        = (1, 1, 1, 1)
        // Sprite 의 백그라운드 / 포그라운드를 구분하는 알파값
        _Cutoff    ("Alpha Cutoff", Range(0, 1)) = 0.5

        [Header(Billboard)]
        // Spherical  : 모든 축을 카메라에 맞춤 (슬라이드 방식)
        // Cylindrical: Y축은 월드 위쪽으로 고정 - 나무 / 잔디용
        [KeywordEnum(Spherical, Cylindrical)] _BILLBOARD ("Billboard Type", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"  = "UniversalPipeline"
            "RenderType"      = "TransparentCutout"
            "Queue"           = "AlphaTest"
            "IgnoreProjector" = "True"
        }

        // 빌보드는 뒤에서 봐도 보여야 하므로 양면으로 그린다.
        // (Unity Quad 의 앞면이 어느 쪽인지에 따라 안 보이는 사고를 막는다)
        Cull Off
        // cutout 은 반투명이 아니므로 깊이를 써도 된다
        ZWrite On

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma multi_compile_instancing            // Material 의 Enable GPU Instancing 용 (p.20)
            #pragma shader_feature_local _BILLBOARD_SPHERICAL _BILLBOARD_CYLINDRICAL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float  _Cutoff;
                float  _BILLBOARD;      // 인스펙터 토글용 (SRP Batcher 호환)
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // ---------------------------------------------------------
            // Vertex Shader (p.22 ~ p.26)
            // ---------------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                // View 행렬 = world -> camera space.
                // 그 upper-left 3x3 의 각 행이 카메라의 월드 공간 축이다. (p.22)
                float3 _r = UNITY_MATRIX_V[0].xyz;   // 카메라 right
                float3 _u = UNITY_MATRIX_V[1].xyz;   // 카메라 up
                float3 _f = UNITY_MATRIX_V[2].xyz;   // 카메라 뒤쪽 (씬 -> 눈)

            #if defined(_BILLBOARD_CYLINDRICAL)
                // Y축을 월드 위쪽으로 고정. 카메라가 위아래로 움직여도
                // 나무가 눕지 않는다.
                _u = float3(0, 1, 0);
                _r = normalize(float3(_r.x, 0, _r.z));
                _f = cross(_r, _u);
            #endif

                // Quad 의 중심점을 world space 로 (local 원점 -> world) (p.23)
                float3 q = TransformObjectToWorld(float3(0, 0, 0));

                // 빌보드 행렬 B. HLSL 의 행렬 초기화는 row 단위로 한다. (p.23)
                //
                //      | _r.x  _u.x  _f.x  q.x |
                //  B = | _r.y  _u.y  _f.y  q.y |
                //      | _r.z  _u.z  _f.z  q.z |
                //      |  0     0     0     1  |
                float4x4 B = {
                    _r.x, _u.x, _f.x, q.x,
                    _r.y, _u.y, _f.y, q.y,
                    _r.z, _u.z, _f.z, q.z,
                    0.0,  0.0,  0.0,  1.0
                };

                // B 는 scale 을 담고 있지 않다. Quad 를 키워 뒀으므로
                // Model 행렬의 대각 성분에서 scale 을 따로 꺼낸다. (p.24)
                float3 s = unity_ObjectToWorld._m00_m11_m22;

                float3 scaledVertex = IN.positionOS.xyz * float3(s.x, s.y, s.z);

                // B 가 위 그림처럼 놓여 있으므로 "행렬 x 열벡터" 순서로 곱한다.
                // (README 의 '곱셈 순서' 항목 참고)
                float3 vertex = mul(B, float4(scaledVertex, 1.0)).xyz;

                OUT.positionHCS = TransformWorldToHClip(vertex);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            // ---------------------------------------------------------
            // Fragment Shader (p.27)
            // ---------------------------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                half4 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);

                // 백그라운드 / 포그라운드 구분 : 음수면 픽셀을 버린다
                clip(base.a - _Cutoff);

                return base * _BaseColor;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
