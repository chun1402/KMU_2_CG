// =====================================================================
//  Class 8 - Parallax Mapping  (슬라이드 p.25 ~ p.37)
//  Advanced Computer Graphics / Mankyu Sung
//
//  핵심 :  normal 을 바꾸는 것이 아니라, "샘플링할 UV 좌표를 shift" 한다.
//          shift 량은 height(depth) map 과 tangent space 의 시선벡터로 결정.
//
//              v.xy / v.z = shift / depth   =>   shift = (v.xy / v.z) * depth   (p.33)
//
//  - 방법1(p.35) : world space 에서 lighting
//  - 방법2(p.36) : tangent space 에서 lighting
// =====================================================================
Shader "Unlit/myShader_ParallaxMapping"
{
    Properties
    {
        [MainTexture] _BaseMap       ("Base Map", 2D)             = "white" {}
        [Normal]      _NormalMap     ("Normal Map", 2D)           = "bump"  {}
                      _HeightMap     ("Height Map (grayscale)", 2D) = "black" {}
                      _NormalStrength("Normal Strength", Range(0, 2)) = 1

        [Header(Parallax)]
        _DepthScale   ("Depth Scale", Range(0, 0.2))  = 0.05
        // Height map 이 "높이"(흰색 = 돌출) 이면 On, "깊이"(흰색 = 함몰) 이면 Off
        [Toggle(_INVERT_HEIGHT)] _InvertHeight ("Height map is Height (not Depth)", Float) = 1

        [Header(Blinn Phong)]
        _SpecularColor  ("Specular Color", Color)    = (1, 1, 1, 1)
        _Shininess      ("Shininess", Range(1, 256)) = 32
        _AmbientStrength("Ambient", Range(0, 1))     = 0.15

        [Header(Debug)]
        [KeywordEnum(World, Tangent)] _LIGHTSPACE ("Lighting Space", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType"     = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue"          = "Geometry"
        }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma shader_feature_local _LIGHTSPACE_WORLD _LIGHTSPACE_TANGENT
            #pragma shader_feature_local _INVERT_HEIGHT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);  SAMPLER(sampler_NormalMap);
            TEXTURE2D(_HeightMap);  SAMPLER(sampler_HeightMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float4 _HeightMap_ST;
                float  _NormalStrength;
                float  _DepthScale;
                float4 _SpecularColor;
                float  _Shininess;
                float  _AmbientStrength;
                float  _InvertHeight;       // 인스펙터 토글용 (SRP Batcher 호환)
                float  _LIGHTSPACE;
            CBUFFER_END

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
            };

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
            // Height map 샘플링 -> "표면에서 얼마나 파였는지(depth)" 로 환산
            //   흰색 = 높음 인 일반적인 Displacement/Height map 이면 1 - h
            // ---------------------------------------------------------
            float SampleDepth(float2 uv)
            {
                float h = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv).r;
            #if defined(_INVERT_HEIGHT)
                h = 1.0 - h;
            #endif
                return h;
            }

            // ---------------------------------------------------------
            // Offset 계산  (p.34)
            //   uv         : A 점의 UV
            //   viewDirTS  : tangent space 로 변환된 시선 벡터 (표면 -> 눈)
            //   viewDirTS.xy : tangent/bitangent 성분,  .z : normal 성분
            // ---------------------------------------------------------
            float2 ParallaxOffset(float2 uv, float3 viewDirTS)
            {
                float  depth  = SampleDepth(uv);                       // H(A)
                // z 가 0 에 가까우면(거의 스치듯 보는 각) offset 이 발산하므로 clamp (p.29)
                float2 offset = viewDirTS.xy / max(viewDirTS.z, 0.05) * (depth * _DepthScale);
                return uv - offset;
            }

            Interpolators vert(appdata input)
            {
                Interpolators o;

                VertexPositionInputs posIn = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionHCS = posIn.positionCS;
                o.positionWS  = posIn.positionWS;
                o.uv          = TRANSFORM_TEX(input.uv, _BaseMap);

                half tangentSign = input.tangentOS.w * GetOddNegativeScale();

                float3 N = TransformObjectToWorldNormal(input.normalOS);
                float3 T = normalize(TransformObjectToWorldDir(input.tangentOS.xyz));
                float3 B = cross(N, T) * tangentSign;

                o.N = N;  o.T = T;  o.B = B;
                return o;
            }

            half4 frag(Interpolators i) : SV_Target
            {
                float3 N = normalize(i.N);
                float3 T = normalize(i.T - dot(i.T, N) * N);
                float3 B = normalize(i.B);

                float3x3 TBN           = float3x3(T, B, N);   // tangent -> world
                float3x3 worldToTangent = transpose(TBN);     // world   -> tangent

                Light mainLight = GetMainLight();
                float3 Lw = normalize(mainLight.direction);
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.positionWS);

                // *** Parallax 는 반드시 tangent space 시선벡터로 계산 (p.35) ***
                float3 viewDirTS = normalize(mul(viewDirWS, worldToTangent));

                // 조정된 UV
                float2 uvP = ParallaxOffset(i.uv, viewDirTS);

                // 이후 모든 샘플링은 uvP 로 (p.28)
                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvP), _NormalStrength);
                normalTS = normalize(normalTS);

                float4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvP);

                float3 nrm, L, V;

            #if defined(_LIGHTSPACE_TANGENT)
                // ---- 방법2 : tangent space 에서 lighting (p.36) ----
                nrm = normalTS;                                  // 그대로 사용
                L   = normalize(mul(Lw,        worldToTangent));
                V   = normalize(mul(viewDirWS, worldToTangent));
            #else
                // ---- 방법1 : world space 에서 lighting (p.35) ----
                nrm = normalize(mul(normalTS, TBN));             // tangent -> world
                L   = Lw;
                V   = viewDirWS;
            #endif

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
