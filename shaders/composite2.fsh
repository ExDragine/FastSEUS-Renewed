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
uniform sampler2D gaux4;

vec4 LinearUpsample(in sampler2D buffer1, in sampler2D buffer2)
{
	float zoom = 1.0f / ENV_RESOLUTION_REDUCTION;

	float ava = 2.0 - step(0.0, zoom) - step(zoom, 1.0);
	zoom = ava + (1 - ava) * zoom;

	return vec4(GammaToLinear(texture2D(buffer1, texcoord.st * sqrt(zoom)).rgb), texture2D(buffer2, texcoord.st * sqrt(zoom)).a);
}

vec3 LinearUpsampleSky(in sampler2D buffer1, in sampler2D buffer2)
{
	float zoom = 1.0f / SKY_RESOLUTION_REDUCTION;

	float ava = 2.0 - step(0.0, zoom) - step(zoom, 1.0);
	zoom = ava + (1 - ava) * zoom;

	return GammaToLinear(vec3(texture2D(buffer1, texcoord.st * sqrt(zoom)).ba, texture2D(buffer2, texcoord.st * sqrt(zoom)).a));
}

void main()
{
	float depth = texture2D(depthtex1, texcoord.st).x;
	vec3 albedo = GammaToLinear(texture2D(gcolor, texcoord.st).rgb);

	vec4 color = LinearUpsample(gaux3, gaux4);
		 color.rgb = max(color.rgb, vec3(0.0));

	if (Luminance(albedo) < 0.0001 || depth > 0.99999)
	{
		color.rgb = LinearUpsampleSky(gnormal, gaux3);
	}
	else
	{
		color.rgb *= albedo;
	}

	color.rgb = LinearToGamma(color.rgb);
		 
	
/* DRAWBUFFERS:67 */
	vec3 prevColor = texture2D(gaux4, texcoord.st).rgb;
	gl_FragData[0] = color;
	gl_FragData[1] = vec4(prevColor, 1.0);
}