Shader "Unlit/NormalMapShader"
{
    Properties
    {
        //메인텍스처임을 지정하는 속성 (optional)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        //[Normal] : 이 텍스처가 Normal map으로 import되지 않았으면 Inspector에서 경고를 띄워 줌
        //"bump" : 아무것도 안 넣었을 때 쓰이는 기본값 (평평한 normal)
        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}

        _NormalStrength("Normal Strength", Range(0, 1)) = 0   //0이면 normal map을 끈 것과 같음
        _Shininess("Shininess (p)", Range(1, 256)) = 128

        //(World) /(Tangent) 두 방법을 Inspector에서 바꿔가며 비교
        [KeywordEnum(World, Tangent)] _Space("Lighting Space", Float) = 0
    }

    SubShader
    {
        Tags {  "RenderType" = "Opaque"
                "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_local _SPACE_WORLD _SPACE_TANGENT
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            //샘플러, 텍스처, Offset/Tile 생성 (14페이지)
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;     //tiling and offset
                float4 _NormalMap_ST;
                float _NormalStrength;
                float _Shininess;
            CBUFFER_END

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;    //오브젝트(로컬) 좌표계에서의 tangent벡터
                                                //.xyz : UV의 U방향으로 따라가는 3차원 벡터
                                                //.w   : B의 방향을 결정하는 +1 혹은 -1 값
            };

            struct Interpolators
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 positionWS  : TEXCOORD1; //월드 공간에서의 position
                float3 T           : TEXCOORD2;
                float3 B           : TEXCOORD3;
                float3 N           : TEXCOORD4;
                //18페이지 구조체에는 normalWS도 같이 적혀 있는데, 그건 아래 N과 똑같은 값이라
                //보간기 슬롯만 낭비하므로 하나로 합침
            };

            //--------------------------------------------------------------------
            // Texture Space 구성
            // 실제 매핑이 fragment shader에서 이루어져야 하므로
            // T, B, N을 vertex shader에서 구한 후 넘겨 줌
            //--------------------------------------------------------------------
            Interpolators vert(appdata input)
            {
                Interpolators o;

                o.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                o.positionWS  = TransformObjectToWorld(input.positionOS.xyz);
                o.uv          = TRANSFORM_TEX(input.uv, _BaseMap);

                half tangentSign = input.tangentOS.w;

                //입력으로 받은 local normal을 world로 변환
                //normal은 scale까지 고려해야 해서 (A^-1)^T 를 사용하는 전용 함수를 씀 (17페이지)
                float3 N = TransformObjectToWorldNormal(input.normalOS);

                //입력으로 받은 tangent를 world로 변환 (이쪽은 단순 방향 변환이라 Dir 함수)
                float3 T = normalize(TransformObjectToWorldDir(input.tangentOS.xyz));

                //bitangent = Normal x Tangent, 방향은 tangentOS.w가 결정
                float3 B = cross(N, T) * tangentSign;

                o.N = N;
                o.T = T;
                o.B = B;

                return o;
            }

            //--------------------------------------------------------------------
            // 라이팅에 쓸 공간으로 world 벡터를 변환
            //  - World 방식  : 그대로 사용
            //  - Tangent 방식 : M(= world->tangent 행렬)을 곱해서 tangent space로
            //--------------------------------------------------------------------
            float3 ToShadingSpace(float3 vWorld, float3x3 M)
            {
            #ifdef _SPACE_TANGENT
                return normalize(mul(vWorld, M));
            #else
                return normalize(vWorld);
            #endif
            }

            //라이트 하나에 대한 Blinn-Phong 계산
            //N, V는 이미 라이팅 공간으로 맞춰진 상태로 들어옴
            void BlinnPhong(Light light, float3x3 M, float3 N, float3 V, float3 albedo,
                            out float3 diffuseAmbient, out float3 specular)
            {
                float3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                //URP의 light.direction은 이미 "표면 -> 광원" 방향이므로 마이너스를 붙이지 않음
                float3 L = ToShadingSpace(light.direction, M);

                //Basemap은 그대로 이용하고 normal을 normal map을 통해 계산 (21페이지)
                float3 diffuse = albedo * lightColor * max(dot(L, N), 0);
                float3 ambient = albedo * lightColor * 0.1;

                //하이라이트는 material 색상과 보통 상관없으므로 albedo를 곱하지 않음
                float3 H = normalize(L + V);
                specular = lightColor * pow(max(dot(N, H), 0), _Shininess);

                diffuseAmbient = diffuse + ambient;
            }

            float4 frag(Interpolators i) : SV_TARGET
            {
                //보간을 거치면서 길이가 틀어지므로 다시 정규화
                float3 T = normalize(i.T);
                float3 B = normalize(i.B);
                float3 Ngeom = normalize(i.N);

                //UnpackNormal : 텍스처의 [0,1] 색상값을 normal의 [-1,1] 범위로 되돌림 (19페이지)
                half3 tnormal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv));

                //xy를 키우면 울퉁불퉁함이 강해짐. 0이면 평평한 normal(0,0,1)이 됨
                tnormal.xy *= _NormalStrength;
                tnormal = normalize(tnormal);

                float4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                //HLSL의 float3x3(T,B,N)은 T,B,N이 "행"으로 들어감 (GLSL은 열) - 15페이지
                //그래서 mul(벡터, 행렬) 순서를 써야 함 - 16페이지
                float3 N;
                float3 V;
                float3x3 M;

            #ifdef _SPACE_TANGENT
                //방법2 : Lighting 계산 in Tangent space
                //각 row가 unit vector일 때는 inverse = transpose
                M = transpose(float3x3(T, B, Ngeom));   //world -> tangent

                //normal은 normal map에서 얻은 그대로 사용 : 이미 tangent space
                N = normalize(tnormal);

                //라이팅을 위해 필요한 모든 벡터들을 tangent space로 변경
                V = ToShadingSpace(_WorldSpaceCameraPos - i.positionWS, M);
            #else
                //방법1 : Lighting 계산 in World space (추천)
                M = float3x3(T, B, Ngeom);              //tangent -> world

                //normal map에서 받은 normal은 tangent space에서 만들었기 때문에 world space로 변경
                N = normalize(mul(tnormal, M));

                //L, V, H는 모두 world space 로 사용함
                V = normalize(_WorldSpaceCameraPos - i.positionWS);
            #endif

                Light mainLight = GetMainLight();
                float3 da1, sp1;
                BlinnPhong(mainLight, M, N, V, albedo.rgb, da1, sp1);

                float3 da2 = 0;
                float3 sp2 = 0;

                int count = GetAdditionalLightsCount();
                for (int idx = 0; idx < count; ++idx)
                {
                    Light addLight = GetAdditionalLight(idx, i.positionWS);
                    float3 da, sp;
                    BlinnPhong(addLight, M, N, V, albedo.rgb, da, sp);
                    da2 += da;
                    sp2 += sp;
                }

                float3 final = (da1 + da2) + (sp1 + sp2);

                return float4(final, 1);
            }

            ENDHLSL
        } // Pass

    } // SubShader

} // Shader
