#version 120

varying vec4 color;

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

uniform vec2 taaJitter;

#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.



void main() {
	gl_Position = ftransform();

	//Temporal jitter
#ifdef TAA_ENABLED
	gl_Position.xyz /= gl_Position.w;
	gl_Position.xy += taaJitter;
	gl_Position.xyz *= gl_Position.w;
#endif
	
	color = gl_Color;

	gl_FogFragCoord = gl_Position.z;
}