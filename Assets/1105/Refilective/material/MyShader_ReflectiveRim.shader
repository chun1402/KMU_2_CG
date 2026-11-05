// =====================================================================
//  Class 10 - Reflection + Rim Light (슬라이드 p.15 ~ p.18)
//  Advanced Computer Graphics / Mankyu Sung
//
//  Rim light = 오브젝트의 실루엣(테두리)만 밝게 빛나는 효과.
//  뒤에서 빛이 들어와 윤곽이 번지는 것처럼 보인다.
//
//  원리 (p.17)
//    표면 법선 N 과 시선 V 의 내적을 본다. 둘 다 world 좌표계.
//      - N 과 V 가 거의 평행  (dot = 1) -> 정면으로 보는 면 -> rim 약함
//      - N 과 V 가 거의 직각  (dot = 0) -> 실루엣 가장자리 -> rim 강함
//
//    내적이 클수록 효과가 약해야 하므로 1에서 뺀다.
//      power   = 1 - max(0, dot(V, N))
//      fresnel = pow(power, _RimPower)
//
//    _RimPower 가 클수록 테두리가 얇고 날카로워진다.
//
//  최종 색 (p.18)
//      color = lerp(baseCol, refl, _Reflectivity) + _RimColor.rgb * fresnel
//
//  rim 은 섞는 것이 아니라 "더한다". 빛이 더해지는 현상이기 때문이다.
//
//  p.16 : 비교를 위해 캡슐을 하나 더 두고, 한쪽은 Unlit/myShader_Reflective,
//         다른 쪽은 이 셰이더를 쓸 것.
// =====================================================================
Shader "Unlit/myShader_ReflectiveRim"
{
    Properties
    {
        _MainTex      ("Albedo", 2D)                = "white" {}   // Base texture map
        _Cube         ("Reflection Cubemap", CUBE)  = "" {}        // cube map
        _Reflectivity ("Reflectivity", Range(0, 1)) = 1.0          // 반사 vs 원래 색

        [Header(Rim Light)]
        // 슬라이드 p.16 의 Properties 에는 _RimlColor 로 적혀 있으나
        // p.18 의 코드는 _RimColor 를 쓴다. 오타이므로 _RimColor 로 통일한다.
        [HDR] _RimColor ("Rim Color", Color)            = (1, 1, 1, 1)
              _RimPower ("Rim Power", Range(0.1, 10))   = 2.0

        [Header(Debug)]
        // Vertex : 슬라이드 p.9 방식. 정점에서 구해 보간한다.
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

            TEXTURE2D(_MainTex);   SAMPLER(sampler_MainTex);
            TEXTURECUBE(_Cube);    SAMPLER(sampler_Cube);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float  _Reflectivity;
                float4 _RimColor;
                float  _RimPower;
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
                float3 reflectDir  : TEXCOORD3;
            };

            // ---------------------------------------------------------
            // Vertex Shader (p.9)
            //   V 는 p -> 카메라 방향이므로 reflect 에 넣을 때 부호를 뒤집는다.
            // ---------------------------------------------------------
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 p = TransformObjectToWorld(IN.positionOS.xyz);
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
            // Fragment Shader (p.17, p.18)
            // ---------------------------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                float3 baseCol = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).rgb;

                // rim 은 실루엣 효과라 반드시 픽셀 단위로 계산해야 한다.
                // 정점에서 구해 보간하면 테두리가 뭉개지고 면 경계가 드러난다.
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - IN.positionWS);

            #if defined(_REFLDIR_PIXEL)
                float3 R = reflect(-V, N);
            #else
                float3 R = normalize(IN.reflectDir);
            #endif

                float3 refl = SAMPLE_TEXTURECUBE(_Cube, sampler_Cube, R).rgb;

                // ---- Rim (p.17) ----
                // dot 이 1에 가까우면 정면, 0에 가까우면 실루엣.
                // 반비례해야 하므로 1에서 뺀다.
                float power   = 1.0 - max(0.0, dot(V, N));
                float fresnel = pow(power, _RimPower);

                // ---- 합성 (p.18) ----
                // reflection 은 섞고(lerp), rim 은 더한다(+).
                float3 color = lerp(baseCol, refl, _Reflectivity)
                             + _RimColor.rgb * fresnel;

                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
