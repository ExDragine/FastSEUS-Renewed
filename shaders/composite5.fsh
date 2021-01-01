#version 120

/*
 _______ _________ _______  _______  _
(  ____ \\__   __/(  ___  )(  ____ )( )
| (    \/   ) (   | (   ) || (    )|| |
| (_____    | |   | |   | || (____)|| |
(_____  )   | |   | |   | ||  _____)| |
      ) |   | |   | |   | || (      (_)
/\____) |   | |   | (___) || )       _
\_______)   )_(   (_______)|/       (_)

Do not modify this code until you have read the LICENSE.txt contained in the root directory of this shaderpack!

*/



#include "Common.inc"


/////////////////////////CONFIGURABLE VARIABLES////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////CONFIGURABLE VARIABLES////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.

#define BLOOM_RESOLUTION_REDUCTION 16.0 // Render resolution reduction of Bloom. 1.0 = Original. Set higher for faster but blurrier Bloom. [1.0 4.0 9.0 16.0 25.0]

/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////

/* DRAWBUFFERS:2 */


const bool gaux3MipmapEnabled = true;

uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gdepthtex;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux3;
uniform sampler2D noisetex;

varying vec4 texcoord;

uniform int worldTime;

uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;
uniform float wetness;
uniform float aspectRatio;
uniform float frameTimeCounter;
uniform sampler2D shadowcolor;
uniform sampler2D shadowcolor1;
uniform sampler2D shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform int   isEyeInWater;
uniform float eyeAltitude;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform int   fogMode;

uniform int frameCounter;

uniform vec2 taaJitter;

vec3 GetColor(vec2 coord)
{
	vec3 color = GammaToLinear(texture2D(gaux3, coord).rgb);

	return color;
}

vec3 GrabBlurH(vec2 coord, const float zoom, const float octave, const vec2 offset)
{
	float scale = exp2(octave);

	coord += offset;
	coord *= scale;

	vec2 texel = scale / vec2(viewWidth, viewHeight);
	vec2 lowBound  = 0.0 - 10.0 * texel * zoom;
	vec2 highBound = 1.0 + 10.0 * texel * zoom;

	if (coord.x < lowBound.x || coord.x > highBound.x || coord.y < lowBound.y || coord.y > highBound.y)
	{
		return vec3(0.0);
	}

	vec3 color = vec3(0.0);

	float weights[5] = float[5](0.27343750, 0.21875000, 0.10937500, 0.03125000, 0.00390625);
	float offsets[5] = float[5](0.00000000, 1.00000000, 2.00000000, 3.00000000, 4.00000000);

	color += GetColor(saturate(coord)) * weights[0];

	color += GetColor(saturate(coord + vec2(offsets[1] * texel.x, 0.0))) * weights[1];
	color += GetColor(saturate(coord - vec2(offsets[1] * texel.x, 0.0))) * weights[1];

	color += GetColor(saturate(coord + vec2(offsets[2] * texel.x, 0.0))) * weights[2];
	color += GetColor(saturate(coord - vec2(offsets[2] * texel.x, 0.0))) * weights[2];

	color += GetColor(saturate(coord + vec2(offsets[3] * texel.x, 0.0))) * weights[3];
	color += GetColor(saturate(coord - vec2(offsets[3] * texel.x, 0.0))) * weights[3];

	color += GetColor(saturate(coord + vec2(offsets[4] * texel.x, 0.0))) * weights[4];
	color += GetColor(saturate(coord - vec2(offsets[4] * texel.x, 0.0))) * weights[4];

	return color;
}

vec2 CalcOffset(float octave, const float zoom)
{
    vec2 offset = vec2(0.0);
    
    vec2 padding = vec2(30.0) / vec2(viewWidth, viewHeight);
    
    offset.x = -min(1.0, floor(octave / 3.0)) * (0.25 + padding.x);
    
    offset.y = -(1.0 - (1.0 / exp2(octave))) - padding.y * octave;

	offset.y += min(1.0, floor(octave / 3.0)) * 0.35;
    
 	return offset;   
}

/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void main() {
	vec3 color = vec3(0.0);

	float zoom = 1.0f / BLOOM_RESOLUTION_REDUCTION;
	float ava = 2.0 - step(0.0, zoom) - step(zoom, 1.0);
	zoom = ava + (1 - ava) * zoom;

	vec2 jitteredCoord = texcoord.st;
	//jitteredCoord += taaJitter * 0.5f;

	vec2 bloomCoord = jitteredCoord.st / sqrt(zoom);


	if (bloomCoord.s <= 1.0f && bloomCoord.s >= 0.0f
	 && bloomCoord.t <= 1.0f && bloomCoord.t >= 0.0f)
	{
		zoom = sqrt(zoom);

		color += GrabBlurH(bloomCoord.st, zoom, 1.0, vec2(0.0, 0.0));
		color += GrabBlurH(bloomCoord.st, zoom, 2.0, CalcOffset(1, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 3.0, CalcOffset(2, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 4.0, CalcOffset(3, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 5.0, CalcOffset(4, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 6.0, CalcOffset(5, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 7.0, CalcOffset(6, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 8.0, CalcOffset(7, zoom));
		color += GrabBlurH(bloomCoord.st, zoom, 9.0, CalcOffset(8, zoom));
	}


	color = LinearToGamma(color);
	gl_FragData[0] = vec4(color.rgb, 1.0f);

}
