// =====================================================================
//  Class 10 - Refraction (슬라이드 p.19 ~ p.25)
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
//  실제 물체는 굴절만 하지 않고 표면에서 일부를 반사하기도 한다.
//  이 셰이더는 그 비율을 _ReflectionAmount 로 **고정**해 섞는다. (p.24)
//  슬라이드의 기본값은 굴절 0.9 / 반사 0.1 이다.
//
//  >>> 비교용 : 이 비율을 보는 각도에 따라 자동으로 정하는 것이
//      MyShader_RefractionFresnel.shader (p.26 ~ p.27) 이다.
// =====================================================================
Shader "Unlit/myShader_Refraction"
{
    Properties
    {
        // reflection 셰이더와 다른 점 : base map 이 없고 base color 를 쓴다 (p.23)
        _Color           ("Base Color", Color)              = (1, 1, 1, 1)
        _Cube            ("Reflection Cubemap", CUBE)       = "" {}
        _RefractionIndex ("Refraction Index", Range(1.0, 2.5)) = 1.5   // eta

        [Header(Mix)]
        // 0.1 = 슬라이드 기본값 (굴절 0.9 : 반사 0.1)
        _ReflectionAmount ("Reflection Amount", Range(0, 1)) = 0.1
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURECUBE(_Cube);  SAMPLER(sampler_Cube);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
                float  _RefractionIndex;
                float  _ReflectionAmount;
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
            // Fragment Shader (p.24)
            // ---------------------------------------------------------
            half4 frag(Varyings IN) : SV_Target
            {
                // refract() 와 reflect() 는 둘 다 정규화된 벡터를 요구한다
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - IN.positionWS);

                // ---- Refraction ----
                // 공기(1.0) -> 물체(_RefractionIndex) 로 들어가므로 비는 1/n
                float  eta        = 1.0 / _RefractionIndex;
                float3 refractDir = refract(-V, N, eta);
                half3  refractionColor = SAMPLE_TEXTURECUBE(_Cube, sampler_Cube, refractDir).rgb;

                // ---- Reflection ----
                float3 reflectDir = reflect(-V, N);
                half3  reflectionColor = SAMPLE_TEXTURECUBE(_Cube, sampler_Cube, reflectDir).rgb;

                // ---- 고정 비율로 섞기 ----
                // _ReflectionAmount = 0.1 이면 굴절 0.9 : 반사 0.1
                float3 color = lerp(refractionColor, reflectionColor, _ReflectionAmount);

                // 유리의 색을 입힌다 (p.23 의 base color)
                color *= _Color.rgb;

                return half4(color, 1.0);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
