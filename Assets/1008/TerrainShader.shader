Shader "Unlit/TerrainShader"
{
    Properties
    {
        _BaseColor ("Base color", Color) = (1,1,1,1)
        _Shininess ("Shininess (p)", Range(1, 256)) = 32
        _SpecIntensity ("Specular Intensity", Range(0, 1)) = 0.0 // 0이면 반사광이 완전히 사라집니다.
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}

        //Terrain 관련 Property (30페이지)
        _NoiseScale ("Noise Scale", Range(0.01, 2)) = 0.2   //작은 값 : 넓고 완만한 산 / 큰 값 : 울퉁불퉁한 지형
        _Height ("Height", Range(0, 20)) = 3                //작은 값 : 거의 평면 / 큰 값 : 높은 산악 지형

        //27페이지 비교용. 0 = u를 f 그대로 / 1 = smoothstep 형태
        _SmoothU ("Smooth Interp (0=f, 1=smooth)", Range(0, 1)) = 1
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

            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _Shininess;
                float _SpecIntensity; // CBUFFER에 추가
                float4 _BaseMap_ST;
                float _NoiseScale;
                float _Height;
                float _SmoothU;
            CBUFFER_END

            struct addData
            {
                float4 positionOS : POSITION;   //local pos
                float3 normals : NORMAL;        //local normal (평면이라 전부 (0,1,0) -> 아래에서 다시 계산함)
                float2 uv : TEXCOORD0;          //local uv
            };

            struct interpolator
            {
                float4 positionHCS : SV_POSITION;   //vertex clip coordinate
                float3 positionWS : TEXCOORD0;      //vertex world coordinate
                float3 normal : TEXCOORD1;          //TransformObjectToWorldNormal()을 통해 변경
                float2 uv : TEXCOORD2;
            };

            //--------------------------------------------------------------------
            // hash21 : p를 넣으면 항상 같은 pseudo-random값을 반환 (25페이지)
            // 같은 좌표면 늘 같은 값이 나와야 지형이 매 프레임 흔들리지 않음
            //--------------------------------------------------------------------
            float hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            //--------------------------------------------------------------------
            // noise2D : value noise (24~27페이지)
            //  1. 2차원 vertex 위치 p 입력
            //  2. 현재 grid cell 찾기 : floor(p)
            //  3. cell의 네 꼭지점에 pseudo-random값 생성
            //  4. 현재 위치의 fractional part : frac(p)
            //  5. 네 값을 부드럽게 interpolation
            //  6. noise값 반환
            //--------------------------------------------------------------------
            float noise2D(float2 p)
            {
                float2 i = floor(p);    // 어느 grid cell인가?
                float2 f = frac(p);     // cell 내부에서 어디인가?

                //네 corner에서 random 값을 얻음
                float a = hash21(i);
                float b = hash21(i + float2(1, 0));
                float c = hash21(i + float2(0, 1));
                float d = hash21(i + float2(1, 1));

                //interpolation parameter를 부드럽게 만듦
                //f 그대로 쓰면 cell 경계에서 기울기가 꺾여 격자 무늬가 보임
                //f*f*(3-2f)는 smoothstep 형태라 경계에서 변화가 훨씬 부드러움
                float2 u = lerp(f, f * f * (3.0 - 2.0 * f), _SmoothU);

                //bilinear interpolation 수행 (26페이지)
                float bottom = lerp(a, b, u.x);
                float top    = lerp(c, d, u.x);
                return lerp(bottom, top, u.y);
            }

            //--------------------------------------------------------------------
            // Height : noise가 추가된 최종 지형의 높이 값 y
            //          (_NoiseScale 및 _Height 값이 반영된 최종 값)
            // xz : object space의 (x, z) 좌표
            //--------------------------------------------------------------------
            float Height(float2 xz)
            {
                return noise2D(xz * _NoiseScale) * _Height;
            }

            interpolator vert(addData input)
            {
                interpolator o;

                float3 positionOS = input.positionOS.xyz;
                float2 p = positionOS.xz;

                //model 좌표 값 변경 (29페이지)
                float h = Height(p);
                positionOS.y += h;

                //--- normal 변경 (31페이지) -------------------------------------
                //mesh의 이웃 정점을 찾는 것이 아니라,
                //현재 위치 주변의 높이를 noise 함수로 다시 평가해서 기울기를 구함
                const float eps = 0.01;     //아주 작은값

                float hx = Height(p + float2(eps, 0));
                float hz = Height(p + float2(0, eps));

                //x방향, z방향으로 eps만큼 갔을 때의 접선 벡터 두 개
                float3 dx = float3(eps, hx - h, 0);
                float3 dz = float3(0, hz - h, eps);

                //두 접선에 모두 수직인 벡터가 normal
                float3 normalOS = normalize(cross(dz, dx));

                o.positionHCS = TransformObjectToHClip(positionOS);
                o.positionWS  = TransformObjectToWorld(positionOS);
                o.normal      = TransformObjectToWorldNormal(normalOS);
                o.uv          = TRANSFORM_TEX(input.uv, _BaseMap);

                return o;
            }

            //라이트 하나에 대한 Blinn-Phong 계산 (main light / additional light 공용)
            void BlinnPhong(Light light, float3 N, float3 V, out float3 diffuseAmbient, out float3 specular)
            {
                float3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                //URP의 light.direction은 이미 "표면 -> 광원" 방향이므로 마이너스를 붙이지 않음
                float3 L = normalize(light.direction);

                //diffuse = K * I * dot(L,N)
                float3 diffuse = _BaseColor.rgb * lightColor * max(dot(L, N), 0);

                //ambient = Ka * Ia
                float3 ambient = _BaseColor.rgb * lightColor * 0.1;

                //specular : 복잡한 R 대신 half vector H를 이용 (Blinn-Phong)
                float3 H = normalize(L + V);
                specular = _BaseColor.rgb * lightColor * pow(max(dot(N, H), 0), _Shininess);

                diffuseAmbient = diffuse + ambient;
            }

            float4 frag(interpolator i) : SV_TARGET
            {
                //blinn-phong을 통해 렌더링 (33페이지)
                float3 N = normalize(i.normal);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);

                Light mainLight = GetMainLight();
                float3 da1, sp1;
                BlinnPhong(mainLight, N, V, da1, sp1);

                float3 da2 = 0;
                float3 sp2 = 0;

                int count = GetAdditionalLightsCount();
                for (int idx = 0; idx < count; ++idx)
                {
                    Light addLight = GetAdditionalLight(idx, i.positionWS);
                    float3 da, sp;
                    BlinnPhong(addLight, N, V, da, sp);
                    da2 += da;
                    sp2 += sp;
                }

                float4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                // 연산 수정 : 스페큘러 값들(sp1, sp2)에 사용자가 조절 가능한 _SpecIntensity를 곱해줍니다.
                float3 finalColor = (da1 + da2) * texColor.xyz + (sp1 + sp2) * _SpecIntensity;

                return float4(finalColor, 1);
            }

            ENDHLSL
        } // Pass

    } // SubShader

} // Shader
