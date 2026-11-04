// =====================================================================
//  Class 9 - Billboard Rendering + Wind (슬라이드 p.19 ~ p.33, p.51)
//  Advanced Computer Graphics / Mankyu Sung
//
//  Quad 하나에 sprite 를 입히고, vertex shader 에서 그 quad 가 항상 카메라를
//  바라보도록 돌려 세운다. 나무 / 꽃 / 잔디처럼 복잡한 오브젝트를 아주 싸게
//  "그럴듯하게" 그리는 기법.
//
//   1) 빌보드 행렬 B
//      View 행렬의 upper-left 3x3 은 카메라의 월드 공간 축(right/up/forward)
//      이다. 이 세 축을 quad 의 축으로 그대로 쓰면 quad 가 카메라 평면과
//      나란해진다. 거기에 quad 중심점 q 를 평행이동으로 얹는다.
//
//   2) Alpha cutout
//      sprite 의 알파가 _Cutoff 보다 작은 픽셀은 clip() 으로 버린다.
//      Queue = AlphaTest(2450) : 불투명 뒤, 투명 앞에서 그려진다.
//
//   3) Wind (p.51)
//      _Time 을 써서 정점을 흔든다. 슬라이드의 한 줄은
//          vertex.x += sin(vertex.z * 4.0 + _Time.y * 2.0) * 0.2;
//      이고, 여기서는 "밑동은 고정, 끝만 흔들림" 과 "꽃 단위 위상" 두 가지를
//      더 적용했다. 자세한 이유는 README_Billboard.md 참고.
//
//  GPU instancing 대응 : #pragma multi_compile_instancing +
//  UNITY_VERTEX_INPUT_INSTANCE_ID + UNITY_SETUP_INSTANCE_ID
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

        [Header(Wind)]
        [Toggle(_WIND)] _WindEnable ("Enable Wind", Float) = 1
        _WindStrength  ("Strength", Range(0, 1))     = 0.2
        _WindSpeed     ("Speed", Range(0, 8))        = 2.0
        _WindFrequency ("Frequency", Range(0, 8))    = 4.0
        _WindDirection ("Direction (XZ)", Vector)    = (1, 0, 0, 0)
        // 0 = 전체가 통째로 흔들림(슬라이드), 1 = 밑동 고정하고 끝만 흔들림
        _WindRooting   ("Root Stiffness", Range(0, 1)) = 1.0
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
            #pragma multi_compile_instancing
            #pragma shader_feature_local _BILLBOARD_SPHERICAL _BILLBOARD_CYLINDRICAL
            #pragma shader_feature_local _WIND

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap);  SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float  _Cutoff;
                float  _BILLBOARD;      // 인스펙터 토글용 (SRP Batcher 호환)
                float  _WindEnable;
                float  _WindStrength;
                float  _WindSpeed;
                float  _WindFrequency;
                float4 _WindDirection;
                float  _WindRooting;
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
            //  Wind (p.51)
            //
            //  슬라이드 원본 :
            //      vertex.x += sin(vertex.z * 4.0 + _Time.y * 2.0) * 0.2;
            //
            //  세 가지를 바꿨다.
            //   (a) 위상을 "정점의 z" 가 아니라 "꽃의 중심 q" 에서 뽑는다.
            //       정점마다 위상이 다르면 quad 한 장이 좌우로 찢어진다.
            //   (b) 밑동은 고정하고 위로 갈수록 크게 흔든다. (_WindRooting)
            //       통째로 밀면 꽃이 미끄러지는 것처럼 보인다.
            //   (c) 주파수가 다른 사인 둘을 섞어 반복되는 티를 줄인다.
            //
            //  heightT : quad 안에서의 높이. Unity Quad 는 y 가 [-0.5, 0.5] 라
            //            +0.5 를 더해 [0, 1] 로 만든다. 0 = 밑동, 1 = 끝.
            // ---------------------------------------------------------
            float3 ApplyWind(float3 worldPos, float3 q, float heightT)
            {
            #if defined(_WIND)
                // (a) 꽃 한 송이당 하나의 위상. 위치가 다르면 위상도 달라진다.
                float phase = (q.x * 0.7 + q.z) * _WindFrequency + _Time.y * _WindSpeed;

                // (c) 사인 두 개를 섞는다. 합이 [-1, 1] 에 머물도록 1.5 로 나눈다.
                float sway = (sin(phase) + 0.5 * sin(phase * 2.3 + 1.7)) / 1.5;

                // (b) 밑동 고정. _WindRooting 이 0이면 전체가 통째로 흔들린다.
                float weight = lerp(1.0, heightT * heightT, _WindRooting);

                float2 dir = normalize(_WindDirection.xz + 1e-5);
                worldPos.xz += dir * sway * _WindStrength * weight;
            #endif
                return worldPos;
            }

            // ---------------------------------------------------------
            // Vertex Shader
            // ---------------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                // View 행렬 = world -> camera space.
                // 그 upper-left 3x3 의 각 행이 카메라의 월드 공간 축이다.
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

                // Quad 의 중심점을 world space 로 (local 원점 -> world)
                float3 q = TransformObjectToWorld(float3(0, 0, 0));

                // 빌보드 행렬 B. HLSL 의 행렬 초기화는 row 단위로 한다.
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
                // Model 행렬의 대각 성분에서 scale 을 따로 꺼낸다.
                float3 s = unity_ObjectToWorld._m00_m11_m22;

                float3 scaledVertex = IN.positionOS.xyz * float3(s.x, s.y, s.z);

                // B 가 위 그림처럼 놓여 있으므로 "행렬 x 열벡터" 순서로 곱한다.
                float3 vertex = mul(B, float4(scaledVertex, 1.0)).xyz;

                // 바람은 빌보드 변환이 끝난 월드 좌표에 적용한다. (p.51)
                // 그래야 카메라를 돌려도 흔들리는 방향이 변하지 않는다.
                float heightT = saturate(IN.positionOS.y + 0.5);
                vertex = ApplyWind(vertex, q, heightT);

                OUT.positionHCS = TransformWorldToHClip(vertex);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            // ---------------------------------------------------------
            // Fragment Shader
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
