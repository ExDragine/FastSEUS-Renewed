#version 120

#include "Common.inc"

#define ENV_RESOLUTION_REDUCTION 3.0 // Render resolution reduction of environment lighting. 1.0 = Original. Set higher for faster but blurrier lighting. [1.0 3.0 4.0 9.0 16.0 25.0]

#define SKY_RESOLUTION_REDUCTION 6.0 // Render resolution reduction of environment lighting. 1.0 = Original. Set higher for faster but blurrier sky. [1.0 4.0 6.0 9.0 16.0 25.0]

const bool gnormalMipmapEnabled = true;
const bool gaux3MipmapEnabled = true;

varying vec4 texcoord;

uniform sampler2D depthtex1;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D gaux3;

uniform float viewWidth;
uniform float viewHeight;

uniform float near;
uniform float far;

float GetDepthLinear(in vec2 coord) 
{					
	return (near * far) / (texture2D(depthtex1, coord).x * (near - far) + far);
}

vec3 GetNormals(vec2 coord)
{
	return DecodeNormal(texture2D(gnormal, coord).xy);
}

vec3 BilateralUpsample(in float depth, in vec3 normal)
{
	vec2 recipres = vec2(1.0f / viewWidth, 1.0f / viewHeight);
	float zoom = 1.0f / ENV_RESOLUTION_REDUCTION;
	if (zoom < 0.0f || zoom > 1.0f)
	{
		zoom = 1.0f;
	}
	float offset = (zoom == 1.0f) ? 0.0 : (0.25f / zoom);

	vec3 color = vec3(0.0f);
	float weights = 0.0f;

	for (float i = -0.5f; i <= 0.5f; i += 1.0f)
	{
		for (float j = -0.5f; j <= 0.5f; j += 1.0f)
		{
			vec2 coord = vec2(i, j) * recipres * 2.0f;

			float sampleDepth = GetDepthLinear(texcoord.st + coord * 2.0f * exp2(offset));
			vec3 sampleNormal = GetNormals(texcoord.st + coord * 2.0f * exp2(offset));

			float weight = saturate(1.0f - abs(sampleDepth - depth) / 2.0f);
				  weight *= max(0.0f, dot(sampleNormal, normal) * 2.0f - 1.0f);

			color += GammaToLinear(texture2D(gaux3, texcoord.st * sqrt(zoom) + coord).rgb) * weight;

			weights += weight;
		}
	}


	color /= max(0.00001f, weights);

	if (weights < 0.01f)
	{
		color =	GammaToLinear(texture2D(gaux3, (texcoord.st) * sqrt(zoom)).rgb);
	}

	return color;
}

vec3 LinearUpsampleSky(in sampler2D buffer1, in sampler2D buffer2)
{
	float zoom = 1.0f / SKY_RESOLUTION_REDUCTION;
	if (zoom < 0.0f || zoom > 1.0f)
	{
		zoom = 1.0f;
	}

	return GammaToLinear(vec3(texture2D(buffer1, texcoord.st * sqrt(zoom)).ba, texture2D(buffer2, texcoord.st * sqrt(zoom)).a));
}

void main()
{
	float depth = texture2D(depthtex1, texcoord.st).x;
	vec3 normal = GetNormals(texcoord.st);

	vec3 albedo = GammaToLinear(texture2D(gcolor, texcoord.st).rgb);


	vec3 color = BilateralUpsample(depth, normal);
	//vec3 color = LinearUpsample(gaux3);


	if (depth > 0.9999999)
	{
		color += LinearUpsampleSky(gnormal, gaux3);
	}
	else
	{
		color *= albedo;
	}
	
	color = LinearToGamma(color);
		 
	
/* DRAWBUFFERS:6 */
	gl_FragData[0] = vec4(color, 1.0);
}