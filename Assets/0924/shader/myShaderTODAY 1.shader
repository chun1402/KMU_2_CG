Shader "Unlit/myShader"
{
    Properties
    {
        _BaseColor ("Base color", Color) = (1,1,1,1)
        _Shininess ("Shininess (p)", Range(1, 256)) = 32   //Blinn-Phong은 p를 Phong보다 크게 (약 2~4배)
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

            half4 _BaseColor; //data type = half4(color)
            float _Shininess; //Property로 받은 p값

            //Unity mesh infor
            struct appdata{                     // app으로 부터 받는 기하 정보

                float4 positionOS : POSITION;   // local 혹은 오브젝트 좌표값 (os : Object Spacn) : why vec4? (동차좌표계이기때문)
                float3 normal : NORMAL;         //position 당 normal
            };

            struct interpolator{                    //fragment Shader로 보낼 데이터
                float4 positionHCS : SV_POSITION;   //opengl에서 gl_Position에 해당, 반드시 설정해야하는 clip 좌표값
                float3 normal : TEXCOORD0;          //world noraml값
                float3 positionWS : TEXCOORD1;      //world position 값
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

                return i;
            }

            //라이트 하나에 대한 Blinn-Phong 계산 (main light / additional light 공용)
            //light  : GetMainLight() 또는 GetAdditionalLight()로 얻은 광원
            //N      : 정규화된 world normal
            //V      : 정규화된 view vector
            float3 BlinnPhong(Light light, float3 N, float3 V)
            {
                //거리 감쇠 * 그림자 감쇠 (main light는 보통 1, point light는 거리에 따라 줄어듦)
                float3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                //vertor L계산 (main light와 동일한 규칙 적용)
                float3 L = normalize(light.direction);

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
                float3 specular = _BaseColor.rgb * lightColor * pow(max(dot(N, H), 0), _Shininess);

                //Phong = ambient + diffuse + specular
                return ambient + diffuse + specular;
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
                float3 phong1 = BlinnPhong(mainLight, N, V);

                //2. 두 번째 라이트 (Point Light)에 대한 계산
                //GetAdditionalLight(index, positionWS) : 픽셀 위치의 감쇠까지 적용된 광원 정보
                //phong2 = ambient2 + diffuse2 + specular2
                float3 phong2 = 0;

                int count = GetAdditionalLightsCount();
                for (int idx = 0; idx < count; ++idx) {
                    Light addLight = GetAdditionalLight(idx, i.positionWS);
                    phong2 += BlinnPhong(addLight, N, V);
                }

                //최종 : phong = phong1 + phong2
                float3 finalColor = phong1 + phong2;
                float4 c = float4(finalColor, 1);
                return c;
            }


            ENDHLSL
        } // Pass

    } // SubShader

} // Shader
