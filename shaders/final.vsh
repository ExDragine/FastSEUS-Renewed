#version 120



#include "Common.inc"


varying vec4 texcoord;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform vec3 skyColor;
uniform float sunAngle;

uniform int worldTime;

uniform mat4 gbufferModelViewInverse;

varying vec3 upVector;

varying float timeSunriseSunset;
varying float timeNoon;
varying float timeMidnight;

varying float avgSkyBrightness;


float CubicSmooth(in float x)
{
	return x * x * (3.0f - 2.0f * x);
}

float clamp01(float x)
{
	return clamp(x, 0.0, 1.0);
}


void main() {
	gl_Position = ftransform();
	
	texcoord = gl_MultiTexCoord0;

	vec3 sunVector = normalize(sunPosition);

	upVector = normalize(upPosition);
	
	
	float timePow = 6.0f;

	float LdotUp = dot(upVector, sunVector);
	float LdotDown = dot(-upVector, sunVector);

	timeNoon = 1.0 - pow(1.0 - clamp01(LdotUp), timePow);
	timeSunriseSunset = 1.0 - timeNoon;
	timeMidnight = CubicSmooth(CubicSmooth(clamp01(LdotDown * 20.0f + 0.4)));
	timeMidnight = 1.0 - pow(1.0 - timeMidnight, 2.0);
	timeSunriseSunset *= 1.0 - timeMidnight;
	timeNoon *= 1.0 - timeMidnight;
	





	vec3 worldLightVector = normalize((gbufferModelViewInverse * vec4(sunVector, 0.0)).xyz);

	avgSkyBrightness = dot(AtmosphericScattering(vec3(0.0, 1.0, 0.0), worldLightVector, 1.0), vec3(0.0, 0.0, 1.0));

	
}
