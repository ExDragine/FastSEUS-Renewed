#version 120


#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.


varying vec4 color;
varying vec4 texcoord;

uniform vec3 sunPosition;
uniform vec3 moonPosition;



uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

uniform vec2 taaJitter;

void main() {
	gl_Position = ftransform();

	//Translate vertices by local offset so sky behaves as if it's very very far away
	vec4 worldPosition = gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex;

	vec3 localOffset = (gbufferModelViewInverse * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// worldPosition.xyz *= 4.0;

	worldPosition.xyz += localOffset.xyz;

	gl_Position = gl_ProjectionMatrix * gbufferModelView * worldPosition;


	//Temporal jitter
#ifdef TAA_ENABLED
	gl_Position.xyz /= gl_Position.w;
	gl_Position.xy += taaJitter;
	gl_Position.xyz *= gl_Position.w;
#endif
	
	color = gl_Color;
	
	texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;

	gl_FogFragCoord = gl_Position.z;

	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

	vec3 viewVec = normalize(viewPos.xyz);

	if (dot(viewVec, sunPosition) > 0.0)
	{
		//gl_Position.xyz += 10000.0;
	}
}