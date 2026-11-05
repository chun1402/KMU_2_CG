// =====================================================================
//  Class 10 - Reflection (슬라이드 p.2 ~ p.14)
//  Advanced Computer Graphics / Mankyu Sung
//
//  반사는 두 단계로 이루어진다. (p.3)
//   1) Skybox   : 주변 환경을 cubemap 으로 그린다.
//                 -> 셰이더를 만들 필요 없다. 내장 Skybox/Cubemap 사용 (p.12)
//   2) Reflective: 그 환경이 비친 오브젝트 표면을 그린다.
//                 -> 이 셰이더가 그것이다. (p.8 ~ p.10)
//
//  원리
//    눈에서 표면의 점 p 로 들어온 시선이 법선 N 에 대해 반사되어 환경의
//    어느 방향을 보게 되는지 구하고(reflect), 그 방향으로 cubemap 을
//    샘플링한다. 그 색을 원래 표면색과 _Reflectivity 로 섞는다.
//
//  주의 : V 는 p -> 카메라 방향이라, reflect 에 넣을 때는 부호를 뒤집는다.
//         reflect(I, N) 의 I 는 표면으로 "들어오는" 방향이기 때문이다. (p.9)
// =====================================================================
Shader "Unlit/myShader_Reflective"
{
    Properties
    {
        _MainTex      ("Albedo", 2D)                = "white" {}   // Base texture map
        _Cube         ("Reflection Cubemap", CUBE)  = "" {}        // cube map
        _Reflectivity ("Reflectivity", Range(0, 1)) = 1.0          // 반사 vs 원래 색

        [Header(Debug)]
        // Vertex : 슬라이드 방식. 정점에서 구해 보간한다.
        // Pixel  : 픽셀마다 구한다. 면이 적은 메쉬에서 훨씬 정확하다.
        [KeywordEnum(Vertex, Pixel)] _REFLDIR ("Reflection Dir", Float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Opaque"
            "Queue"          = "Geometry"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature_local _REFLDIR_VERTEX _REFLDIR_PIXEL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // p.8
            TEXTURE2D(_MainTex);   SAMPLER(sampler_MainTex);
            TEXTURECUBE(_Cube);    SAMPLER(sampler_Cube);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float  _Reflectivity;
                float  _REFLDIR;        // 인스펙터 토글용 (SRP Batcher 호환)
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float3 reflectDir  : TEXCOORD3;   // 슬라이드 방식(정점에서 계산)
            };

            // ---------------------------------------------------------
            // Vertex Shader (p.9)
            //
            //   p : world 좌표계에서의 점
            //   N : world 좌표계에서의 법선
            //   V : p -> 카메라 방향  (= _WorldSpaceCameraPos - p)
            //
            //   ReflectDir = reflect(-V, N)
            //
            //   왜 -V 인가. reflect(I, N) 의 I 는 표면으로 들어오는 입사
            //   벡터다. V 는 p 에서 카메라로 나가는 방향이므로 반대로 뒤집어야
            //   "카메라 -> p" 라는 입사 방향이 된다.
            // ---------------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 p = TransformObjectToWorld(IN.positionOS.xyz);

                // normal matrix 를 직접 만들지 않고 이 함수를 쓴다
                float3 N = TransformObjectToWorldNormal(IN.normalOS);

                float3 V = _WorldSpaceCameraPos - p;

                OUT.positionHCS = TransformWorldToHClip(p);
                OUT.uv          = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.positionWS  = p;
                OUT.normalWS    = N;
                OUT.reflectDir  = reflect(-normalize(V), normalize(N));

                return OUT;
            }

            // ---------------------------------------------------------
            // Fragment Shader (p.10)
            // ---------------------------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                float3 baseCol = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).rgb;

            #if defined(_REFLDIR_PIXEL)
                // 픽셀마다 다시 계산한다. 보간으로 짧아진 법선을 되살려야 하므로
                // normalize 가 필요하다.
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - IN.positionWS);
                float3 R = reflect(-V, N);
            #else
                // 슬라이드 방식 : 정점에서 구한 값을 그대로 보간해서 쓴다
                float3 R = normalize(IN.reflectDir);
            #endif

                float3 refl = SAMPLE_TEXTURECUBE(_Cube, sampler_Cube, R).rgb;

                // 반사된 색을 쓸지 원래 색을 쓸지 _Reflectivity 로 섞는다 (p.10, p.11)
                float3 color = lerp(baseCol, refl, _Reflectivity);

                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
