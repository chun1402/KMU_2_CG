Shader "Unlit/myShader"
{
    Properties
    {
        _BaseColor ("Base color", Color) = (1,1,1,1)
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

            // URP 기본 함수 (TransformObjectToHClip 등) 제공
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            half4 _BaseColor; //data type = half4(color)

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

            //라스터라이져 수행 -> fragment(pixel) 결정

            float4 frag(interpolator i ) :SV_TARGET {              // SV_TARGET : opengl에서 vec4 fragColor에 해당(SV_TARGET), 즉, 픽셀의 색상
                
                // pong 계산

                //1. diffuse 계산
                
                Light light = GetMainLight();
                //vertor L계산
                float3 L = normalize(-light.direction);
                float3 N = normalize(i.normal);

                //diffuse = K * I * dot(L,N)
                float3 diffuse = _BaseColor.rgb * light.color * max(dot(L, N), 0);

                
                //2. ambient 계산
                //ambient = Ka * Ia;        diffuse의 10%-30%
                float3 ambient = _BaseColor.rgb * light.color * 0.1;

                //3. specular 계산
                //specular를 world좌표에서 계산
                //specular = Is * (dot(R,V))^p
                //vertor V계산 : view vertor (world좌표 위치 -> 카메라 위치)
                
                float3 wdpos = i.positionWS;
                float3 campos = _WorldSpaceCameraPos;        //빌트인 카메라 위치 변수
                float3 V = normalize(campos - wdpos);

                float3 R = reflect(-L,N);
                float p = 16.0;                              // p의 승
                
                float3 specular = _BaseColor.rgb * light.color * pow(max(dot(R,V), 0), p);

                float3 finalColor = diffuse + ambient + specular;
                float4 c = float4(finalColor, 1);
                return c;
            }

            
            ENDHLSL
        } // Pass

    } // SubShader

} // Shader