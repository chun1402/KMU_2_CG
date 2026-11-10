// =====================================================================
//  Class 10 - Refraction (슬라이드 p.19 ~ p.27)
//  Advanced Computer Graphics / Mankyu Sung
//
//  유리처럼 투명한 물체에서는 빛이 표면 안으로 들어가(transmit) 꺾이고(bend)
//  다시 나온다. 꺾이는 각도는 Snell 의 법칙을 따른다. (p.21)
//
//    refract(I, N, eta)
//      I   : 표면으로 들어오는 입사 벡터  (V 가 p -> 카메라이므로 -V)
//      N   : 법선
//      eta : 굴절률의 비 = sin(θ1) / sin(θ2)
//
//  공기에서 유리로 들어가는 경우이므로
//    eta = n_공기 / n_유리 = 1.0 / _RefractionIndex              (p.24)
//
//  ---------------------------------------------------------------------
//  실제 물체는 굴절만 하지 않고 표면에서 일부를 반사한다. 그 비율을
//  정하는 방식이 두 가지이고, Mix Mode 로 전환한다.
//
//   Fixed   (p.24) : 고정 비율. 슬라이드 기본값은 굴절 0.9 : 반사 0.1
//   Fresnel (p.26) : 보는 각도에 따라 자동. Schlick's approximation
//                      f = ( 1 - max(N · V, 0) ) ^ p
//
//  두 모드의 차이는 lerp 의 세 번째 인자 하나뿐이다.
//
//      color = lerp(refractionColor, reflectionColor, f);
//                                                     ^
//                              Fixed  : _ReflectionAmount (상수)
//                              Fresnel: 각도에서 계산한 f
//
//  Mix Mode 는 머티리얼마다 따로 정해지므로, 같은 셰이더로 머티리얼을 둘
//  만들어 한쪽은 Fixed, 한쪽은 Fresnel 로 두면 나란히 비교할 수 있다.
// =====================================================================
Shader "Unlit/myShader_Refraction"
{
    Properties
    {
        // reflection 셰이더와 다른 점 : base map 이 없고 base color 를 쓴다 (p.23)
        _Color           ("Base Color", Color)                 = (1, 1, 1, 1)
        _Cube            ("Reflection Cubemap", CUBE)          = "" {}
        _RefractionIndex ("Refraction Index", Range(1.0, 2.5)) = 1.5   // eta

        [Header(Reflection Mix)]
        // Fixed   : p.24 방식 (고정 비율)
        // Fresnel : p.26 방식 (각도에 따라 자동)
        [KeywordEnum(Fixed, Fresnel)] _MIX ("Mix Mode", Float) = 1

        // Fixed 모드에서만 쓰인다. 0.1 = 슬라이드 기본값 (굴절 0.9 : 반사 0.1)
        _ReflectionAmount ("Reflection Amount (Fixed)", Range(0, 1)) = 0.1

        // Fresnel 모드에서만 쓰인다. 클수록 정면이 넓게 투명해진다
        _FresnelPower ("Fresnel Power", Range(0.1, 5.0)) = 2.0
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
            #pragma shader_feature_local _MIX_FIXED _MIX_FRESNEL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURECUBE(_Cube);  SAMPLER(sampler_Cube);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float  _RefractionIndex;
                float  _MIX;              // 인스펙터 토글용 (SRP Batcher 호환)
                float  _ReflectionAmount;
                float  _FresnelPower;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float3 p = TransformObjectToWorld(IN.positionOS.xyz);

                OUT.positionHCS = TransformWorldToHClip(p);
                OUT.positionWS  = p;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);

                return OUT;
            }

            // ---------------------------------------------------------
            // Fragment Shader (p.24, p.26)
            // ---------------------------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                // refract() 와 reflect() 는 둘 다 정규화된 벡터를 요구한다
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - IN.positionWS);

                // ---- Refraction (p.24) ----
                // 공기(1.0) -> 물체(_RefractionIndex) 로 들어가므로 비는 1/n
                float  eta        = 1.0 / _RefractionIndex;
                float3 refractDir = refract(-V, N, eta);
                half3  refractionColor = SAMPLE_TEXTURECUBE(_Cube, sampler_Cube, refractDir).rgb;

                // ---- Reflection ----
                float3 reflectDir = reflect(-V, N);
                half3  reflectionColor = SAMPLE_TEXTURECUBE(_Cube, sampler_Cube, reflectDir).rgb;

                // ---- 섞는 비율 결정 ----
            #if defined(_MIX_FRESNEL)
                // p.26 : Schlick's approximation
                //   N·V 가 1 (정면)   -> f = 0 -> 굴절 우세
                //   N·V 가 0 (실루엣) -> f = 1 -> 반사 우세
                float f = pow(1.0 - max(dot(N, V), 0.0), _FresnelPower);
            #else
                // p.24 : 어느 각도에서 보든 같은 비율
                float f = _ReflectionAmount;
            #endif

                half3 color = lerp(refractionColor, reflectionColor, f);

                // 유리의 색을 입힌다 (p.23 의 base color)
                color *= _Color.rgb;

                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
