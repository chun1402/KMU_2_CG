// =====================================================================
//  Class 8 - Assignment 1 : Steep Parallax Mapping  (슬라이드 p.38 ~ p.41)
//  Advanced Computer Graphics / Mankyu Sung
//  ref) https://learnopengl.com/Advanced-Lighting/Parallax-Mapping
//
//  기본 Parallax 의 한계 :
//     T0 에서 읽은 H(T0) 만큼 "한 번에" UV 를 밀어버리기 때문에, 높이가 급격히
//     변하는(steep) 표면에서는 엉뚱한 지점을 가리키게 되어 왜곡이 생긴다.
//
//  Steep Parallax 의 아이디어 (p.41) :
//     같은 시선 벡터 방향으로 "한 번에 가지 말고 쪼개서" 진행한다.
//     표면을 N 개의 깊이 레이어로 나누고, 레이어를 한 칸 내려갈 때마다 UV 도
//     한 칸(deltaUV) 밀면서, 현재 레이어 깊이가 height map 의 깊이를 넘어서는
//     (= 빨간 곡선 아래로 내려가는) 첫 지점 T_k 를 찾는다.
//
//  Parallax Occlusion(POM) :
//     Steep 의 계단(layer) 티를 없애기 위해 교차 직전/직후 두 샘플을 선형보간.
// =====================================================================
Shader "Unlit/myShader_SteepParallaxMapping"
{
    Properties
    {
        [MainTexture] _BaseMap       ("Base Map", 2D)               = "white" {}
        [Normal]      _NormalMap     ("Normal Map", 2D)             = "bump"  {}
                      _HeightMap     ("Height Map (grayscale)", 2D) = "black" {}
                      _NormalStrength("Normal Strength", Range(0, 2)) = 1

        [Header(Parallax)]
        // None = Normal mapping 만 (비교용) / Basic = p.34 / Steep = p.38 / Occlusion = POM
        [KeywordEnum(None, Basic, Steep, Occlusion)] _PARALLAX ("Parallax Mode", Float) = 2
        _DepthScale ("Depth Scale", Range(0, 0.2)) = 0.05
        _MinLayers  ("Min Layers", Range(1, 64))   = 8
        _MaxLayers  ("Max Layers", Range(1, 64))   = 32
        [Toggle(_INVERT_HEIGHT)] _InvertHeight ("Height map is Height (not Depth)", Float) = 1
        // 가장자리에서 UV 가 [0,1] 을 벗어날 때 픽셀을 버려 늘어짐을 제거
        [Toggle(_CLIP_EDGES)]    _ClipEdges    ("Discard out-of-range UV", Float) = 0

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
            #pragma target   3.0
            #pragma shader_feature_local _PARALLAX_NONE _PARALLAX_BASIC _PARALLAX_STEEP _PARALLAX_OCCLUSION
            #pragma shader_feature_local _LIGHTSPACE_WORLD _LIGHTSPACE_TANGENT
            #pragma shader_feature_local _INVERT_HEIGHT
            #pragma shader_feature_local _CLIP_EDGES

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 레이어 루프의 컴파일 타임 상한 (_MaxLayers 는 이 값 이하로 사용)
            #define MAX_PARALLAX_STEPS 64

            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);  SAMPLER(sampler_NormalMap);
            TEXTURE2D(_HeightMap);  SAMPLER(sampler_HeightMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float4 _HeightMap_ST;
                float  _NormalStrength;
                float  _DepthScale;
                float  _MinLayers;
                float  _MaxLayers;
                float4 _SpecularColor;
                float  _Shininess;
                float  _AmbientStrength;
                float  _InvertHeight;       // 인스펙터 토글용 (SRP Batcher 호환)
                float  _ClipEdges;
                float  _LIGHTSPACE;
                float  _PARALLAX;
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

            // 0 = 표면(가장 바깥), 1 = 가장 깊은 곳
            float SampleDepth(float2 uv)
            {
                float h = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv).r;
            #if defined(_INVERT_HEIGHT)
                h = 1.0 - h;
            #endif
                return h;
            }

            // 루프 안에서는 UV 미분값이 불연속이므로 명시적 gradient 로 샘플링해야
            // 밉맵 선택이 깨지지 않는다 (화면 전체가 지글거리는 현상 방지)
            float SampleDepthGrad(float2 uv, float2 dx, float2 dy)
            {
                float h = SAMPLE_TEXTURE2D_GRAD(_HeightMap, sampler_HeightMap, uv, dx, dy).r;
            #if defined(_INVERT_HEIGHT)
                h = 1.0 - h;
            #endif
                return h;
            }

            // =========================================================
            // 1) Basic Parallax Mapping  (p.34)
            //    shift = (v.xy / v.z) * depth * scale
            // =========================================================
            float2 ParallaxOffset(float2 uv, float3 viewDirTS)
            {
                float  depth  = SampleDepth(uv);
                float2 offset = viewDirTS.xy / max(viewDirTS.z, 0.05) * (depth * _DepthScale);
                return uv - offset;
            }

            // =========================================================
            // 2) Steep Parallax Mapping  (p.38, p.41)
            //    + 3) Parallax Occlusion (마지막 보간) : _PARALLAX_OCCLUSION 일 때만
            // =========================================================
            float2 SteepParallaxOffset(float2 uv, float3 viewDirTS)
            {
                // 정면에서 볼수록 레이어 적게, 비스듬히 볼수록 많이 (깊이 왜곡이 커지므로)
                float minL = min(_MinLayers, _MaxLayers);
                float maxL = max(_MinLayers, _MaxLayers);
                float numLayers = lerp(maxL, minL, saturate(abs(viewDirTS.z)));

                float layerDepth = 1.0 / numLayers;   // 레이어 1칸의 깊이 증가량

                // 깊이 0 -> 1 동안 UV 가 총 이동해야 하는 벡터 P
                float2 P = viewDirTS.xy / max(viewDirTS.z, 0.05) * _DepthScale;
                float2 deltaUV = P / numLayers;       // 레이어 1칸당 UV 이동량

                // 루프 안 샘플링용 gradient (진입 시점의 화면 미분값을 고정 사용)
                float2 dx = ddx(uv);
                float2 dy = ddy(uv);

                float2 currentUV    = uv;
                float  currentDepth = 0.0;                                  // 광선이 내려온 깊이
                float  mapDepth     = SampleDepthGrad(currentUV, dx, dy);   // 그 지점 표면의 깊이

                // 광선 깊이가 표면 깊이를 넘어서는 첫 지점까지 전진 (T0 -> T1 -> T2 ...)
                [loop]
                for (int k = 0; k < MAX_PARALLAX_STEPS; ++k)
                {
                    if (currentDepth >= mapDepth) break;   // 빨간 곡선 아래로 내려감 = 교차
                    currentUV    -= deltaUV;
                    mapDepth      = SampleDepthGrad(currentUV, dx, dy);
                    currentDepth += layerDepth;
                }

            #if defined(_PARALLAX_OCCLUSION)
                // --- 교차 직전(prev) 과 직후(current) 사이를 선형보간 ---
                float2 prevUV = currentUV + deltaUV;

                float afterDepth  = mapDepth - currentDepth;                                  // 교차 후 (<=0)
                float beforeDepth = SampleDepthGrad(prevUV, dx, dy) - currentDepth + layerDepth; // 교차 전 (>0)

                float denom  = afterDepth - beforeDepth;                      // 항상 음수
                float weight = (abs(denom) < 1e-6) ? 0.0 : saturate(afterDepth / denom);
                currentUV = lerp(currentUV, prevUV, weight);
            #endif

                return currentUV;
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

                float3x3 TBN            = float3x3(T, B, N);
                float3x3 worldToTangent = transpose(TBN);

                Light  mainLight  = GetMainLight();
                float3 Lw         = normalize(mainLight.direction);
                float3 viewDirWS  = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float3 viewDirTS  = normalize(mul(viewDirWS, worldToTangent));

                // ---- UV 재계산 ----
            #if   defined(_PARALLAX_BASIC)
                float2 uvP = ParallaxOffset(i.uv, viewDirTS);
            #elif defined(_PARALLAX_STEEP) || defined(_PARALLAX_OCCLUSION)
                float2 uvP = SteepParallaxOffset(i.uv, viewDirTS);
            #else
                float2 uvP = i.uv;                 // Normal mapping 만 (비교용)
            #endif

            #if defined(_CLIP_EDGES)
                // 밀려난 UV 가 타일 밖으로 나가면 버린다 (경계 늘어짐 제거)
                clip(min(min(uvP.x, uvP.y), min(1.0 - uvP.x, 1.0 - uvP.y)));
            #endif

                float3 normalTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvP), _NormalStrength);
                normalTS = normalize(normalTS);

                float4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvP);

                float3 nrm, L, V;

            #if defined(_LIGHTSPACE_TANGENT)
                nrm = normalTS;
                L   = normalize(mul(Lw,        worldToTangent));
                V   = normalize(mul(viewDirWS, worldToTangent));
            #else
                nrm = normalize(mul(normalTS, TBN));
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
