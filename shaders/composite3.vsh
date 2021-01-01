#version 120

#define SKY_DESATURATION 0.0f



#include "Common.inc"


varying vec4 texcoord;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform vec3 skyColor;
uniform float sunAngle;

uniform int worldTime;

varying vec3 upVector;
varying vec3 sunVector;

varying vec3 colorSunlight;
varying vec3 colorSkylight;
varying vec3 colorSunglow;
varying vec3 colorSkyTint;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec3 worldSunVector;

uniform mat4 shadowModelViewInverse;

varying float nightDarkness;

varying float contextualFogFactor;

uniform float frameTimeCounter;

uniform sampler2D noisetex;

uniform float nightVision;

float CubicSmooth(in float x)
{
	return x * x * (3.0f - 2.0f * x);
}

void ContextualFog(inout vec3 color, in vec3 viewPos, in vec3 viewDir, in vec3 lightDir, in vec3 skyLightColor, in vec3 sunLightColor, float density)
{
	float dist = length(viewPos);

	float fogDensity = density * 0.019;
		  fogDensity *= 1.0 -  saturate(viewDir.y * 0.5 + 0.5) * 0.72;
	float fogFactor = pow(1.0 - exp(-dist * fogDensity), 2.0);
		  //fogFactor = 1.0 -  saturate(viewDir.y * 0.5 + 0.5);




	vec3 fogColor = pow(gl_Fog.color.rgb, vec3(2.2));


	float VdotL = dot(viewDir, lightDir);

	float g = 0.72;
				//float g = 0.9;
	float g2 = g * g;
	float theta = VdotL * 0.5 + 0.5;
	float anisoFactor = 1.5 * ((1.0 - g2) / (2.0 + g2)) * ((1.0 + theta * theta) / (1.0 + g2 - 2.0 * g * theta)) + g * theta;


	float skyFactor = pow(saturate(viewDir.y * 0.5 + 0.5), 1.5);
		  //skyFactor = skyFactor * (3.0 - 2.0 * skyFactor);

	fogColor = sunLightColor * anisoFactor * 1.0 + skyFactor * skyLightColor * 1.0;

	fogColor *= exp(-density * 1.5) * 2.0;

	color = mix(color, fogColor, fogFactor);

}

void DoNightEye(inout vec3 color)
{
	float luminance = Luminance(color);

	color = mix(color, luminance * vec3(0.2, 0.4, 0.9), vec3(0.8));
}

void main() 
{
	gl_Position = ftransform();
	
	texcoord = gl_MultiTexCoord0;

	//Calculate ambient light from atmospheric scattering
	worldSunVector = normalize((shadowModelViewInverse * vec4(0.0, 0.0, 1.0, 0.0)).xyz);

	sunVector = normalize((gbufferModelView * vec4(worldSunVector.xyz, 0.0)).xyz);

	if (sunAngle >= 0.5f) 
	{
		worldSunVector *= -1.0;
		sunVector *= -1.0;
	}

	//sunVector = normalize(sunPosition);

	//upVector = normalize(upPosition);

	upVector = normalize((gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0)).xyz);



	
	nightDarkness = 0.003 * (1.0 + 8.0 * nightVision);


	float LdotUp = dot(upVector, sunVector);


	float horizonTime = CubicSmooth(saturate((1.0 - abs(LdotUp)) * 7.0f - 6.0f));
	


	vec3 skyTint = vec3(1.0);
	float skyTintAmount = abs(skyColor.r - (116.0 / 255.0)) + abs(skyColor.g - (172.0 / 255.0)) + abs(skyColor.b - (255.0 / 255.0));
	//skyTint = mix(vec3(1.0), skyColor, saturate(skyTintAmount));
	contextualFogFactor = clamp(skyTintAmount * 3.0, 0.0, 1.0) * 0.5;
	contextualFogFactor = 0.0;





	colorSunlight = AtmosphericScatteringSingle(worldSunVector, worldSunVector, 1.0) * 0.2;
	colorSunlight = normalize(colorSunlight + 0.001);

	colorSunlight *= pow(saturate(worldSunVector.y), 0.9);
	
	colorSunlight *= 1.0f - horizonTime;




	vec3 moonlight = AtmosphericScattering(-worldSunVector, -worldSunVector, 1.0);
	moonlight = normalize(moonlight + 0.0001);
	moonlight *= pow(saturate(-worldSunVector.y), 0.9);
	moonlight *= nightDarkness * 0.5;



	colorSkylight = vec3(0.0);

///*
	const int latSamples = 1;
	const int lonSamples = 2;

	for (int i = 0; i < latSamples; i++)
	{
		float latitude = (float(i) / float(latSamples)) * PI;
			  latitude = latitude;
		for (int j = 0; j < lonSamples; j++)
		{
			float longitude = (float(j) / float(lonSamples)) * PI * 2.0;
			//longitude = longitude * 0.5 + 0.5;

			vec3 kernel;
			kernel.x = cos(latitude) * cos(longitude);
			kernel.z = cos(latitude) * sin(longitude);
			kernel.y = sin(latitude);

			vec3 skyCol = AtmosphericScattering(kernel, worldSunVector, 0.1);


//void ContextualFog(inout vec3 color, in vec3 viewPos, in vec3 viewDir, in vec3 lightDir, in vec3 skyLightColor, in vec3 sunLightColor, float density)
			ContextualFog(skyCol, kernel * 1670.0, kernel, worldSunVector, skyCol, colorSunlight * 1.0, contextualFogFactor);

			vec3 moonAtmosphere = AtmosphericScattering(kernel, -worldSunVector, 1.0);
			DoNightEye(moonAtmosphere);

			skyCol += moonAtmosphere * nightDarkness;

			colorSkylight += skyCol;


		}
	}

	colorSkylight /= latSamples * lonSamples;

	DoNightEye(moonlight);

	colorSunlight += moonlight;

//*/





	//colorSkylight = vec3(0.1f);
	
}
