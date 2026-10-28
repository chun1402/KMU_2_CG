Shader "Unlit/myShader"
{
    Properties
    {
        _BaseColor ("Base color", Color) = (1,1,1,1)
        _Shininess ("Shininess (p)", Range(1, 256)) = 32   //Blinn-Phong은 p를 Phong보다 크게 (약 2~4배)

        //[MainTexture] : 이 material의 주 텍스처라고 명시 -> Inspector에 preview로 나타남
        //("_MainTex"라는 이름을 쓰면 자동으로 Main texture가 됨)
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
    }

    SubShader
    {
        // URP에서 사용하려면 RenderPipeline 태그를 UniversalPipeline으로 지정
        Tags {  "RenderType" = "Opaque"
                "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            //추가 라이트(Additional Light)를 픽셀 단위로 쓰려면 이 키워드가 필요
            //이게 없으면 GetAdditionalLightsCount()가 항상 0을 반환함
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS

            // URP 기본 함수 (TransformObjectToHClip 등) 제공
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            //텍스처 매핑에 필요한 3가지 : 텍스처 / 샘플러 / uv 좌표
            TEXTURE2D(_BaseMap);        //텍스처 선언 : 픽셀 정보를 가진 이미지 데이터
            SAMPLER(sampler_BaseMap);   //샘플러 선언 : 필터링, wrapping, mipmap 제어 (이미지를 읽는 방법)

            //SRP Batcher를 위해 material property들은 같은 CBUFFER에 모아서 선언
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor; //data type = half4(color)
                float _Shininess; //Property로 받은 p값
                float4 _BaseMap_ST; //유니티가 자동으로 만들어주는 vector로서 tiling(xy)과 offset(zw) 정보를 저장
            CBUFFER_END

            //Unity mesh infor
            struct appdata{                     // app으로 부터 받는 기하 정보

                float4 positionOS : POSITION;   // local 혹은 오브젝트 좌표값 (os : Object Spacn) : why vec4? (동차좌표계이기때문)
                float3 normal : NORMAL;         //position 당 normal
                float2 uv : TEXCOORD0;          //mesh에 저장된 uv 좌표 (텍스처 매핑용)
            };

            struct interpolator{                    //fragment Shader로 보낼 데이터
                float4 positionHCS : SV_POSITION;   //opengl에서 gl_Position에 해당, 반드시 설정해야하는 clip 좌표값
                float3 normal : TEXCOORD0;          //world noraml값
                float3 positionWS : TEXCOORD1;      //world position 값
                float2 uv : TEXCOORD2;              //fragment로 보간되어 넘어갈 uv 좌표
            };

            interpolator vert(appdata input){
                interpolator i;
                //input.positionOS : local(object) -> world -> camera -> clip
                //local(object) -> clip
                //TransformObjectToHClip : vec3 받아서 vec4 반환
                i.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                //TransformObjectToWorldNormal : 오브젝트 noraml 받아서 world좌표 변환
                i.normal = TransformObjectToWorldNormal(input.normal);
                //TransformObjectToWorld : 오브젝트 좌표 -> 월드 좌표로 변환
                i.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                //uv는 변환 없이 그대로 전달 (tiling/offset은 fragment에서 적용)
                i.uv = input.uv;

                return i;
            }

            //라이트 하나에 대한 Blinn-Phong 계산 (main light / additional light 공용)
            //텍스처와 곱해지는 (diffuse + ambient)와, 곱해지지 않는 specular를 따로 돌려줌
            //light           : GetMainLight() 또는 GetAdditionalLight()로 얻은 광원
            //N               : 정규화된 world normal
            //V               : 정규화된 view vector
            //diffuseAmbient  : (out) diffuse + ambient
            //specular        : (out) specular
            void BlinnPhong(Light light, float3 N, float3 V, out float3 diffuseAmbient, out float3 specular)
            {
                //거리 감쇠 * 그림자 감쇠 (main light는 보통 1, point light는 거리에 따라 줄어듦)
                float3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                //vertor L계산 (main light와 동일한 규칙 적용)
                float3 L = normalize(-light.direction);

                //1. diffuse 계산
                //diffuse = K * I * dot(L,N)
                float3 diffuse = _BaseColor.rgb * lightColor * max(dot(L, N), 0);

                //2. ambient 계산
                //ambient = Ka * Ia;        diffuse의 10%-30%
                float3 ambient = _BaseColor.rgb * lightColor * 0.1;

                //3. specular 계산 (Blinn-Phong)
                //복잡한 R 대신 half vector H를 이용
                //H = (L + V) / |L + V|
                float3 H = normalize(L + V);

                //specular = Is * pow(max(dot(N,H), 0), shininess)
                specular = _BaseColor.rgb * lightColor * pow(max(dot(N, H), 0), _Shininess);

                diffuseAmbient = diffuse + ambient;
            }

            //라스터라이져 수행 -> fragment(pixel) 결정

            float4 frag(interpolator i ) :SV_TARGET {              // SV_TARGET : opengl에서 vec4 fragColor에 해당(SV_TARGET), 즉, 픽셀의 색상

                // blinn-pong 계산

                float3 N = normalize(i.normal);

                //vertor V계산 : view vertor (world좌표 위치 -> 카메라 위치)
                float3 wdpos = i.positionWS;
                float3 campos = _WorldSpaceCameraPos;        //빌트인 카메라 위치 변수
                float3 V = normalize(campos - wdpos);

                //1. Main Light (디폴트 Directional Light)에 대한 계산
                //phong1 = ambient1 + diffuse1 + specular1
                Light mainLight = GetMainLight();
                float3 da1, sp1;
                BlinnPhong(mainLight, N, V, da1, sp1);

                //2. 두 번째 라이트 (Point Light)에 대한 계산
                //GetAdditionalLight(index, positionWS) : 픽셀 위치의 감쇠까지 적용된 광원 정보
                //phong2 = ambient2 + diffuse2 + specular2
                float3 da2 = 0;
                float3 sp2 = 0;

                int count = GetAdditionalLightsCount();
                for (int idx = 0; idx < count; ++idx) {
                    Light addLight = GetAdditionalLight(idx, i.positionWS);
                    float3 da, sp;
                    BlinnPhong(addLight, N, V, da, sp);
                    da2 += da;
                    sp2 += sp;
                }

                //최종 : phong = phong1 + phong2
                float3 diffuseAmbient = da1 + da2;
                float3 specular = sp1 + sp2;

                //3. 텍스처 샘플링
                //TRANSFORM_TEX : uv * _BaseMap_ST.xy + _BaseMap_ST.zw (tiling과 offset 적용)
                float2 uv = TRANSFORM_TEX(i.uv, _BaseMap);
                //SAMPLE_TEXTURE2D : 텍스처 + 샘플러 + uv를 이용해 해당 위치의 색상을 읽어옴
                float4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);

                //4. Phong 색상과 텍스처 색상을 결합
                //Phong = (diffuse + Ambient) * (texColor.xyz) + specular;
                //하이라이트는 텍스처 색상과 상관없으므로 specular는 곱하지 않고 더하기만 함
                float3 finalColor = diffuseAmbient * texColor.xyz + specular;
                float4 c = float4(finalColor, 1);
                return c;
            }


            ENDHLSL
        } // Pass

    } // SubShader

} // Shader
