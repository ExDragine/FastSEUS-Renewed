#version 120



#include "Common.inc"


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
#define SHADOW_MAP_BIAS 0.90

/////////ADJUSTABLE VARIABLES//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////ADJUSTABLE VARIABLES//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.
#define SHADOW_TAA

#define ENABLE_SSAO	// Screen space ambient occlusion.
#define GI	// Indirect lighting from sunlight.

#define GI_QUALITY 0.5 // Number of GI samples. More samples=smoother GI. High performance impact! [0.5 1.0 2.0]
#define GI_RESOLUTION_REDUCTION 9.0 // Render resolution reduction of GI. 1.0 = Original. Set higher for faster but blurrier GI. [1.0 4.0 9.0 16.0 25.0]
#define GI_RADIUS 1.0 // How far indirect light can spread. Can help to reduce artifacts with low GI samples. [0.5 0.75 1.0 1.5 2.0]

/////////INTERNAL VARIABLES////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////INTERNAL VARIABLES////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//Do not change the name of these variables or their type. The Shaders Mod reads these lines and determines values to send to the inner-workings
//of the shaders mod. The shaders mod only reads these lines and doesn't actually know the real value assigned to these variables in GLSL.
//Some of these variables are critical for proper operation. Change at your own risk.

const float 	shadowDistance 			= 120.0; // Shadow distance. Set lower if you prefer nicer close shadows. Set higher if you prefer nicer distant shadows. [80.0 120.0 180.0 240.0]
const bool 		shadowHardwareFiltering0 = true;

const bool 		shadowtex1Mipmap = true;
const bool 		shadowtex1Nearest = false;
const bool 		shadowcolor0Mipmap = true;
const bool 		shadowcolor0Nearest = false;
const bool 		shadowcolor1Mipmap = true;
const bool 		shadowcolor1Nearest = false;

const int 		noiseTextureResolution  = 64;


//END OF INTERNAL VARIABLES//

/* DRAWBUFFERS:46 */

uniform sampler2D gnormal;
uniform sampler2D depthtex1;
uniform sampler2D composite;
uniform sampler2D gdepth;
uniform sampler2D shadowcolor1;
uniform sampler2D shadowcolor;
uniform sampler2D shadowtex1;
uniform sampler2D noisetex;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferProjection;

varying vec4 texcoord;
varying vec3 lightVector;

uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;
uniform float rainStrength;
uniform float wetness;
uniform float aspectRatio;
uniform float frameTimeCounter;
uniform float sunAngle;
uniform vec3 skyColor;
uniform vec3 cameraPosition;

uniform int frameCounter;

uniform vec2 taaJitter;

varying vec3 upVector;

/////////////////////////FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

vec3  	GetNormals(in vec2 coord) {				//Function that retrieves the screen space surface normals. Used for lighting calculations
	return DecodeNormal(texture2D(gnormal, coord).xy);
}

float 	GetDepth(in vec2 coord) {
	return texture2D(depthtex1, coord.st).x;
}

vec4  	GetScreenSpacePosition(in vec2 coord) {	//Function that calculates the screen-space position of the objects in the scene using the depth texture and the texture coordinates of the full-screen quad
	float depth = GetDepth(coord);
	vec4 fragposition = gbufferProjectionInverse * vec4(coord.s * 2.0f - 1.0f, coord.t * 2.0f - 1.0f, 2.0f * depth - 1.0f, 1.0f);
		 fragposition /= fragposition.w;
	
	return fragposition;
}

vec4  	GetScreenSpacePosition(in vec2 coord, in float depth) {	//Function that calculates the screen-space position of the objects in the scene using the depth texture and the texture coordinates of the full-screen quad
	vec4 fragposition = gbufferProjectionInverse * vec4(coord.s * 2.0f - 1.0f, coord.t * 2.0f - 1.0f, 2.0f * depth - 1.0f, 1.0f);
		 fragposition /= fragposition.w;
	
	return fragposition;
}


vec3 	CalculateNoisePattern1(vec2 offset, float size) {
	vec2 coord = texcoord.st;

	coord *= vec2(viewWidth, viewHeight);
	coord = mod(coord + offset, vec2(size));
	coord /= noiseTextureResolution;

	return texture2D(noisetex, coord).xyz;
}

vec2 DistortShadowSpace(in vec2 pos)
{
	vec2 signedPos = pos * 2.0f - 1.0f;

	float dist = length(signedPos.xy);
	float distortFactor = (1.0f - SHADOW_MAP_BIAS) + dist * SHADOW_MAP_BIAS;
	signedPos.xy *= 0.95 / distortFactor;

	pos = signedPos * 0.5f + 0.5f;

	return pos;
}

float 	GetMaterialIDs(in vec2 coord) {			//Function that retrieves the texture that has all material IDs stored in it
	return texture2D(composite, coord).b;
}

float GetSkylight(in vec2 coord)
{
	return texture2DLod(gdepth, coord, 0).g;
}

float 	GetMaterialMask(in vec2 coord, const in int ID) {
	float matID = (GetMaterialIDs(coord) * 255.0f);

	//Catch last part of sky
	if (matID > 254.0f) {
		matID = 0.0f;
	}

	if (matID == ID) {
		return 1.0f;
	} else {
		return 0.0f;
	}
}

bool 	GetSkyMask(in vec2 coord)
{
	float matID = GetMaterialIDs(coord);
	matID = floor(matID * 255.0f);

	if (matID < 1.0f || matID > 254.0f)
	{
		return true;
	} else {
		return false;
	}
}

float 	ExpToLinearDepth(in float depth)
{
	return 2.0f * near * far / (far + near - (2.0f * depth - 1.0f) * (far - near));
}

vec3 ProjectBack(vec3 cameraSpace) 
{
    vec4 clipSpace = gbufferProjection * vec4(cameraSpace, 1.0);
    vec3 NDCSpace = clipSpace.xyz / clipSpace.w;
    vec3 screenSpace = 0.5 * NDCSpace + 0.5;
		 //screenSpace.z = 0.1f;
    return screenSpace;
}

float GetAO(vec2 coord, vec3 normal, float dither)
{
	const int numRays = 2;

	const float phi = 1.618033988;
	const float gAngle = phi * 3.14159265 * 1.0003;

	float depth = GetDepth(coord);
	float linDepth = ExpToLinearDepth(depth);
	vec3 origin = GetScreenSpacePosition(coord, depth).xyz;

	float aoAccum = 0.0;

	float radius = 0.15 * -origin.z;
		  radius = mix(radius, 0.8, 0.5);
	float zThickness = 0.15 * -origin.z;
		  zThickness = mix(zThickness, 1.0, 0.5);

	float aoMul = 1.0;
	
	for (int i = 0; i < numRays; i++)
	{
		float fi = float(i) + dither;
		float fiN = fi / float(numRays);
		float lon = gAngle * fi * 6.0;
		float lat = asin(fiN * 2.0 - 1.0) * 1.0;

		vec3 kernel;
		kernel.x = cos(lat) * cos(lon);
		kernel.z = cos(lat) * sin(lon);
		kernel.y = sin(lat);

		kernel.xyz = normalize(kernel.xyz + normal.xyz);

		float sampleLength = radius * mod(fiN, 0.07) / 0.07;

		vec3 samplePos = origin + kernel * sampleLength;

		vec3 samplePosProj = ProjectBack(samplePos);

		vec3 actualSamplePos = GetScreenSpacePosition(samplePosProj.xy, GetDepth(samplePosProj.xy)).xyz;

		vec3 sampleVector = normalize(samplePos - origin);

		float depthDiff = actualSamplePos.z - samplePos.z;

		if (depthDiff > 0.0 && depthDiff < zThickness)
		{
			//aoAccum += 1.0 * saturate(depthDiff * 100.0) * saturate(1.0 - depthDiff * 0.25 / (sampleLength + 0.001));
			float aow = 1.35 * saturate(dot(sampleVector, normal));
			//aow *= saturate(dot(sampleVector, upVector) * 0.5 + 0.5) * 1.5 + 0.0;
			aoAccum += aow;
			//aoAccum += 1.0 * saturate(dot(kernel, upVector));
			//aoMul *= mix(1.0, 0.0, saturate(dot(kernel, upVector)));
			//aoMul *= 0.45;
		}
	}

	aoAccum /= numRays;

	float ao = 1.0 - aoAccum;
	ao = pow(ao, 1.5025);

	return ao;
}

vec4 GetLight(in vec2 screenCoord, in float range, in float quality, vec3 noisePattern)
{
	vec3 normal = GetNormals(screenCoord.st);						//Gets the screen-space normals

	vec4 gn = gbufferModelViewInverse * vec4(normal.xyz, 0.0f);
		 gn = shadowModelView * gn;
		 gn.xyz = normalize(gn.xyz);

	vec3 shadowSpaceNormal = gn.xyz;

	vec4 screenSpacePosition 	= GetScreenSpacePosition(screenCoord.st); 			//Gets the screen-space position
	vec3 viewVector 			= normalize(screenSpacePosition.xyz);


	float distance = length(screenSpacePosition.xyz); 	//Get surface distance in meters

	float materialIDs = texture2D(composite, screenCoord).b * 255.0f;

		
	vec4 worldposition = gbufferModelViewInverse * screenSpacePosition;		//Transform from screen space to world space
		 worldposition = shadowModelView * worldposition;							//Transform from world space to shadow space	
		 worldposition = shadowProjection * worldposition;								//Transform from shadow space to shadow projection space					
		 worldposition /= worldposition.w;

	float d = length(worldposition.xy);
	float distortFactor = (1.0f - SHADOW_MAP_BIAS) + d * SHADOW_MAP_BIAS;

	worldposition = worldposition * 0.5f + 0.5f;		//Transform from shadow projection space to shadow map coordinates

	float shadowMult = 0.0f;														//Multiplier used to fade out shadows at distance
	float shad = 0.0f;
	vec3 fakeIndirect = vec3(0.0f);

	float fakeLargeAO = 0.0;


	float mcSkylight = GetSkylight(screenCoord) * 0.8 + 0.2;

	float fademult = 0.15f;

	shadowMult = clamp((shadowDistance * 41.4f * fademult) - (distance * fademult), 0.0f, 1.0f);	//Calculate shadowMult to fade shadows out

	float compare = sin(frameTimeCounter) > -0.2 ? 1.0 : 0.0;

	if (shadowMult > 0.0) 
	{
			 

		//big shadow
		float rad = range;

		int c = 0;
		float s = 2.0f * rad / 2048;

		vec2 dither = noisePattern.xy - 0.5f;
		//vec2 dither = vec2(0.0f);

		float step = 1.0f / quality;

		for (float i = -2.0f; i <= 2.0f; i += step) {
			for (float j = -2.0f; j <= 2.0f; j += step) {

				vec2 offset = (vec2(i, j) + dither * step) * s;

				offset *= length(offset) * 15.0;
				offset *= GI_RADIUS * 1.0;

				vec2 coord =  worldposition.st + offset;
				vec2 lookupCoord = DistortShadowSpace(coord);

				float depthSample = texture2DLod(shadowtex1, lookupCoord, 0).x;

				depthSample = -3 + 5.0 * depthSample;
				vec3 samplePos = vec3(coord.x, coord.y, depthSample);


					fakeLargeAO += saturate((worldposition.z - samplePos.z) * 1000.0);
					//fakeLargeAO += saturate((worldposition.z - samplePos.z) * 1000.0) * saturate(1.0 - abs(worldposition.z - samplePos.z) * 5.0);


				vec3 lightVector = normalize(samplePos.xyz - worldposition.xyz);

				vec4 normalSample = texture2DLod(shadowcolor1, lookupCoord, 6);
				vec3 surfaceNormal = normalSample.rgb * 2.0f - 1.0f;
					 surfaceNormal.x = -surfaceNormal.x;
					 surfaceNormal.y = -surfaceNormal.y;

				float surfaceSkylight = normalSample.a;

				if (surfaceSkylight < 0.2)
				{
					surfaceSkylight = mcSkylight;
				}

				float NdotL = max(0.0f, dot(shadowSpaceNormal.xyz, lightVector * vec3(1.0, 1.0, -1.0)));
					   NdotL = NdotL * 0.9f + 0.2f;

				if (abs(materialIDs - 3.0f) < 0.1f || abs(materialIDs - 2.0f) < 0.1f || abs(materialIDs - 11.0f) < 0.1f)
				{
					NdotL = 0.5f;
				}

				if (NdotL > 0.0)
				{
					bool isTranslucent = length(surfaceNormal) < 0.5f;

					if (isTranslucent)
					{
						surfaceNormal.xyz = vec3(0.0f, 0.0f, 1.0f);
					}

					//float leafMix = clamp(-surfaceNormal.b * 10.0f, 0.0f, 1.0f);


					float weight = dot(lightVector, surfaceNormal);
					float rawdot = weight;
					if (isTranslucent)
					{
						weight = abs(weight) * 0.85f;
					}

					if (normalSample.a < 0.2)
					{
						weight = 0.5;
					}

					weight = max(weight, 0.0f);

					float dist = length(samplePos.xyz - worldposition.xyz - vec3(0.0f, 0.0f, 0.0f));
					if (dist < 0.0005f)
					{
						dist = 10000000.0f;
					}

					const float falloffPower = 1.9f;
					float distanceWeight = (1.0f / (pow(dist * (62260.0f / rad), falloffPower) + 100.1f));
						  //distanceWeight = max(0.0f, distanceWeight - 0.000009f);
						  distanceWeight *= pow(length(offset), 2.0) * 50000.0 + 1.01;
						

					//Leaves self-occlusion
					if (rawdot < 0.0f)
					{
						distanceWeight = max(distanceWeight * 30.0f - 0.13f, 0.0f);
						distanceWeight *= 0.04f;
					}
							  

					//float skylightWeight = clamp(1.0 - abs(surfaceSkylight - mcSkylight) * 10.0, 0.0, 1.0);
					float skylightWeight = 1.0 / (max(0.0, surfaceSkylight - mcSkylight) * 15.0 + 1.0);


					vec3 colorSample = pow(texture2DLod(shadowcolor, lookupCoord, 6).rgb, vec3(2.2f));

					colorSample /= surfaceSkylight;
					//colorSample 				= pow(colorSample, vec3(1.4f));

					colorSample = normalize(colorSample) * pow(length(colorSample), 1.1f);


					fakeIndirect += colorSample * weight * distanceWeight * NdotL * skylightWeight;
					//fakeIndirect += skylightWeight * weight * distanceWeight * NdotL;
					//fakeLargeAO += aoDistanceWeight * NdotL;
				}
				c += 1;
			}
		}

		fakeIndirect /= c;
		fakeLargeAO /= c;
		fakeLargeAO = clamp(1.0 - fakeLargeAO * 0.8, 0.0, 1.0);
		// fakeLargeAO = pow(fakeLargeAO, 2.0);
	}

	fakeIndirect = mix(vec3(0.0f), fakeIndirect, vec3(shadowMult));

	//fakeIndirect /= fakeLargeAO;

	float ao = 1.0f;
	bool isSky = GetSkyMask(screenCoord.st);
	#ifdef ENABLE_SSAO
	if (!isSky)
	{
		ao *= GetAO(screenCoord.st, normal.xyz, noisePattern.x);
	}
	#endif

	fakeIndirect.rgb *= ao;

	//ao *= fakeLargeAO;


	//fakeIndirect.rgb = vec3(mcSkylight / 1150.0);

	return vec4(fakeIndirect.rgb * 500.0f * GI_RADIUS, ao);

}

vec4 textureSmooth(in sampler2D tex, in vec2 coord)
{
	vec2 res = vec2(64.0f);

///*
	coord *= res;
	coord += 0.5f;

	vec2 whole = floor(coord);
	vec2 part  = fract(coord);

	part.x = part.x * part.x * (3.0f - 2.0f * part.x);
	part.y = part.y * part.y * (3.0f - 2.0f * part.y);
	// part.x = 1.0f - (cos(part.x * 3.1415f) * 0.5f + 0.5f);
	// part.y = 1.0f - (cos(part.y * 3.1415f) * 0.5f + 0.5f);

	coord = whole + part;

	coord -= 0.5f;
	coord /= res;
//*/

	return texture2D(tex, coord);
}

float AlmostIdentity(in float x, in float m, in float n)
{
	if (x > m) return x;

	float a = 2.0f * n - m;
	float b = 2.0f * m - 3.0f * n;
	float t = x / m;

	return (a * t + b) * t * t + n;
}


float GetWaves(vec3 position) {
	float speed = 0.9f;

	vec2 p = position.xz / 20.0f;

	p.xy -= position.y / 20.0f;
	p.x = -p.x;

	float waveSpeed = frameTimeCounter * speed;

	p.x += waveSpeed / 40.0f;
	p.y -= waveSpeed / 40.0f;

	float weight = 1.0f;
	float weights = weight;

	float allwaves = 0.0f;

	float wave = 0.0;
	p /= 2.1f;
	p.y -= waveSpeed / 20.0f;
	p.x -= waveSpeed / 30.0f;


	weight = 4.1f;
	weights += weight;
	wave = textureSmooth(noisetex, (p * vec2(2.0f, 1.4f))  + vec2(0.0f,  -p.x * 2.1f) ).x;
	p /= 1.5f;
	p.x += waveSpeed / 20.0f;
	wave *= weight;
	allwaves += wave;

	weight = 17.25f;
	weights += weight;
	wave = (textureSmooth(noisetex, (p * vec2(1.0f, 0.75f))  + vec2(0.0f,  p.x * 1.1f) ).x);
	p /= 1.5f;
	p.x -= waveSpeed / 55.0f;
	wave *= weight;
	allwaves += wave;

	weight = 15.25f;
	weights += weight;
	wave = (textureSmooth(noisetex, (p * vec2(1.0f, 0.75f))  + vec2(0.0f,  -p.x * 1.7f) ).x);
	p /= 1.9f;
	p.x += waveSpeed / 155.0f;
	wave *= weight;
	allwaves += wave;

	weight = 29.25f;
	weights += weight;
	wave = abs(textureSmooth(noisetex, (p * vec2(1.0f, 0.8f))  + vec2(0.0f,  -p.x * 1.7f) ).x * 2.0f - 1.0f);
	p /= 2.0f;
	p.x += waveSpeed / 155.0f;
	wave = 1.0f - AlmostIdentity(wave, 0.2f, 0.1f);
	wave *= weight;
	allwaves += wave;

	weight = 15.25f;
	weights += weight;
	wave = abs(textureSmooth(noisetex, (p * vec2(1.0f, 0.8f))  + vec2(0.0f,  p.x * 1.7f) ).x * 2.0f - 1.0f);
	wave = 1.0f - AlmostIdentity(wave, 0.2f, 0.1f);
	wave *= weight;
	allwaves += wave;

	allwaves /= weights;

	return allwaves;
}


vec3 GetWavesNormal(vec3 position) {

	float WAVE_HEIGHT = 1.5;

	float sampleDistance = 11.0f;

	position -= vec3(0.005f, 0.0f, 0.005f) * sampleDistance;

	float wavesCenter = GetWaves(position);
	float wavesLeft = GetWaves(position + vec3(0.01f * sampleDistance, 0.0f, 0.0f));
	float wavesUp   = GetWaves(position + vec3(0.0f, 0.0f, 0.01f * sampleDistance));

	sampleDistance = 30.0f * WAVE_HEIGHT / sampleDistance;

	vec3 wavesNormal;
		 wavesNormal.r = wavesCenter - wavesLeft;
		 wavesNormal.g = wavesCenter - wavesUp;

		 wavesNormal.r *= sampleDistance;
		 wavesNormal.g *= sampleDistance;

		 wavesNormal.b = 1.0;
		 wavesNormal.rgb = normalize(wavesNormal.rgb);



	return wavesNormal.rgb;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void main() {

	//Waves normal
	vec2 wavesNormal = vec2(0.0);

	vec2 waveCoord = texcoord.st * 5.0f;
	if (waveCoord.s <= 1.0f && waveCoord.s >= 0.0f
	 && waveCoord.t <= 1.0f && waveCoord.t >= 0.0f)
	{
		wavesNormal = EncodeNormal(GetWavesNormal(vec3(waveCoord.s * 50.0, 1.0, waveCoord.t * 50.0)).xyz);
	}
	vec4 gaux1Color = texture2D(gaux1, texcoord.st);

	gl_FragData[0] = vec4(gaux1Color.xy, wavesNormal.xy);
//--------------------------------------------------------------------------------------------------

	vec4 lightGI = vec4(vec3(0.0), 1.0);

	//Noise
	vec3 noisePattern = CalculateNoisePattern1(vec2(0.0f), 4);

	//UV
	float zoom = 1.0f / GI_RESOLUTION_REDUCTION;
	if (zoom < 0.0f || zoom > 1.0f)
	{
		zoom = 1.0f;
	}

	vec2 coord = texcoord.st / sqrt(zoom);

	if (coord.s <= 1.0f && coord.s >= 0.0f
	 && coord.t <= 1.0f && coord.t >= 0.0f)
	{
		if(rainStrength <= 0.99)
		{
			#ifdef GI
				lightGI = GetLight(coord.st, 16.0, GI_QUALITY, noisePattern);
			#endif
		}
		else
		{
			bool isSky = GetSkyMask(coord.st);
		#ifdef ENABLE_SSAO
			if (!isSky)
			{
				vec3 normal = GetNormals(coord.st);
				lightGI.a *= GetAO(coord.st, normal.xyz, noisePattern.x);
			}
		#endif
		}

		lightGI.a = mix(lightGI.a, 1.0, GetMaterialMask(coord.st, 4));
	}

//--------------------------------------------------------------------------------------------------

	gl_FragData[1] = vec4(LinearToGamma(lightGI.rgb), lightGI.a);
}

//change GetWavesNormal
//change material id getting of transparent blocks