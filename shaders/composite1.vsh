#version 120

#define TORCHLIGHT_COLOR_TEMPERATURE 2300 // Color temperature of torch light in Kelvin. [2000 2300 2500 3000]

#define ENV_RESOLUTION_REDUCTION 3.0 // Render resolution reduction of environment lighting. 1.0 = Original. Set higher for faster but blurrier lighting. [1.0 3.0 4.0 9.0 16.0 25.0]

#define SKY_RESOLUTION_REDUCTION 6.0 // Render resolution reduction of environment lighting. 1.0 = Original. Set higher for faster but blurrier sky. [1.0 4.0 6.0 9.0 16.0 25.0]

#include "Common.inc"


varying vec4 texcoord;
varying vec2 envCoord;
varying vec2 skyCoord;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform vec3 skyColor;
uniform float sunAngle;

uniform int worldTime;

varying vec3 lightVector;
varying vec3 upVector;
varying vec3 sunVector;

varying float timeSunriseSunset;
varying float timeNoon;
varying float timeMidnight;
varying float timeSkyDark;

varying vec3 colorSunlight;
varying vec3 colorSkylight;
varying vec3 colorSunglow;
varying vec3 colorBouncedSunlight;
varying vec3 colorScatteredSunlight;
varying vec3 colorTorchlight;
varying vec3 colorWaterMurk;
varying vec3 colorWaterBlue;
varying vec3 colorSkyTint;

varying vec4 skySHR;
varying vec4 skySHG;
varying vec4 skySHB;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec3 worldLightVector;
varying vec3 worldSunVector;

uniform mat4 shadowModelViewInverse;

varying float nightDarkness;

varying float contextualFogFactor;

uniform float frameTimeCounter;

uniform sampler2D noisetex;


varying float heldLightBlacklist;

uniform int heldItemId;    

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

	float zoomEnv = 1.0f / ENV_RESOLUTION_REDUCTION;
	float zoomSky = 1.0f / SKY_RESOLUTION_REDUCTION;

	float avaEnv = 2.0 - step(0.0, zoomEnv) - step(zoomEnv, 1.0);
	float avaSky = 2.0 - step(0.0, zoomSky) - step(zoomSky, 1.0);

	zoomEnv = avaEnv + (1 - avaEnv) * zoomEnv;
	zoomSky = avaSky + (1 - avaSky) * zoomSky;
	
	envCoord = texcoord.st / sqrt(zoomEnv);
	skyCoord = texcoord.st / sqrt(zoomSky);


	heldLightBlacklist = 1.0;

	//Calculate ambient light from atmospheric scattering
	worldSunVector = normalize((shadowModelViewInverse * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	worldLightVector = worldSunVector;

	sunVector = normalize((gbufferModelView * vec4(worldSunVector.xyz, 0.0)).xyz);
	lightVector = sunVector;

	if (sunAngle >= 0.5f) 
	{
		worldSunVector *= -1.0;
		sunVector *= -1.0;
	}

	upVector = normalize((gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0)).xyz);


	if (
		heldItemId == 344
		|| heldItemId == 423
		|| heldItemId == 413
		|| heldItemId == 411
		)
	{
		heldLightBlacklist = 0.0;
	}



	
	nightDarkness = 0.003 * (1.0 + 8.0 * nightVision);


	float timePow = 6.0f;

	float LdotUp = dot(upVector, sunVector);
	float LdotDown = dot(-upVector, sunVector);

	timeNoon = 1.0 - pow(1.0 - saturate(LdotUp), timePow);
	timeSunriseSunset = 1.0 - timeNoon;
	timeMidnight = CubicSmooth(CubicSmooth(saturate(LdotDown * 20.0f + 0.4)));
	timeMidnight = 1.0 - pow(1.0 - timeMidnight, 2.0);
	timeSunriseSunset *= 1.0 - timeMidnight;
	timeNoon *= 1.0 - timeMidnight;

	timeSkyDark = 0.0f;


	float horizonTime = CubicSmooth(saturate((1.0 - abs(LdotUp)) * 7.0f - 6.0f));
	
	const float rayleigh = 0.02f;


	colorWaterMurk = vec3(0.2f, 0.5f, 0.95f);
	colorWaterBlue = vec3(0.2f, 0.5f, 0.95f);
	colorWaterBlue = mix(colorWaterBlue, vec3(1.0f), vec3(0.5f));


	vec3 skyTint = vec3(1.0);
	float skyTintAmount = abs(skyColor.r - (116.0 / 255.0)) + abs(skyColor.g - (172.0 / 255.0)) + abs(skyColor.b - (255.0 / 255.0));

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
	const int latSamples = 2;
	const int lonSamples = 5;

	vec4 shR = vec4(0.0);
	vec4 shG = vec4(0.0);
	vec4 shB = vec4(0.0);

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

			vec3 skyCol = AtmosphericScattering(normalize(kernel + vec3(0.0, 1.0, 0.0) * 0.1), worldSunVector, 0.0);


//void ContextualFog(inout vec3 color, in vec3 viewPos, in vec3 viewDir, in vec3 lightDir, in vec3 skyLightColor, in vec3 sunLightColor, float density)
			ContextualFog(skyCol, kernel * 1670.0, kernel, worldSunVector, skyCol, colorSunlight * 1.0, contextualFogFactor);


			vec3 moonAtmosphere = AtmosphericScattering(kernel, -worldSunVector, 1.0);
			DoNightEye(moonAtmosphere);

			skyCol += moonAtmosphere * nightDarkness;

			colorSkylight += skyCol;

			//skyCol *= 0.5;

			shR += ToSH(skyCol.r, kernel);
			shG += ToSH(skyCol.g, kernel);
			shB += ToSH(skyCol.b, kernel);

			//shR += ToSH(skyCol.r, kernel * vec3(-1.0, 1.0, -1.0));
			//shG += ToSH(skyCol.g, kernel * vec3(-1.0, 1.0, -1.0));
			//shB += ToSH(skyCol.b, kernel * vec3(-1.0, 1.0, -1.0));


		}
	}

	colorSkylight /= latSamples * lonSamples;

	DoNightEye(moonlight);

	colorSunlight += moonlight;


	shR /= latSamples * lonSamples;
	shG /= latSamples * lonSamples;
	shB /= latSamples * lonSamples;

	skySHR = shR;
	skySHG = shG;
	skySHB = shB;
//*/





	
	//Torchlight color
	//colorTorchlight = vec3(1.00f, 0.30f, 0.00f);
	//colorTorchlight = vec3(1.0f, 0.5, 0.1);

	if (TORCHLIGHT_COLOR_TEMPERATURE == 2000)
		//2000k
		colorTorchlight = GammaToLinear(vec3(255, 141, 11) / 255.0);
	else if (TORCHLIGHT_COLOR_TEMPERATURE == 2300)
		//2300k
		colorTorchlight = GammaToLinear(vec3(255, 152, 54) / 255.0);
	else if (TORCHLIGHT_COLOR_TEMPERATURE == 2500)
		//2500k
		colorTorchlight = GammaToLinear(vec3(255, 166, 69) / 255.0);
	else
		//3000k
		colorTorchlight = GammaToLinear(vec3(255, 180, 107) / 255.0);
}
