// =====================================================================
//  Class 11 - Simple PBR Shader (슬라이드 p.50 ~ p.55)
//  Advanced Computer Graphics / Mankyu Sung
//
//  URP 의 Lit shader 는 기능이 많아 무겁다. (p.53)
//  대부분의 AAA 게임은 필요한 항만 남긴 자체 lighting 모델을 쓴다.
//  이 셰이더가 그 "simplify 한 Lit" 에 해당한다. (p.54)
//
//  ---------------------------------------------------------------------
//  Cook-Torrance BRDF (p.37)
//
//      fr = Kd * (c / PI)  +  Ks * ( D F G ) / ( 4 (wo·n)(wi·n) )
//           ---------------      ---------------------------------
//               diffuse                     specular
//
//  유니티 URP 가 쓰는 조합 (p.45)
//      D : Trowbridge-Reitz GGX      -> PBR_D_GGX        (p.40)
//      F : Schlick approximation     -> PBR_F_Schlick    (p.42)
//      G : Schlick-GGX (Smith)       -> PBR_G_Smith      (p.44)
//
//  Metallic-Smoothness workflow (p.47)
//      metallic = 1 -> base map 이 specular 반사색, diffuse 없음
//      metallic = 0 -> base map 이 diffuse 색, F0 는 0.04 고정
//  ---------------------------------------------------------------------
//
//  텍스처는 ambientCG 의 PBR surface 를 그대로 쓴다. (p.50)
//  간접광(환경 반사)은 Lighting 창에 등록한 skybox 에서 자동으로 온다. (p.51)
// =====================================================================
Shader "Custom/SimplePBR"
{
    Properties
    {
        [Header(Surface Maps)]
        [MainTexture] _BaseMap   ("Base Map (Color)", 2D)       = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color)          = (1, 1, 1, 1)
        [Normal]      _NormalMap ("Normal Map (GL)", 2D)        = "bump"  {}
                      _NormalStrength ("Normal Strength", Range(0, 2)) = 1.0

        // ambientCG 는 Metalness 와 Roughness 를 따로 준다.
        // 유니티 Lit 처럼 한 장에 묶을 필요 없이 각각 넣으면 된다.
        _MetallicMap  ("Metallic Map", 2D)        = "white" {}
        _Metallic     ("Metallic", Range(0, 1))   = 1.0
        _RoughnessMap ("Roughness Map", 2D)       = "white" {}
        _Roughness    ("Roughness", Range(0, 1))  = 1.0
        _AOMap        ("Ambient Occlusion", 2D)   = "white" {}

        [Header(Indirect)]
        // skybox 에서 오는 간접광의 세기
        _IndirectStrength ("Indirect Strength", Range(0, 2)) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"     = "Opaque"
            "Queue"          = "Geometry"
        }

        // =============================================================
        //  Forward Pass
        // =============================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target   3.0

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);    SAMPLER(sampler_NormalMap);
            TEXTURE2D(_MetallicMap);  SAMPLER(sampler_MetallicMap);
            TEXTURE2D(_RoughnessMap); SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_AOMap);        SAMPLER(sampler_AOMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float4 _MetallicMap_ST;
                float4 _RoughnessMap_ST;
                float4 _AOMap_ST;
                float4 _BaseColor;
                float  _NormalStrength;
                float  _Metallic;
                float  _Roughness;
                float  _IndirectStrength;
            CBUFFER_END

            // =========================================================
            //  D : Trowbridge-Reitz GGX   (슬라이드 p.40)
            //
            //      NDF = a2 / ( PI * ( (n·h)^2 * (a2 - 1) + 1 )^2 )
            //      a   = roughness^2
            //
            //  microfacet 의 법선이 half vector 에 얼마나 몰려 있는지를
            //  나타낸다. roughness 가 작을수록 좁고 날카로운 하이라이트.
            // =========================================================
            float PBR_D_GGX(float NdotH, float roughness)
            {
                float a  = roughness * roughness;   // α
                float a2 = a * a;
                float t  = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                return a2 / (PI * t * t + 1e-7);
            }

            // =========================================================
            //  F : Fresnel-Schlick   (슬라이드 p.42)
            //
            //      F = F0 + (1 - F0) * (1 - cosTheta)^5
            //
            //  F0 : 정면에서 볼 때의 기본 반사율.
            //       비금속은 0.04 로 거의 일정하고, 금속은 base map 색 자체가
            //       F0 가 된다. (p.47 의 metallic workflow)
            // =========================================================
            float3 PBR_F_Schlick(float cosTheta, float3 F0)
            {
                return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
            }

            // roughness 를 고려한 변형. 간접광(환경 반사)에 쓴다.
            float3 PBR_F_SchlickRoughness(float cosTheta, float3 F0, float roughness)
            {
                float3 r = max(1.0 - roughness, F0);
                return F0 + (r - F0) * pow(1.0 - cosTheta, 5.0);
            }

            // =========================================================
            //  G : Schlick-GGX + Smith   (슬라이드 p.44)
            //
            //      PBR_G_SchlickGGX(n,v,k) = (n·v) / ( (n·v)(1-k) + k )
            //      k = (α + 1)^2 / 8      (직접광)
            //      k = α / 2              (간접광 / IBL)
            //
            //  거친 표면에서 microfacet 끼리 서로 가려(self-shadowing,
            //  masking) 잃는 에너지의 통계적 비율이다.
            //  시선 쪽과 광원 쪽 두 번 곱하는 것이 Smith 방식.
            // =========================================================
            float PBR_G_SchlickGGX(float NdotX, float k)
            {
                return NdotX / (NdotX * (1.0 - k) + k + 1e-7);
            }

            float PBR_G_Smith(float NdotV, float NdotL, float roughness)
            {
                float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
                return PBR_G_SchlickGGX(NdotV, k) * PBR_G_SchlickGGX(NdotL, k);
            }

            // =========================================================
            //  하나의 광원에 대한 Cook-Torrance (p.37, p.38)
            // =========================================================
            float3 PBR_ShadeLight(Light light, float3 N, float3 V, float3 albedo,
                              float metallic, float roughness, float3 F0)
            {
                float3 L = normalize(light.direction);
                float3 H = normalize(L + V);

                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V)) + 1e-4;
                float NdotH = saturate(dot(N, H));
                float HdotV = saturate(dot(H, V));

                // ---- specular : D F G / (4 (wo·n)(wi·n)) ----
                float  D = PBR_D_GGX(NdotH, roughness);
                float  G = PBR_G_Smith(NdotV, NdotL, roughness);
                float3 F = PBR_F_Schlick(HdotV, F0);

                float3 specular = (D * G * F) / (4.0 * NdotV * NdotL + 1e-4);

                // ---- diffuse : Kd * c / PI ----
                // Ks 는 곧 F 다. 에너지 보존을 위해 Kd = 1 - Ks.
                // 금속은 흡수된 빛이 diffuse 로 나오지 않으므로 (1-metallic) 을 곱한다.
                float3 kS = F;
                float3 kD = (1.0 - kS) * (1.0 - metallic);
                float3 diffuse = kD * albedo / PI;

                float3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);

                return (diffuse + specular) * radiance * NdotL;
            }

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float3 tangentWS   : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float  fogFactor   : TEXCOORD5;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                VertexPositionInputs posIn = GetVertexPositionInputs(IN.positionOS.xyz);

                float3 N = TransformObjectToWorldNormal(IN.normalOS);
                float3 T = normalize(TransformObjectToWorldDir(IN.tangentOS.xyz));
                float  s = IN.tangentOS.w * GetOddNegativeScale();
                float3 B = cross(N, T) * s;

                OUT.positionHCS = posIn.positionCS;
                OUT.positionWS  = posIn.positionWS;
                OUT.normalWS    = N;
                OUT.tangentWS   = T;
                OUT.bitangentWS = B;
                OUT.uv          = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.fogFactor   = ComputeFogFactor(posIn.positionCS.z);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                // ---- 표면 파라미터를 텍스처에서 읽는다 (p.46, p.47) ----
                float3 albedo    = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                float  metallic  = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, IN.uv).r * _Metallic;
                float  roughness = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, IN.uv).r * _Roughness;
                float  ao        = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, IN.uv).r;

                // 완전히 매끈하면 하이라이트가 한 점으로 수렴해 사라지므로 하한을 둔다
                roughness = clamp(roughness, 0.04, 1.0);

                // ---- normal mapping ----
                float3 nTS = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv), _NormalStrength);

                float3 Nv = normalize(IN.normalWS);
                float3 Tv = normalize(IN.tangentWS - dot(IN.tangentWS, Nv) * Nv);
                float3 Bv = normalize(IN.bitangentWS);
                float3x3 TBN = float3x3(Tv, Bv, Nv);          // tangent -> world

                float3 N = normalize(mul(nTS, TBN));
                float3 V = GetWorldSpaceNormalizeViewDir(IN.positionWS);

                // ---- F0 : metallic workflow (p.47) ----
                // 비금속은 0.04, 금속은 base map 색이 곧 반사색
                float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

                // =====================================================
                //  직접광 (p.34, p.36)
                // =====================================================
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                float3 Lo = PBR_ShadeLight(mainLight, N, V, albedo, metallic, roughness, F0);

            #ifdef _ADDITIONAL_LIGHTS
                uint count = GetAdditionalLightsCount();
                for (uint i = 0u; i < count; ++i)
                {
                    Light addLight = GetAdditionalLight(i, IN.positionWS);
                    Lo += PBR_ShadeLight(addLight, N, V, albedo, metallic, roughness, F0);
                }
            #endif

                // =====================================================
                //  간접광 (p.34, p.36)
                //   diffuse  : spherical harmonics (ambient probe)
                //   specular : skybox 가 만든 환경 큐브맵 (p.51)
                // =====================================================
                float NdotV = saturate(dot(N, V));

                float3 F_ibl  = PBR_F_SchlickRoughness(NdotV, F0, roughness);
                float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);

                // Irradiance map 역할 (p.36)
                float3 indirectDiffuse = SampleSH(N) * albedo * kD_ibl;

                // Prefiltered environment map 역할 (p.36).
                // roughness 가 클수록 흐린 밉 레벨을 집어 거친 반사를 흉내낸다.
                float3 R   = reflect(-V, N);
                float  mip = PerceptualRoughnessToMipmapLevel(roughness);
                half4  enc = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip);
                float3 env = DecodeHDREnvironment(enc, unity_SpecCube0_HDR);

                float3 indirectSpecular = env * F_ibl;

                float3 ambient = (indirectDiffuse + indirectSpecular) * ao * _IndirectStrength;

                // =====================================================
                float3 color = Lo + ambient;
                color = MixFog(color, IN.fogFactor);

                return half4(color, 1.0);
            }
            ENDHLSL
        }

        // =============================================================
        //  그림자를 드리우기 위한 패스
        // =============================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   shadowVert
            #pragma fragment shadowFrag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float4 _MetallicMap_ST;
                float4 _RoughnessMap_ST;
                float4 _AOMap_ST;
                float4 _BaseColor;
                float  _NormalStrength;
                float  _Metallic;
                float  _Roughness;
                float  _IndirectStrength;
            CBUFFER_END

            float3 _LightDirection;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct ShadowVaryings
            {
                float4 positionHCS : SV_POSITION;
            };

            ShadowVaryings shadowVert(ShadowAttributes IN)
            {
                ShadowVaryings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);

                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

                // 그림자 여드름(acne)을 줄이기 위한 normal bias
                float4 positionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, _LightDirection));

            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif

                OUT.positionHCS = positionCS;
                return OUT;
            }

            half4 shadowFrag(ShadowVaryings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}
