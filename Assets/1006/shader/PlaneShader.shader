Shader "Unlit/PlaneShader"
{
    Properties
    {
        _BaseColor ("Base color", Color) = (1,1,1,1)
        _Shininess ("Shininess (p)", Range(1, 256)) = 32

        //추가1) 텍스처 매핑 + scrolling
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        _ScrollSpeed ("Scroll Speed (uv.x)", Range(-2, 2)) = 0.5

        //Wave 관련 Property
        _WaveAmplitude ("Wave Amplitude", Range(0, 2)) = 0.5     //A : 파동의 높이
        _WaveFrequency ("Wave Frequency", Range(0, 10)) = 2      //k : 파동의 촘촘한 정도
        _WaveSpeed ("Wave Speed", Range(-10, 10)) = 2            //w : 파동이 흘러가는 속도

        //추가2) z방향 파동의 세기. 0으로 두면 x방향 파동만 적용됨
        _ZWaveWeight ("Z Wave Weight", Range(0, 1)) = 0.5
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

            //z방향 파동(wave2)이 x방향 파동(wave1)과 얼마나 다르게 움직이는지를 정하는 상수
            //변위 식과 normal 식 양쪽에서 똑같이 쓰여야 하므로 한 곳에 모아 둠
            #define WAVE2_FREQ_SCALE  1.4
            #define WAVE2_SPEED_SCALE 0.7

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _Shininess;
                float4 _BaseMap_ST;
                float _ScrollSpeed;
                float _WaveAmplitude;
                float _WaveFrequency;
                float _WaveSpeed;
                float _ZWaveWeight;
            CBUFFER_END

            struct appdata
            {
                float4 positionOS : POSITION;   //local 좌표
                float3 normal : NORMAL;         //local normal (평면이므로 전부 (0,1,0))
                float2 uv : TEXCOORD0;
            };

            struct interpolator
            {
                float4 positionHCS : SV_POSITION;
                float3 normal : TEXCOORD0;      //world normal
                float3 positionWS : TEXCOORD1;  //world position
                float2 uv : TEXCOORD2;
            };

            //--------------------------------------------------------------------
            // 파동에 의한 y 변위와, 그 결과로 바뀐 normal을 함께 계산
            //
            //   y = A*sin(k*x + w*t) + (A*weight)*cos(1.4*k*z + 0.7*w*t)
            //
            // positionOS : (inout) y값이 파동만큼 올라감
            // normalOS   : (out) 변형된 표면의 normal
            //--------------------------------------------------------------------
            void ApplyWave(inout float3 positionOS, out float3 normalOS)
            {
                //phase = k*x - w*t (부호를 바꾸면 파동이 흘러가는 방향이 반대가 됨)
                float phase1 = positionOS.x * _WaveFrequency
                             + _Time.y * _WaveSpeed;

                //z방향 파동은 cos을 이용하고, 주파수와 속도를 살짝 다르게 줘서 패턴이 겹치지 않게 함
                float phase2 = positionOS.z * (_WaveFrequency * WAVE2_FREQ_SCALE)
                             + _Time.y * (_WaveSpeed * WAVE2_SPEED_SCALE);

                //파장을 직접 지정하고 싶다면
                //  float wavelength = 5.0;              x방향 5유닛마다 파형이 한 번 반복
                //  float k = TWO_PI / wavelength;       k = 2*pi / lambda
                //  float phase1 = positionOS.x * k + _Time.y * _WaveSpeed;

                float wave1 = sin(phase1);
                float wave2 = cos(phase2);

                //원 sin/cos 값은 [-1,1]이므로 amplitude를 곱해 높이를 조정
                positionOS.y += wave1 * _WaveAmplitude
                              + wave2 * _WaveAmplitude * _ZWaveWeight;

                //--- normal 계산 -------------------------------------------------
                //y값이 바뀌었기 때문에 normal도 바뀌어야 함 (원래는 무조건 (0,1,0))
                //표면의 기울기(gradient)를 미분으로 구한 뒤 그에 수직인 벡터를 normal로 사용
                float2 direction1 = float2(1, 0);   //wave1은 x방향으로 진행
                float2 direction2 = float2(0, 1);   //wave2는 z방향으로 진행

                // d/dx [ A*sin(phase1) ] = A*k*cos(phase1)
                float2 gradient1 = direction1
                                 * cos(phase1)
                                 * _WaveFrequency
                                 * _WaveAmplitude;

                // d/dz [ A*w*cos(phase2) ] = -A*w*(1.4k)*sin(phase2)
                float2 gradient2 = direction2
                                 * -sin(phase2)
                                 * (_WaveFrequency * WAVE2_FREQ_SCALE)
                                 * (_WaveAmplitude * _ZWaveWeight);

                float2 gradient = gradient1 + gradient2;

                //기울기가 (dy/dx, dy/dz)일 때 표면의 normal은 (-dy/dx, 1, -dy/dz)
                normalOS = normalize(float3(-gradient.x, 1.0, -gradient.y));
            }

            interpolator vert(appdata input)
            {
                interpolator i;

                //vertex shader 안에서 입력 vertex를 직접 변경
                float3 positionOS = input.positionOS.xyz;
                float3 normalOS;
                ApplyWave(positionOS, normalOS);

                //변형이 끝난 좌표를 가지고 평소대로 좌표계 변환
                i.positionHCS = TransformObjectToHClip(positionOS);
                i.positionWS = TransformObjectToWorld(positionOS);
                //입력 normal이 아니라 ApplyWave가 새로 계산한 normal을 사용
                i.normal = TransformObjectToWorldNormal(normalOS);

                //uv scrolling : 시간에 따라 offset을 밀어줌 (_Time.y = 게임 시작 후 경과 시간)
                float2 uv = TRANSFORM_TEX(input.uv, _BaseMap);
                uv.x += _Time.y * _ScrollSpeed;
                i.uv = uv;

                return i;
            }

            //라이트 하나에 대한 Blinn-Phong 계산 (main light / additional light 공용)
            void BlinnPhong(Light light, float3 N, float3 V, out float3 diffuseAmbient, out float3 specular)
            {
                float3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

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
                //기존에 했던 blinn-phong방법을 이용해 렌더링 수행
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

                float3 diffuseAmbient = da1 + da2;
                float3 specular = sp1 + sp2;

                //uv는 vertex shader에서 이미 scrolling까지 끝난 값
                float4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);

                //Phong = (diffuse + Ambient) * (texColor.xyz) + specular
                float3 finalColor = diffuseAmbient * texColor.xyz + specular;

                return float4(finalColor, 1);
            }

            ENDHLSL
        } // Pass

    } // SubShader

} // Shader
