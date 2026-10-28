// =====================================================================
//  Class 8 - Normal Mapping  (슬라이드 p.13 ~ p.24)
//  Advanced Computer Graphics / Mankyu Sung
//
//  - Tangent space(T, B, N) 를 vertex shader 에서 구성해 fragment 로 전달
//  - Normal map 에서 읽은 normal 로 lighting 계산
//  - 방법1(p.23) : world space 에서 lighting
//  - 방법2(p.24) : tangent space 에서 lighting
//    => Material 인스펙터의 "Lighting Space" 로 전환 (결과는 동일해야 정상)
// =====================================================================
Shader "Unlit/myShader_NormalMapping"
{
    Properties
    {
        [MainTexture] _BaseMap       ("Base Map", 2D)             = "white" {}
        [Normal]      _NormalMap     ("Normal Map", 2D)           = "bump"  {}
                      _NormalStrength("Normal Strength", Range(0, 2)) = 1

        [Header(Blinn Phong)]
        _SpecularColor ("Specular Color", Color)        = (1, 1, 1, 1)
        _Shininess     ("Shininess", Range(1, 256))     = 32
        _AmbientStrength("Ambient", Range(0, 1))        = 0.15

        [Header(Debug)]
        // 방법1 = World, 방법2 = Tangent
        [KeywordEnum(World, Tangent)] _LIGHTSPACE ("Lighting Space", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"       = "Opaque"
            "RenderPipeline"   = "UniversalPipeline"
            "Queue"            = "Geometry"
        }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature_local _LIGHTSPACE_WORLD _LIGHTSPACE_TANGENT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ---------------------------------------------------------
            // 텍스처 / 샘플러 / Tiling-Offset  (p.14)
            // ---------------------------------------------------------
            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);  SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;         // tiling and offset
                float4 _NormalMap_ST;
                float  _NormalStrength;
                float4 _SpecularColor;
                float  _Shininess;
                float  _AmbientStrength;
                float  _LIGHTSPACE;         // 인스펙터 토글용 (SRP Batcher 호환)
            CBUFFER_END

            // ---------------------------------------------------------
            // 정점 입력 : tangent vector 포함  (p.13)
            // ---------------------------------------------------------
            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;   // xyz = U 방향, w = B 의 handedness(±1)
            };

            // 실제 매핑은 fragment 에서 하므로 T,B,N 을 넘겨준다 (p.18)
            struct Interpolators
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 T           : TEXCOORD2;
                float3 B           : TEXCOORD3;
                float3 N           : TEXCOORD4;
            };

            // ---------------------------------------------------------
            // Vertex : Texture space(T,B,N) 구성 - 모두 world space (p.15)
            // ---------------------------------------------------------
            Interpolators vert(appdata input)
            {
                Interpolators o;

                VertexPositionInputs posIn = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionHCS = posIn.positionCS;
                o.positionWS  = posIn.positionWS;
                o.uv          = TRANSFORM_TEX(input.uv, _BaseMap);

                // tangentOS.w : bitangent 방향(+1/-1). 음수 스케일 오브젝트 보정까지 포함
                half tangentSign = input.tangentOS.w * GetOddNegativeScale();

                // normal 은 역전치 행렬로, tangent 는 단순 방향 변환으로 (p.17)
                float3 N = TransformObjectToWorldNormal(input.normalOS);
                float3 T = normalize(TransformObjectToWorldDir(input.tangentOS.xyz));
                float3 B = cross(N, T) * tangentSign;

                o.N = N;
                o.T = T;
                o.B = B;
                return o;
            }

            // ---------------------------------------------------------
            // Fragment
            // ---------------------------------------------------------
            half4 frag(Interpolators i) : SV_Target
            {
                // 보간으로 깨진 직교성 복구
                float3 N = normalize(i.N);
                float3 T = normalize(i.T - dot(i.T, N) * N);   // Gram-Schmidt
                float3 B = normalize(i.B);

                // HLSL 은 row-vector 규약 : mul(벡터, 행렬) (p.16)
                //   tangent -> world : mul(v, TBN)
                //   world   -> tangent : mul(v, transpose(TBN))
                float3x3 TBN = float3x3(T, B, N);   // 각 row 가 T, B, N (p.15)

                // Normal map 에서 tangent space normal 획득 (p.19)
                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalStrength);
                normalTS = normalize(normalTS);

                float4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                Light mainLight = GetMainLight();
                float3 Lw = normalize(mainLight.direction);
                float3 Vw = GetWorldSpaceNormalizeViewDir(i.positionWS);

                float3 nrm, L, V;

            #if defined(_LIGHTSPACE_TANGENT)
                // ---- 방법2 : tangent space 에서 lighting (p.24) ----
                // normal map 의 normal 을 그대로 사용하고, L/V 를 tangent space 로 보낸다
                float3x3 worldToTangent = transpose(TBN);
                nrm = normalTS;
                L   = normalize(mul(Lw, worldToTangent));
                V   = normalize(mul(Vw, worldToTangent));
            #else
                // ---- 방법1 : world space 에서 lighting (p.22, 권장) ----
                // normal map 의 normal 을 world space 로 변환
                nrm = normalize(mul(normalTS, TBN));
                L   = Lw;
                V   = Vw;
            #endif

                // Blinn-Phong
                float  NdotL    = saturate(dot(nrm, L));
                float3 H        = normalize(L + V);
                float  specTerm = pow(saturate(dot(nrm, H)), _Shininess) * (NdotL > 0 ? 1 : 0);

                float3 diffuse  = albedo.rgb * NdotL;
                float3 specular = _SpecularColor.rgb * specTerm;
                float3 ambient  = albedo.rgb * _AmbientStrength;

                float3 final = (diffuse + specular) * mainLight.color + ambient;
                return half4(final, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Unlit"
}
