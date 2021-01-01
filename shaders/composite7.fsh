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

#define MOTION_BLUR // Motion blur. Makes motion look blurry.
#define BLOOM_RESOLUTION_REDUCTION 16.0 // Render resolution reduction of Bloom. 1.0 = Original. Set higher for faster but blurrier Bloom. [1.0 4.0 9.0 16.0 25.0]

/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////

/* DRAWBUFFERS:467 */



uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D gdepthtex;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
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

uniform float frameTime;

vec3 GetColorTexture(vec2 coord)
{
	return GammaToLinear(texture2DLod(gaux3, coord, 0.0).rgb);
}

float GetDepth(vec2 coord)
{
	return texture2D(gdepthtex, coord).x;
}

void 	MotionBlur(inout vec3 color) {
	float depth = GetDepth(texcoord.st);

	if (depth < 0.7)
	{
		color.rgb = GetColorTexture(texcoord.st).rgb;
		return;
	}


	vec4 currentPosition = vec4(texcoord.x * 2.0f - 1.0f, texcoord.y * 2.0f - 1.0f, 2.0f * depth - 1.0f, 1.0f);

	vec4 fragposition = gbufferProjectionInverse * currentPosition;
	fragposition = gbufferModelViewInverse * fragposition;
	fragposition /= fragposition.w;
	fragposition.xyz += cameraPosition;

	vec4 previousPosition = fragposition;
	previousPosition.xyz -= previousCameraPosition;
	previousPosition = gbufferPreviousModelView * previousPosition;
	previousPosition = gbufferPreviousProjection * previousPosition;
	previousPosition /= previousPosition.w;

	vec2 velocity = (currentPosition - previousPosition).st * 0.1f * (1.0 / frameTime) * 0.012;
	float maxVelocity = 0.05f;
		 velocity = clamp(velocity, vec2(-maxVelocity), vec2(maxVelocity));

	//bool isHand = GetMaterialMask(texcoord.st, 5);
	//velocity *= 1.0f - float(isHand);

	int samples = 0;

	float dither = rand(texcoord.st).x;

	color.rgb = vec3(0.0f);

	{
		vec2 coord = texcoord.st + velocity * (dither - 0.5) * 0.5;
		float checker = step(0.0, coord.x) * step(coord.x, 1.0) * step(0.0, coord.y) * step(coord.y, 1.0);
		color += GetColorTexture(coord).rgb * checker;
		samples += int(checker);

		coord = texcoord.st + velocity * (dither + 0.5) * 0.5;
		checker = step(0.0, coord.x) * step(coord.x, 1.0) * step(0.0, coord.y) * step(coord.y, 1.0);
		color += GetColorTexture(coord).rgb * checker;
		samples += int(checker);
	}

	color.rgb /= samples;


}





vec4 cubic(float x)
{
    float x2 = x * x;
    float x3 = x2 * x;
    vec4 w;
    w.x =   -x3 + 3*x2 - 3*x + 1;
    w.y =  3*x3 - 6*x2       + 4;
    w.z = -3*x3 + 3*x2 + 3*x + 1;
    w.w =  x3;
    return w / 6.f;
}

vec4 BicubicTexture(in sampler2D tex, in vec2 coord, const float zoom)
{
	vec2 resolution = vec2(viewWidth, viewHeight);

	coord *= zoom * zoom;
	coord *= resolution;

	float fx = fract(coord.x);
    float fy = fract(coord.y);
    coord.x -= fx;
    coord.y -= fy;

    fx -= 0.5;
    fy -= 0.5;

    vec4 xcubic = cubic(fx);
    vec4 ycubic = cubic(fy);

    vec4 c = vec4(coord.x - 0.5, coord.x + 1.5, coord.y - 0.5, coord.y + 1.5);
    vec4 s = vec4(xcubic.x + xcubic.y, xcubic.z + xcubic.w, ycubic.x + ycubic.y, ycubic.z + ycubic.w);
    vec4 offset = c + vec4(xcubic.y, xcubic.w, ycubic.y, ycubic.w) / s;

    vec4 sample0 = texture2D(tex, vec2(offset.x, offset.z) / resolution);
    vec4 sample1 = texture2D(tex, vec2(offset.y, offset.z) / resolution);
    vec4 sample2 = texture2D(tex, vec2(offset.x, offset.w) / resolution);
    vec4 sample3 = texture2D(tex, vec2(offset.y, offset.w) / resolution);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix( mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec3 GetBloomTap(vec2 coord, const float zoom, const float octave, const vec2 offset)
{
	float scale = exp2(octave);

	coord /= scale;
	coord -= offset;

	return GammaToLinear(BicubicTexture(gaux1, coord, zoom).rgb);
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

vec3 GetBloom(vec2 coord, const float zoom)
{
	vec3 bloom = vec3(0.0);

	bloom += GetBloomTap(coord, zoom, 1.0, CalcOffset(0.0, zoom)) * 2.0;
	bloom += GetBloomTap(coord, zoom, 2.0, CalcOffset(1.0, zoom)) * 1.5;
	bloom += GetBloomTap(coord, zoom, 3.0, CalcOffset(2.0, zoom)) * 1.2;
	bloom += GetBloomTap(coord, zoom, 4.0, CalcOffset(3.0, zoom)) * 1.3;
	bloom += GetBloomTap(coord, zoom, 5.0, CalcOffset(4.0, zoom)) * 1.4;
	bloom += GetBloomTap(coord, zoom, 6.0, CalcOffset(5.0, zoom)) * 1.5;
	bloom += GetBloomTap(coord, zoom, 7.0, CalcOffset(6.0, zoom)) * 1.6;
	bloom += GetBloomTap(coord, zoom, 8.0, CalcOffset(7.0, zoom)) * 1.7;
	bloom += GetBloomTap(coord, zoom, 9.0, CalcOffset(8.0, zoom)) * 0.4;

	bloom /= 12.6;



	return bloom;
}

/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void main() {

	vec3 color = vec3(0.0);
	vec3 bloom = vec3(0.0);

	#ifdef MOTION_BLUR
		MotionBlur(color);
	#else
		color = GetColorTexture(texcoord.st);
	#endif

	float zoom = 1.0f / BLOOM_RESOLUTION_REDUCTION;
	float ava = 2.0 - step(0.0, zoom) - step(zoom, 1.0);
	zoom = ava + (1 - ava) * zoom;

	vec2 bloomCoord = texcoord.st / sqrt(zoom);

	if (bloomCoord.s <= 1.0f && bloomCoord.s >= 0.0f
	 && bloomCoord.t <= 1.0f && bloomCoord.t >= 0.0f)
	{
		bloom = GetBloom(bloomCoord.st, sqrt(zoom));
		//Debug
		//bloom = texture2D(gaux1, texcoord.st * sqrt(zoom)).rgb * 0.001;
	}

	gl_FragData[0] = vec4(LinearToGamma(bloom), 1.0);
	gl_FragData[1] = vec4(LinearToGamma(color), 1.0);
	//Write color for previous frame here
	gl_FragData[2] = vec4(texture2D(gaux3, texcoord.st).rgba);

}
