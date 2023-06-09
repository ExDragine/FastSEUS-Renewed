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

#define TONEMAP_CURVE 5.0 // Controls the intensity of highlights. Lower values give a more filmic look, higher values give a more vibrant/natural look. Default: 5.5 [2.0 3.0 4.0 5.0 6.0]

#define EXPOSURE 1.0 // Controls overall brightness/exposure of the image. Higher values give a brighter image. Default: 1.0 [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

#define GAMMA 1.0 // Gamma adjust. Lower values make shadows darker. Higher values make shadows brighter. Default: 1.0 [0.7 0.8 0.9 1.0 1.1 1.2 1.3]

#define LUMA_GAMMA 1.0 // Gamma adjust of luminance only. Preserves colors while adjusting contrast. Lower values make shadows darker. Higher values make shadows brighter. Default: 1.0 [0.7 0.8 0.9 1.0 1.1 1.2 1.3]

#define SATURATION 1.0 // Saturation adjust. Higher values give a more colorful image. Default: 1.0 [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5]

#define WHITE_CLIP 0.0 // Higher values will introduce clipping to white on the highlights of the image. [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5]

#define BLOOM_RESOLUTION_REDUCTION 16.0 // Render resolution reduction of Bloom. 1.0 = Original. Set higher for faster but blurrier Bloom. [1.0 4.0 9.0 16.0 25.0]

#define BLOOM_AMOUNT 1.0 // Amount of bloom to apply to the image. [0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

#define MICRO_BLOOM // Very fine-scale bloom. Very bright areas will have a fine-scale bleed-over to dark areas.

#define TONEMAP_OPERATOR SEUSTonemap // Each tonemap operator defines a different way to present the raw internal HDR color information to a color range that fits nicely with the limited range of monitors/displays. Each operator gives a different feel to the overall final image. [SEUSTonemap HableTonemap ACESTonemap ACESTonemap2]

/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////


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

varying float timeSunriseSunset;
varying float timeNoon;
varying float timeMidnight;

varying float avgSkyBrightness;

uniform vec3 skyColor;


uniform float nightVision;


const float overlap = 0.2;

const float rgOverlap = 0.1 * overlap;
const float rbOverlap = 0.01 * overlap;
const float gbOverlap = 0.04 * overlap;

const mat3 coneOverlap = mat3(1.0, 			rgOverlap, 	rbOverlap,
							  rgOverlap, 	1.0, 		gbOverlap,
							  rbOverlap, 	rgOverlap, 	1.0);

const mat3 coneOverlapInverse = mat3(	1.0 + (rgOverlap + rbOverlap), 			-rgOverlap, 	-rbOverlap,
									  	-rgOverlap, 		1.0 + (rgOverlap + gbOverlap), 		-gbOverlap,
									  	-rbOverlap, 		-rgOverlap, 	1.0 + (rbOverlap + rgOverlap));










vec3 SEUSTonemap(vec3 color)
{
	color = color * coneOverlap;



	const float p = TONEMAP_CURVE;
	color = pow(color, vec3(p));
	color = color / (1.0 + color);
	color = pow(color, vec3(1.0 / p));


	color = color * coneOverlapInverse;
	color = saturate(color);

	return color;
}



/////////////////////////////////////////////////////////////////////////////////
// Tonemapping by John Hable
vec3 HableTonemap(vec3 x)
{
	
	x *= coneOverlap * 1.5;

	const float A = 0.15;
	const float B = 0.50;
	const float C = 0.10;
	const float D = 0.20;
	const float E = 0.00;
	const float F = 0.30;

	x = pow(x, vec3(TONEMAP_CURVE));

   	vec3 result = pow((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F), vec3(1.0 / TONEMAP_CURVE))-E/F;
   	result = saturate(result);

   	return result * coneOverlapInverse;
}
/////////////////////////////////////////////////////////////////////////////////



/////////////////////////////////////////////////////////////////////////////////
//	ACES Fitting by Stephen Hill
vec3 RRTAndODTFit(vec3 v)
{
    vec3 a = v * (v + 0.0245786f) - 0.000090537f;
    vec3 b = v * (v + 0.4329510f) + 0.238081f;
    return a / b;
}

vec3 ACESTonemap2(vec3 color)
{
	color *= coneOverlap * 1.5;

    // Apply RRT and ODT
    color = RRTAndODTFit(color);


    // Clamp to [0, 1]
    color = saturate(color * coneOverlapInverse);

    return color;
}
/////////////////////////////////////////////////////////////////////////////////











vec3 ACESTonemap(vec3 color)
{
	color = color * coneOverlap;

	color = (color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14);

	color = saturate(color * coneOverlapInverse);


	return color;
}

vec3 Tonemap2(vec3 color)
{
	color *= 1.3;

	const float p = 2.9;
	color = pow(color, vec3(p));
	color = color / (1.0 + color);
	color = pow(color, vec3(1.0 / p));

	color = sqrt(color);
	color = mix(color, color * color * (3.0 - 2.0 * color), vec3(0.1));
	color *= color;



	return color;
}



vec3 	CalculateNoisePattern1(vec2 offset, float size) 
{
	vec2 coord = texcoord.st;

	coord *= vec2(viewWidth, viewHeight);
	coord = mod(coord + offset, vec2(size));
	coord *= 0.015625;

	return texture2D(noisetex, coord).xyz;
}

vec3 GetBloom(vec2 coord)
{
	float zoom = 1.0f / BLOOM_RESOLUTION_REDUCTION;
	float ava = 2.0 - step(0.0, zoom) - step(zoom, 1.0);
	zoom = ava + (1 - ava) * zoom;
	
	vec2 bloomCoord = coord.st * sqrt(zoom);
	vec3 bloomColor = GammaToLinear(texture2DLod(gaux1, bloomCoord, 0.0625).rgb);

	return bloomColor;
}

void CalculateExposureEyeBrightness(inout vec3 color) 
{
	float exposureMax = 1.55f;
		  //exposureMax *= mix(1.0f, 0.25f, timeSunriseSunset);
		  //exposureMax *= mix(1.0f, 0.0f, timeMidnight);
		  //exposureMax *= mix(1.0f, 0.25f, rainStrength);
		  exposureMax *= avgSkyBrightness * 2.0;
	float exposureMin = 0.07f;
	float exposure = pow(eyeBrightnessSmooth.y / 240.0f, 6.0f) * exposureMax + exposureMin;

	//exposure = 1.0f;

	color.rgb /= vec3(exposure);
	color.rgb *= 350.0;
}

void AverageExposure(inout vec3 color)
{
	float avglod = int(log2(min(viewWidth, viewHeight)));

	float avgLumPow = 1.1;
	float exposureMax = 0.9;
	float exposureMin = 0.00005;

	color /= pow(Luminance(texture2DLod(gaux3, vec2(0.5), avglod).rgb), avgLumPow) * exposureMax + exposureMin;
}

void MicroBloom(inout vec3 color, in vec2 uv)
{

	vec3 bloom = vec3(0.0);
	float allWeights = 0.0f;

	for (int i = 0; i < 4; i++) 
	{
		for (int j = 0; j < 4; j++) 
		{
			float weight = 1.0f - distance(vec2(i, j), vec2(2.5f)) / 2.5;
				  weight = clamp(weight, 0.0f, 1.0f);
				  weight = 1.0f - cos(weight * PI / 2.0f);
				  weight = pow(weight, 2.0f);
			vec2 coord  = vec2(i - 2.5, j - 2.5);
				 coord /= vec2(viewWidth, viewHeight);

			vec2 finalCoord = (uv.st + coord.st);

			if (weight > 0.0f)
			{
				bloom += pow(saturate(texture2DLod(gaux3, finalCoord, 0).rgb), vec3(2.2f)) * weight;
				allWeights += weight;
			}
		}
	}
	bloom /= allWeights;

	color = mix(color, bloom, vec3(0.35));
}

void 	Vignette(inout vec3 color) {
	float dist = distance(texcoord.st, vec2(0.5f)) * 2.0f;
		  dist /= 1.5142f;

	color.rgb *= 1.0f - dist * 0.5;

}

void DoNightEye(inout vec3 color)
{
	float lum = Luminance(color);
	float mixSize = 1250000.0;
	float mixFactor = 0.01 / (pow(lum * mixSize, 2.0) + 0.01);


	vec3 nightColor = mix(color, vec3(lum), vec3(0.9)) * vec3(0.25, 0.5, 1.0) * 2.0;

	color = mix(color, nightColor, mixFactor);
}

void Overlay(inout vec3 color, vec3 overlayColor)
{
	vec3 overlay = vec3(0.0);

	for (int i = 0; i < 3; i++)
	{
		if (color[i] > 0.5)
		{
			float valueUnit = (1.0 - color[i]) * 2.0;
			float minValue = color[i] * 2.0 - 1.0;
			overlay[i] = overlayColor[i] * valueUnit + minValue;
		}
		else
		{
			float valueUnit = color[i] * 2.0;
			overlay[i] = overlayColor[i] * valueUnit;
		}
	}

	color = overlay;
}

/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void main() {

	vec2 coord = texcoord.st;

	vec3 color = GammaToLinear(texture2D(gaux3, coord.st).rgb);


	color = mix(color, GetBloom(coord.st), vec3(0.16 * BLOOM_AMOUNT + isEyeInWater * 0.7));

	//CalculateExposureEyeBrightness(color);

	//DoNightEye(color);
#ifdef MICRO_BLOOM
	MicroBloom(color, coord);
#endif
	Vignette(color);

	//Debug
	//color = GetBloom(coord.st);
	//color = GammaToLinear(texture2D(gaux1, coord.st).rgb);

	AverageExposure(color);

	// color = pow(color, vec3(0.8));

	color *= 36.0 * EXPOSURE; 


	color = TONEMAP_OPERATOR(color);

	color = pow(length(color), 1.0 / LUMA_GAMMA) * normalize(color + 0.00001);

	color = saturate(color * (1.0 + WHITE_CLIP));


	color = LinearToGamma(color);
	color = pow(color, vec3((1.0 / GAMMA)));


	color = mix(color, vec3(Luminance(color)), vec3(1.0 - SATURATION));





	color += rand(coord.st) * (1.0 / 255.0);



	gl_FragColor = vec4(color.rgb, 1.0f);

}
