#version 120

#extension GL_ARB_gpu_shader5 : enable

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

#define TAA_SOFTNESS 0.0 // Softness of temporal anti-aliasing. Default 0.0 [0.0 0.2 0.4 0.6 0.8 1.0]
#define SHARPENING 0.6 // Sharpening of the image. Default 0.0 [0.0 0.2 0.4 0.8 1.0]

#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.
//#define TAA_AGGRESSIVE // Makes Temporal Anti-Aliasing more generously blend previous frames. This results in a more stable and smoother image, but causes more noticeable artifacts with movement.

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
uniform sampler2D gaux4;
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

vec3 GetColor(vec2 coord)
{
	return GammaToLinear(texture2D(gnormal, coord).rgb);
}

vec3 BlurV(vec2 coord, const float zoom)
{

	vec3 color = vec3(0.0);

	vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

	float weights[5] = float[5](0.27343750, 0.21875000, 0.10937500, 0.03125000, 0.00390625);
	float offsets[5] = float[5](0.00000000, 1.00000000, 2.00000000, 3.00000000, 4.00000000);
	
	color += GetColor(coord) * weights[0];

	color += GetColor(coord + vec2(0.0, offsets[1] * texel.y)) * weights[1];
	color += GetColor(coord - vec2(0.0, offsets[1] * texel.y)) * weights[1];

	color += GetColor(coord + vec2(0.0, offsets[2] * texel.y)) * weights[2];
	color += GetColor(coord - vec2(0.0, offsets[2] * texel.y)) * weights[2];

	color += GetColor(coord + vec2(0.0, offsets[3] * texel.y)) * weights[3];
	color += GetColor(coord - vec2(0.0, offsets[3] * texel.y)) * weights[3];

	color += GetColor(coord + vec2(0.0, offsets[4] * texel.y)) * weights[4];
	color += GetColor(coord - vec2(0.0, offsets[4] * texel.y)) * weights[4];

	return color;
}

float ExpToLinearDepth(in float depth) {
	vec2 a = vec2(fma(depth, 2.0, -1.0), 1.0);

	mat2 ipm = mat2(gbufferProjectionInverse[2].z, gbufferProjectionInverse[2].w,
					gbufferProjectionInverse[3].z, gbufferProjectionInverse[3].w);

	vec2 d = ipm * a;
		 d.x /= d.y;

	return -d.x;
}

vec2 GetNearFragment(vec2 coord, float depth, out float minDepth)
{
	
	
	vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
	vec4 depthSamples;
	depthSamples.x = texture2D(gdepthtex, coord + texel * vec2(1.0, 1.0)).x;
	depthSamples.y = texture2D(gdepthtex, coord + texel * vec2(1.0, -1.0)).x;
	depthSamples.z = texture2D(gdepthtex, coord + texel * vec2(-1.0, 1.0)).x;
	depthSamples.w = texture2D(gdepthtex, coord + texel * vec2(-1.0, -1.0)).x;

	float checker = step(depth, depthSamples.x);

	vec2 targetFragment = vec2(1.0 - checker);

	checker = step(depth, depthSamples.y);
	targetFragment = (1.0 - checker) * vec2(1.0, -1.0) + checker * targetFragment;

	checker = step(depth, depthSamples.z);
	targetFragment = (1.0 - checker) * vec2(-1.0, 1.0) + checker * targetFragment;

	checker = step(depth, depthSamples.w);
	targetFragment = (1.0 - checker) * vec2(-1.0, -1.0) + checker * targetFragment;
		

	minDepth = min(min(min(depthSamples.x, depthSamples.y), depthSamples.z), depthSamples.w);

	return coord + texel * targetFragment;
}

#define COLORPOW 1.0

/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void main() {

	float zoom = 1.0f / BLOOM_RESOLUTION_REDUCTION;
	float ava = 2.0 - step(0.0, zoom) - step(zoom, 1.0);
	zoom = ava + (1 - ava) * zoom;

	vec2 bloomCoord = texcoord.st / sqrt(zoom);
	vec3 bloomColor = vec3(0.0);

	if (bloomCoord.s <= 1.0f && bloomCoord.s >= 0.0f
	 && bloomCoord.t <= 1.0f && bloomCoord.t >= 0.0f)
	{
		bloomColor = BlurV(bloomCoord.st, sqrt(zoom));
		bloomColor = LinearToGamma(bloomColor);
	}






	//Combine TAA here...
	vec3 color = pow(texture2D(gaux3, texcoord.st).rgb, vec3(COLORPOW));	//Sample color texture
	vec3 origColor = color;


	#ifdef TAA_ENABLED


	float depth = texture2D(gdepthtex, texcoord.st).x;


	float minDepth;

	vec2 nearFragment = GetNearFragment(texcoord.st, depth, minDepth);

	float nearDepth = texture2D(gdepthtex, nearFragment).x;

	vec4 projPos = vec4(texcoord.st * 2.0 - 1.0, nearDepth * 2.0 - 1.0, 1.0);
	vec4 viewPos = gbufferProjectionInverse * projPos;
	viewPos.xyz /= viewPos.w;

	vec4 worldPos = gbufferModelViewInverse * vec4(viewPos.xyz, 1.0);

	vec4 worldPosPrev = worldPos;
	worldPosPrev.xyz += cameraPosition - previousCameraPosition;

	vec4 viewPosPrev = gbufferPreviousModelView * vec4(worldPosPrev.xyz, 1.0);
	vec4 projPosPrev = gbufferPreviousProjection * vec4(viewPosPrev.xyz, 1.0);
	projPosPrev.xyz /= projPosPrev.w;

	vec2 motionVector = (projPos.xy - projPosPrev.xy);

	float motionVectorMagnitude = length(motionVector) * 10.0;
	float pixelMotionFactor = clamp(motionVectorMagnitude * 500.0, 0.0, 1.0);

	vec2 reprojCoord = texcoord.st - motionVector.xy * 0.5;

	vec2 pixelError = cos((fract(abs(texcoord.st - reprojCoord.xy) * vec2(viewWidth, viewHeight)) * 2.0 - 1.0) * PI) * 0.5 + 0.5;
	vec2 pixelErrorFactor = pow(pixelError, vec2(0.5));



	vec4 prevColor = pow(texture2D(gaux4, reprojCoord.st), vec4(COLORPOW, COLORPOW, COLORPOW, 1.0));
	float prevMinDepth = prevColor.a;

	float motionVectorDiff = (abs(motionVectorMagnitude - prevColor.a));

	vec3 avgColor = vec3(0.0);
	vec3 avgX = vec3(0.0);
	vec3 avgY = vec3(0.0);

	vec3 m2 = vec3(0.0);


	{
		vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

		//Centre
		vec3 samp = texture2D(gaux3, texcoord.xy).rgb;
		avgColor -= samp;
		avgX += samp;
		avgY += samp;
		m2 += samp * samp;

		//Top
		samp = texture2D(gaux3, texcoord.xy + vec2(-1.0, 1.0) * texel).rgb;
		avgColor += samp;
		m2 += samp * samp;

		samp = texture2D(gaux3, texcoord.xy + vec2(0.0, 1.0) * texel).rgb;
		avgY += samp;
		m2 += samp * samp;

		samp = texture2D(gaux3, texcoord.xy + vec2(1.0, 1.0) * texel).rgb;
		avgColor += samp;
		m2 += samp * samp;

		//Middle
		samp = texture2D(gaux3, texcoord.xy + vec2(-1.0, 0.0) * texel).rgb;
		avgX += samp;
		m2 += samp * samp;

		samp = texture2D(gaux3, texcoord.xy + vec2(1.0, 0.0) * texel).rgb;
		avgX += samp;
		m2 += samp * samp;

		//Buttom
		samp = texture2D(gaux3, texcoord.xy + vec2(-1.0, -1.0) * texel).rgb;
		avgColor += samp;
		m2 += samp * samp;

		samp = texture2D(gaux3, texcoord.xy + vec2(0.0, -1.0) * texel).rgb;
		avgY += samp;
		m2 += samp * samp;

		samp = texture2D(gaux3, texcoord.xy + vec2(1.0, -1.0) * texel).rgb;
		avgColor += samp;
		m2 += samp * samp;
	}


	avgColor = (avgColor + avgX + avgY) / 9.0;
	avgX /= 3.0;
	avgY /= 3.0;

#ifdef TAA_AGGRESSIVE
	float colorWindow = 1.9;
#else
	float colorWindow = 1.5;
#endif

	vec3 sigma = sqrt(max(vec3(0.0), m2 / 9.0 - avgColor * avgColor));
		 sigma *= colorWindow;
	vec3 minc = avgColor - sigma;
	vec3 maxc = avgColor + sigma;

#ifdef TAA_AGGRESSIVE
	vec3 blendWeight = vec3(0.015);
#else
	vec3 blendWeight = vec3(0.05);
#endif


	//adaptive sharpen
	vec3 sharpen = (vec3(1.0) - exp(-(color - avgColor) * 15.0)) * 0.06;
	vec3 sharpenX = (vec3(1.0) - exp(-(color - avgX) * 15.0)) * 0.06;
	vec3 sharpenY = (vec3(1.0) - exp(-(color - avgY) * 15.0)) * 0.06;
	color += sharpenX * (0.45 / blendWeight) * pixelErrorFactor.x;
	color += sharpenY * (0.45 / blendWeight) * pixelErrorFactor.y;



	color += clamp(sharpen, -vec3(0.0005), vec3(0.0005)) * SHARPENING * 4.0;



	color = mix(color, avgColor, vec3(TAA_SOFTNESS));
	prevColor.rgb = clamp(prevColor.rgb, minc, maxc);

	if (depth < 0.7)
	{
		blendWeight = vec3(1.0);
		color = origColor;
	}



	vec3 taa = mix(prevColor.rgb, color, blendWeight);

	#else 

	vec3 taa = color.rgb;

	#endif

	gl_FragData[0] = vec4(bloomColor.rgb, 1.0f);
	gl_FragData[1] = vec4(taa, 1.0);
	gl_FragData[2] = vec4(vec3(0.0), 1.0f);

}
