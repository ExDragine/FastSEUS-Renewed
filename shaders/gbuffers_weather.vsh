#version 120


#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.


varying vec4 color;
varying vec4 texcoord;
varying vec4 lmcoord;

uniform vec2 taaJitter;

void main() {
	gl_Position = ftransform();
	//gl_Position.z = 0.0f;

	//Temporal jitter
#ifdef TAA_ENABLED
	gl_Position.xyz /= gl_Position.w;
	gl_Position.xy += taaJitter;
	gl_Position.xyz *= gl_Position.w;
#endif

	color = gl_Color;
	
	texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;

	lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}