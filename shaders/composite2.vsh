#version 120

#define TORCHLIGHT_COLOR_TEMPERATURE 2300 // Color temperature of torch light in Kelvin. [2000 2300 2500 3000]


#include "Common.inc"


varying vec4 texcoord;

uniform float sunAngle;

uniform int worldTime;

varying vec3 lightVector;
varying vec3 upVector;

varying vec3 colorSunlight;
varying vec3 colorSkylight;
varying vec3 colorTorchlight;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec3 worldLightVector;
varying vec3 worldSunVector;

uniform mat4 shadowModelViewInverse;

varying float nightDarkness;

uniform float frameTimeCounter;


varying float heldLightBlacklist;

uniform int heldItemId;    

uniform float nightVision;

float CubicSmooth(in float x)
{
	return x * x * (3.0f - 2.0f * x);
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


	heldLightBlacklist = 1.0;

	//Calculate ambient light from atmospheric scattering
	worldSunVector = normalize((shadowModelViewInverse * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	worldLightVector = worldSunVector;

	vec3 sunVector = normalize((gbufferModelView * vec4(worldSunVector.xyz, 0.0)).xyz);
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

	float horizonTime = CubicSmooth(saturate((1.0 - abs(LdotUp)) * 7.0f - 6.0f));
	
	const float rayleigh = 0.02f;


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
	const int lonSamples = 2;

	for (int i = 0; i < latSamples; i++)
	{
		float latitude = (float(i) / float(latSamples)) * PI;
			  latitude = latitude;
		for (int j = 0; j < lonSamples; j++)
		{
			float longitude = (float(j) / float(lonSamples)) * PI * 2.0;

			vec3 kernel;
			kernel.x = cos(latitude) * cos(longitude);
			kernel.z = cos(latitude) * sin(longitude);
			kernel.y = sin(latitude);

			vec3 skyCol = AtmosphericScattering(normalize(kernel + vec3(0.0, 1.0, 0.0) * 0.1), worldSunVector, 0.0);

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




	
	//Torchlight color

	if (TORCHLIGHT_COLOR_TEMPERATURE == 2000)
		//2000k
		colorTorchlight = pow(vec3(255, 141, 11) / 255.0, vec3(2.2));
	else if (TORCHLIGHT_COLOR_TEMPERATURE == 2300)
		//2300k
		colorTorchlight = pow(vec3(255, 152, 54) / 255.0, vec3(2.2));
	else if (TORCHLIGHT_COLOR_TEMPERATURE == 2500)
		//2500k
		colorTorchlight = pow(vec3(255, 166, 69) / 255.0, vec3(2.2));
	else
		//3000k
		colorTorchlight = pow(vec3(255, 180, 107) / 255.0, vec3(2.2));
	
}
