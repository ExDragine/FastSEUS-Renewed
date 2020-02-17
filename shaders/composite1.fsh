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

/////////////////////////CONFIGURABLE VARIABLES////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////CONFIGURABLE VARIABLES////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////END OF CONFIGURABLE VARIABLES/////////////////////////////////////////////////////////////////////////////////////////////////////////////



#include "Common.inc"


#define SHADOW_MAP_BIAS 0.9

#define VARIABLE_PENUMBRA_SHADOWS	// Contact-hardening (area) shadows

#define COLORED_SHADOWS // Colored shadows from stained glass.

#define TAA_ENABLED // Temporal Anti-Aliasing. Utilizes multiple rendered frames to reconstruct an anti-aliased image similar to supersampling. Can cause some artifacts.
	#define SHADOW_TAA

#define GI_RESOLUTION_REDUCTION 9.0 // Render resolution reduction of GI. 1.0 = Original. Set higher for faster but blurrier GI. [1.0 4.0 9.0 16.0 25.0]

#define SUNLIGHT_INTENSITY 1.0 // Intensity of sunlight. [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]






const int 		shadowMapResolution 	= 512;	// Shadowmap resolution [512 768 1024 2048 4096]
const float 	shadowDistance 			= 120.0; // Shadow distance. Set lower if you prefer nicer close shadows. Set higher if you prefer nicer distant shadows. [80.0 120.0 180.0 240.0]
const float 	shadowIntervalSize 		= 4.0f;
const bool 		shadowHardwareFiltering0 = true;

const bool 		shadowtex1Mipmap = true;
const bool 		shadowtex1Nearest = false;
const bool 		shadowcolor0Mipmap = true;
const bool 		shadowcolor0Nearest = false;
const bool 		shadowcolor1Mipmap = true;
const bool 		shadowcolor1Nearest = false;

const float shadowDistanceRenderMul = 1.0f;

const int 		RGB8 					= 0;
const int 		RGBA8 					= 0;
const int 		RGBA16 					= 0;
const int 		RG16 					= 0;
const int 		RGB16 					= 0;
const int 		gcolorFormat 			= RGB8;
const int 		gdepthFormat 			= RGBA8;
const int 		gnormalFormat 			= RGBA16;
const int 		compositeFormat 		= RGB8;
const int 		gaux1Format 			= RGBA16;
const int 		gaux2Format 			= RGBA8;
const int 		gaux3Format 			= RGBA16;
const int 		gaux4Format 			= RGBA16;


const int 		superSamplingLevel 		= 0;

const float		sunPathRotation 		= -40.0f;

const int 		noiseTextureResolution  = 64;

const float 	ambientOcclusionLevel 	= 0.06f;


const bool gaux3MipmapEnabled = true;
const bool gaux1MipmapEnabled = false;

const bool gaux4Clear = false;

const float wetnessHalflife = 1.0;
const float drynessHalflife = 60.0;


uniform sampler2D gcolor;
uniform sampler2D gdepth;
uniform sampler2D depthtex1;
uniform sampler2D gdepthtex;
uniform sampler2D gnormal;
uniform sampler2D composite;
uniform sampler2D gaux1;
uniform sampler2D gaux2;
uniform sampler2D gaux3;
uniform sampler2D gaux4;
uniform sampler2D noisetex;

uniform sampler2DShadow shadow;


varying vec4 texcoord;
varying vec2 envCoord;
varying vec2 skyCoord;

varying vec3 lightVector;
varying vec3 sunVector;
varying vec3 upVector;

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

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform mat4 gbufferModelView;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 skyColor;

uniform int   isEyeInWater;
uniform float eyeAltitude;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform int   fogMode;

varying float timeSunriseSunset;
varying float timeNoon;
varying float timeMidnight;

varying vec3 colorSunlight;
varying vec3 colorSkylight;
varying vec3 colorTorchlight;

varying vec4 skySHR;
varying vec4 skySHG;
varying vec4 skySHB;

varying vec3 worldLightVector;
varying vec3 worldSunVector;

uniform int heldBlockLightValue;

varying float contextualFogFactor;

uniform int frameCounter;

uniform vec2 taaJitter;

uniform float nightVision;

varying float heldLightBlacklist;





vec4 GetViewPosition(in vec2 coord, in float depth) 
{
#ifdef TAA_ENABLED
	coord += taaJitter;
#endif

	vec4 fragposition = gbufferProjectionInverse * vec4(coord.s * 2.0f - 1.0f, coord.t * 2.0f - 1.0f, 2.0f * depth - 1.0f, 1.0f);
		 fragposition /= fragposition.w;

	
	return fragposition;
}

vec4 GetViewPositionRaw(in vec2 coord, in float depth) 
{
	vec4 fragposition = gbufferProjectionInverse * vec4(coord.s * 2.0f - 1.0f, coord.t * 2.0f - 1.0f, 2.0f * depth - 1.0f, 1.0f);
		 fragposition /= fragposition.w;

	
	return fragposition;
}

float 	ExpToLinearDepth(in float depth)
{
	return 2.0f * near * far / (far + near - (2.0f * depth - 1.0f) * (far - near));
}

float CurveBlockLightSky(float blockLight)
{
	//blockLight = pow(blockLight, 3.0);

	//blockLight = InverseSquareCurve(1.0 - blockLight, 0.2);
	blockLight = 1.0 - pow(1.0 - blockLight, 0.45);
	blockLight *= blockLight * blockLight;

	return blockLight;
}

float GetDepthLinear(in vec2 coord) 
{					
	return (near * far) / (texture2D(depthtex1, coord).x * (near - far) + far);
}

vec3 GetNormals(vec2 coord)
{
	return DecodeNormal(texture2D(gnormal, coord).xy);
}

vec3 	CalculateNoisePattern1(vec2 offset, float size) 
{
	vec2 coord = texcoord.st;

	coord *= vec2(viewWidth, viewHeight);
	coord = mod(coord + offset, vec2(size));
	coord /= noiseTextureResolution;

	return texture2D(noisetex, coord).xyz;
}




struct GbufferData
{
	vec3 albedo;
	vec3 normal;
	float depth;
	float mcLightmap;
	float smoothness;
	float metallic;
	float emissive;
	float materialID;
	vec4 transparentAlbedo;
	float parallaxShadow;
};


struct MaterialMask
{
	float sky;
	float grass;
	float leaves;
	float hand;
	float entityPlayer;
	float water;
	float stainedGlass;
	float ice;
};

struct Ray {
	vec3 dir;
	vec3 origin;
};

struct Plane {
	vec3 normal;
	vec3 origin;
};

struct Intersection {
	vec3 pos;
	float distance;
	float angle;
};

float GetMaterialMask(const in int ID, in float matID) 
{
	//Catch last part of sky
	if (matID > 254.0f) 
	{
		matID = 0.0f;
	}

	if (matID == ID) 
	{
		return 1.0f;
	} 
	else 
	{
		return 0.0f;
	}
}

GbufferData GetGbufferData(vec2 coord)
{
	GbufferData data;


	vec3 gbuffer0 = texture2D(gcolor, coord.st).rgb;
	vec3 gbuffer1 = texture2D(gdepth, coord.st).gba;
	vec2 gbuffer2 = texture2D(gnormal, coord.st).rg;
	vec3 gbuffer3 = texture2D(composite, coord.st).rgb;
	float depth = texture2D(depthtex1, coord.st).x;


	data.albedo = GammaToLinear(gbuffer0);

	data.mcLightmap = CurveBlockLightSky(gbuffer1.r);
	data.emissive = gbuffer1.g;

	data.normal = DecodeNormal(gbuffer2);


	data.smoothness = gbuffer3.r;
	data.metallic = gbuffer3.g;
	data.materialID = gbuffer3.b;

	data.depth = depth;

	data.transparentAlbedo = texture2D(gaux2, coord.st);

	data.parallaxShadow = gbuffer1.b;

	return data;
}

MaterialMask CalculateMasks(float materialID)
{
	MaterialMask mask;

	materialID *= 255.0;

	mask.sky = GetMaterialMask(0, materialID);



	mask.grass 			= GetMaterialMask(2, materialID);
	mask.leaves 		= GetMaterialMask(3, materialID);
	mask.hand 			= GetMaterialMask(4, materialID);
	mask.entityPlayer 	= GetMaterialMask(5, materialID);
	mask.water 			= GetMaterialMask(6, materialID);
	mask.stainedGlass	= GetMaterialMask(7, materialID);
	mask.ice 			= GetMaterialMask(8, materialID);

	return mask;
}

Intersection 	RayPlaneIntersectionWorld(in Ray ray, in Plane plane)
{
	float rayPlaneAngle = dot(ray.dir, plane.normal);

	float planeRayDist = 100000000.0f;
	vec3 intersectionPos = ray.dir * planeRayDist;

	if (rayPlaneAngle > 0.0001f || rayPlaneAngle < -0.0001f)
	{
		planeRayDist = dot((plane.origin), plane.normal) / rayPlaneAngle;
		intersectionPos = ray.dir * planeRayDist;
		intersectionPos = -intersectionPos;

		intersectionPos += cameraPosition.xyz;
	}

	Intersection i;

	i.pos = intersectionPos;
	i.distance = planeRayDist;
	i.angle = rayPlaneAngle;

	return i;
}





vec4 BilateralUpsample(in float depth, in vec3 normal)
{
	vec2 recipres = vec2(1.0f / viewWidth, 1.0f / viewHeight);
	float zoomGI = 1.0f / GI_RESOLUTION_REDUCTION;
	if (zoomGI < 0.0f || zoomGI > 1.0f)
	{
		zoomGI = 1.0f;
	}
	float offset = (zoomGI == 1.0f) ? 0.0 : (0.25f / zoomGI);

	vec4 light = vec4(0.0f);
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

			light += pow(texture2DLod(gaux3, texcoord.st * sqrt(zoomGI) + coord, 1.875), vec4(vec3(2.2f), 1.0f)) * weight;

			weights += weight;
		}
	}


	light /= max(0.00001f, weights);

	if (weights < 0.01f)
	{
		light =	pow(texture2DLod(gaux3, (texcoord.st) * sqrt(zoomGI), 1.875), vec4(vec3(2.2f), 1.0f));
	}

	return light;
}

vec4 GetGI(vec3 albedo, vec3 normal, float depth, float skylight)
{

	depth = ExpToLinearDepth(depth);

	vec4 indirectLight = BilateralUpsample(depth, normal);
	//vec4 indirectLight = texture2D(gaux3, texcoord.st * sqrt(1.0f / GI_RESOLUTION_REDUCTION));
	

	if(rainStrength <= 0.99)
	{
		float value = length(indirectLight.rgb);

		indirectLight.rgb = pow(value, 0.7) * normalize(indirectLight.rgb + 0.0001) * 0.4;



		indirectLight.rgb *= albedo * mix(colorSunlight, vec3(0.4) * Luminance(colorSkylight), rainStrength);
		indirectLight.rgb *= 3.6f * saturate(skylight * 7.0);
	}

	return indirectLight;
}

float OrenNayar(vec3 normal, vec3 eyeDir, vec3 lightDir)
{
	const float PI = 3.14159;
	const float roughness = 0.55;

	// interpolating normals will change the length of the normal, so renormalize the normal.

	// calculate intermediary values
	float NdotL = dot(normal, lightDir);
	float NdotV = dot(normal, eyeDir);

	float angleVN = acos(NdotV);
	float angleLN = acos(NdotL);

	float alpha = max(angleVN, angleLN);
	float beta = min(angleVN, angleLN);
	float gamma = dot(eyeDir - normal * dot(eyeDir, normal), lightDir - normal * dot(lightDir, normal));

	float roughnessSquared = roughness * roughness;

	// calculate A and B
	float A = 1.0 - 0.5 * (roughnessSquared / (roughnessSquared + 0.57));

	float B = 0.45 * (roughnessSquared / (roughnessSquared + 0.09));

	float C = sin(alpha) * tan(beta);

	// put it all together
	float L1 = max(0.0, NdotL) * (A + B * max(0.0, gamma) * C);

	//return max(0.0f, surface.NdotL * 0.99f + 0.01f);
	return saturate(L1);
}

vec3 GetWavesNormal(vec3 position) {

	vec2 coord = position.xz / 50.0;
	coord.xy -= position.y / 50.0;
	//coord -= floor(coord);

	coord = mod(coord, vec2(1.0));

	float texelScale = 4.0;

	//to fix color error with GL_CLAMP
	coord.x = coord.x * ((viewWidth - 1 * texelScale) / viewWidth) + ((0.5 * texelScale) / viewWidth);
	coord.y = coord.y * ((viewHeight - 1 * texelScale) / viewHeight) + ((0.5 * texelScale) / viewHeight);

	coord *= 0.1995f;

	vec3 normal;
	if (coord.s <= 1.0f && coord.s >= 0.0f
	 && coord.t <= 1.0f && coord.t >= 0.0f)
	{
		normal.xyz = DecodeNormal(texture2D(gaux1, coord).zw);
	}

	return normal;
}

vec3 FakeRefract(vec3 vector, vec3 normal, float ior)
{
	return refract(vector, normal, ior);
	//return vector + normal * 0.5;
}

float CalculateWaterCaustics(vec4 screenSpacePosition, MaterialMask mask)
{
	if (isEyeInWater == 1)
	{
		if (mask.water > 0.5)
		{
			return 1.0;
		}
	}
	vec4 worldPos = gbufferModelViewInverse * screenSpacePosition;
	worldPos.xyz += cameraPosition.xyz;

	vec2 dither = CalculateNoisePattern1(vec2(0.0), 2.0).xy;
	float waterPlaneHeight = 63.0;

	// vec4 wlv = shadowModelViewInverse * vec4(0.0, 0.0, 1.0, 0.0);
	vec4 wlv = gbufferModelViewInverse * vec4(lightVector.xyz, 0.0);
	vec3 worldLightVector = -normalize(wlv.xyz);
	// worldLightVector = normalize(vec3(-1.0, 1.0, 0.0));

	float pointToWaterVerticalLength = min(abs(worldPos.y - waterPlaneHeight), 2.0);
	vec3 flatRefractVector = FakeRefract(worldLightVector, vec3(0.0, 1.0, 0.0), 1.0 / 1.3333);
	float pointToWaterLength = pointToWaterVerticalLength / -flatRefractVector.y;
	vec3 lookupCenter = worldPos.xyz - flatRefractVector * pointToWaterLength;


	const float distanceThreshold = 0.15;

	const int numSamples = 1;
	int c = 0;

	float caustics = 0.0;

	for (int i = -numSamples; i <= numSamples; i++)
	{
		for (int j = -numSamples; j <= numSamples; j++)
		{
			vec2 offset = vec2(i + dither.x, j + dither.y) * 0.2;
			vec3 lookupPoint = lookupCenter + vec3(offset.x, 0.0, offset.y);
			vec3 wavesNormal = GetWavesNormal(lookupPoint).xzy;
			vec3 refractVector = FakeRefract(worldLightVector.xyz, wavesNormal.xyz, 1.0 / 1.3333);
			float rayLength = pointToWaterVerticalLength / refractVector.y;
			vec3 collisionPoint = lookupPoint - refractVector * rayLength;

			float dist = dot(collisionPoint - worldPos.xyz, collisionPoint - worldPos.xyz) * 7.1;

			caustics += 1.0 - saturate(dist / distanceThreshold);

			c++;
		}
	}

	caustics /= c;

	caustics /= distanceThreshold;


	return pow(caustics, 2.0) * 3.0;
}

vec3 CalculateSunlightVisibility(vec4 screenSpacePosition, MaterialMask mask) {				//Calculates shadows
	if (rainStrength >= 0.99f)
		return vec3(1.0f);

	#ifdef TAA_ENABLED
		vec3 noise = rand(texcoord.st + sin(frameTimeCounter)).rgb;
	#else
		vec3 noise = rand(texcoord.st).rgb;
	#endif

	//if (shadingStruct.direct > 0.0f) {
		float distance = length(screenSpacePosition.xyz); 	//Get surface distance in meters

		vec4 ssp = screenSpacePosition;

		vec4 worldposition = gbufferModelViewInverse * ssp;		//Transform from screen space to world space


		worldposition = shadowModelView * worldposition;	//Transform from world space to shadow space
		float comparedepth = -worldposition.z;				//Surface distance from sun to be compared to the shadow map

		worldposition = shadowProjection * worldposition;
		worldposition /= worldposition.w;

		float dist = length(worldposition.xy);
		float distortFactor = (1.0f - SHADOW_MAP_BIAS) + dist * SHADOW_MAP_BIAS;
		worldposition.xy *= 0.95f / distortFactor;

	#ifdef SHADOW_TAA
		worldposition.xy += taaJitter;
	#endif

		worldposition.z = mix(worldposition.z, 0.5, 0.8);
		worldposition = worldposition * 0.5f + 0.5f;		//Transform from shadow space to shadow map coordinates

		float shadowMult = 0.0f;																			//Multiplier used to fade out shadows at distance
		float shading = 0.0f;

		float fademult = 0.15f;
			shadowMult = saturate(shadowDistance * 1.4f * fademult - distance * fademult);	//Calculate shadowMult to fade shadows out

		if (shadowMult > 0.0) 
		{

			float diffthresh = dist * 1.0f + 0.10f;
				  diffthresh *= 1.5f / (shadowMapResolution / 2048.0f);
				  //diffthresh /= shadingStruct.direct + 0.1f;


			#ifdef PIXEL_SHADOWS
				  //diffthresh += 1.5;
			#endif


			#ifdef ENABLE_SOFT_SHADOWS
			#ifndef VARIABLE_PENUMBRA_SHADOWS

				int count = 0;
				float spread = 1.0f / shadowMapResolution;

				for (float i = -0.5f; i <= 0.5f; i++) 
				{
					for (float j = -0.5f; j <= 0.5f; j++) 
					{
						float angle = noise.x * 3.14159 * 2.0;

						mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

						vec2 coord = vec2(i, j) * rot;

						shading += shadow2D(shadow, vec3(worldposition.st + coord * spread, worldposition.z - 0.0008f * diffthresh)).x;
						count++;
					}
				}
				shading /= count;

			#endif
			#endif

			#ifdef VARIABLE_PENUMBRA_SHADOWS

				float vpsSpread = 0.145 / distortFactor;

				float avgDepth = 0.0;
				float minDepth = 11.0;
				int c;

				for (int i = -1; i <= 1; i += 2)
				{
					for (int j = -1; j <= 1; j += 2)
					{
						vec2 lookupCoord = worldposition.xy + (vec2(i, j) / shadowMapResolution) * 8.0 * vpsSpread;
						//avgDepth += pow(texture2DLod(shadowtex1, lookupCoord, 2).x, 4.1);
						float depthSample = texture2DLod(shadowtex1, lookupCoord, 0).x;
						minDepth = min(minDepth, depthSample);
						avgDepth += pow(min(max(0.0, worldposition.z - depthSample) * 1.0, 0.025), 2.0);
						c++;
					}
				}

				avgDepth /= c;
				avgDepth = pow(avgDepth, 1.0 / 2.0);

				// float penumbraSize = min(abs(worldposition.z - minDepth), 0.15);
				float penumbraSize = avgDepth;


				int count = 0;
				float spread = penumbraSize * 0.125 * vpsSpread + 0.25 / shadowMapResolution;
				spread += dist * 2.0 / shadowMapResolution;

				// worldposition.z -= (1.0 / shadowMapResolution) * noise.x * dist;

				diffthresh *= 0.5 + avgDepth * 50.0;

				for (float i = -1.5f; i <= 1.5f; i += 2.0f) 
				{
					for (float j = -1.5f; j <= 1.5f; j += 2.0f) 
					{
						float angle = noise.x * 3.14159 * 2.0;

						mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

						vec2 coord = vec2(i + noise.y - 0.5, j + noise.y - 0.5) * rot;

						shading += shadow2D(shadow, vec3(worldposition.st + coord * spread, worldposition.z - 0.0012f * diffthresh)).x;
						count++;
					}
				}
				shading /= count;

			#endif

			#ifndef VARIABLE_PENUMBRA_SHADOWS
			#ifndef ENABLE_SOFT_SHADOWS
				//diffthresh *= 2.0f;
				shading = shadow2DLod(shadow, vec3(worldposition.st, worldposition.z - 0.0006f * diffthresh), 0).x;
			#endif
			#endif

		}

		float clampFactor = max(0.0, dist - 0.1) * 5.0 + 1.0;
		shading = saturate(((shading * 2.0 - 1.0) * clampFactor) * 0.5 + 0.5);

		vec3 result = vec3(shading);


		///*
		#ifdef COLORED_SHADOWS

		float shadowNormalAlpha = texture2DLod(shadowcolor1, worldposition.st, 0).a;

		if (shadowNormalAlpha < 0.1)
		{

			float angle = noise.x * 3.14159 * 2.0;
			mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

			float solidShadowSum = 0.0;
			vec3 shadowColorSampleSum = vec3(0.0);

			int c = 0;

			for (float i = -1.5f; i <= 1.5f; i += 2.0f) 
			{
				for (float j = -1.5f; j <= 1.5f; j += 2.0f) 
				{
					// worldposition.st += (vec2(i, j) * rot) * (0.5 / shadowMapResolution);
					worldposition.st += (vec2(i + noise.y - 0.5, j + noise.y - 0.5) * rot) * (0.5 / shadowMapResolution);

					vec4 shadowColorSample = texture2DLod(shadowcolor, worldposition.st, 0);
					float opacityCheck = 1.0 - saturate(pow(shadowColorSample.a * 1.1, 4.0));
					// result = mix(vec3(1.0), pow(shadowColorSample.rgb, vec3(1.6)) * (opacityCheck), vec3(1.0 - shading));
					shadowColorSampleSum += pow(shadowColorSample.rgb, vec3(1.6)) * (opacityCheck);
					float solidDepth = texture2DLod(shadowtex1, worldposition.st, 0).x;
					float solidShadow = 1.0 - saturate((worldposition.z - solidDepth) * 5200.0); 
					solidShadowSum += solidShadow;
					// result *= solidShadow;
					c++;
				}
			}

			solidShadowSum /= c;
			shadowColorSampleSum /= c;

			result = mix(vec3(1.0), shadowColorSampleSum.rgb, vec3(1.0 - shading));
			result *= solidShadowSum;
		}
		#endif
		//*/

		result = mix(vec3(1.0), result, shadowMult);

	#ifdef TAA_ENABLED
		#ifdef SHADOW_TAA
			result = mix(vec3(1.0), result, shadowMult);
			result *= (result.r > 0.8 || result.g > 0.8 || result.b > 0.8) ? 1.0f : noise.x;
		#endif
	#endif

	return result;
}

float RenderSunDisc(vec3 worldDir, vec3 sunDir)
{
	float d = dot(worldDir, sunDir);

	float disc = 0.0;


	float size = 0.00195;
	float hardness = 1000.0;

	disc = pow(curve(saturate((d - (1.0 - size)) * hardness)), 2.0);

	float visibility = curve(saturate(worldDir.y * 30.0));

	disc *= visibility;

	return disc;
}

float Get2DNoise(in vec3 pos)
{
	pos.xy = pos.xz;
	pos.xy += 0.5f;

	vec2 p = floor(pos.xy);
	vec2 f = fract(pos.xy);

	f.x = f.x * f.x * (3.0f - 2.0f * f.x);
	f.y = f.y * f.y * (3.0f - 2.0f * f.y);

	vec2 uv = p.xy + f.xy;

	// uv -= 0.5f;
	// uv2 -= 0.5f;

	vec2 coord = (uv + 0.5f) / noiseTextureResolution;
	float xy1 = texture2D(noisetex, coord).x;
	return xy1;
}

float GetCoverage(in float coverage, in float density, in float clouds)
{
	clouds = clamp(clouds - (1.0f - coverage), 0.0f, 1.0f - density) / (1.0f - density);
		clouds = max(0.0f, clouds * 1.1f - 0.1f);
	//TODO: Clean up this dirty shit!
	 //clouds = clouds = clouds * clouds * (3.0f - 2.0f * clouds);
	return clouds;
}

float   CalculateSunglow(vec3 npos, vec3 lightVector) {

	float curve = 4.0f;

	vec3 halfVector2 = normalize(-lightVector + npos);
	float factor = 1.0f - dot(halfVector2, npos);

	return factor * factor * factor * factor;
}

vec4 CloudColor(in vec4 worldPosition, in float sunglow, in vec3 worldLightVector, in float altitude, in float thickness, const bool isShadowPass)
{

	float cloudHeight = altitude;
	float cloudDepth  = thickness;
	float cloudUpperHeight = cloudHeight + (cloudDepth / 2.0f);
	float cloudLowerHeight = cloudHeight - (cloudDepth / 2.0f);

	//worldPosition.xz /= 1.0f + max(0.0f, length(worldPosition.xz - cameraPosition.xz) / 5000.0f);

	vec3 p = worldPosition.xyz / 150.0f;



	float t = frameTimeCounter * 1.0f;
		  t *= 0.5;


	p    += (Get2DNoise(p * 2.0f   ) * 2.0f - 1.0f) * 0.10f;
	p.z  -= (Get2DNoise(p * 0.25f  ) * 2.0f - 1.0f) * 0.45f;
	p.x  -= (Get2DNoise(p * 0.125f ) * 2.0f - 1.0f) * 2.2f;
	p.xz -= (Get2DNoise(p * 0.0525f) * 2.0f - 1.0f) * 2.7f;


	p.x *= 0.5f;
	p.x -= t * 0.01f;

	vec3 p1 = p * vec3(1.0f, 0.5f, 1.0f) + vec3(0.0f, t * 0.01f, 0.0f);

	float noise = Get2DNoise(p * vec3(1.0f, 0.5f, 1.0f) + vec3(0.0f, t * 0.01f, 0.0f));
	p *= 2.0f;
	p.x -= t * 0.057f;
	vec3 p2 = p;

	noise += (2.0f - abs(Get2DNoise(p) * 2.0f - 0.0f)) * 0.15f;
		p *= 3.0f;
		p.xz -= t * 0.035f;
		p.x *= 2.0f;
		vec3 p3 = p;

	noise += (3.0f - abs(Get2DNoise(p) * 3.0f - 0.0f)) * 0.050f;
		p *= 3.0f;
		p.xz -= t * 0.035f;
		vec3 p4 = p;

	noise += (3.0f - abs(Get2DNoise(p) * 3.0f - 0.0f)) * 0.015f;
		p *= 3.0f;
		p.xz -= t * 0.035f;

		  if (!isShadowPass)
		  {
		 		noise += Get2DNoise(p) * 0.022f;
				p *= 3.0f;
		  		noise += Get2DNoise(p) * 0.009f;
		  }
		  noise /= 1.475f;

	//cloud edge
	float coverage = 0.701f;
		  coverage = mix(coverage, 0.97f, rainStrength);

		  float dist = length(worldPosition.xz - cameraPosition.xz * 0.5);
		  coverage *= max(0.0f, 1.0f - dist / 14000.0f);
	float density = 0.1f + rainStrength * 0.3;

	if (isShadowPass)
	{
		return vec4(GetCoverage(0.4f, 0.4f, noise));
	}

	noise = GetCoverage(coverage, density, noise);

	const float lightOffset = 0.4f;



	float sundiff = Get2DNoise(p1 + worldLightVector.xyz * lightOffset);
		  sundiff += (2.0f - abs(Get2DNoise(p2 + worldLightVector.xyz * lightOffset / 2.0f) * 2.0f)) * 0.55f;
		  				float largeSundiff = sundiff;
		  				      largeSundiff = -GetCoverage(coverage, 0.0f, largeSundiff * 1.3f);
		  sundiff += (3.0f - abs(Get2DNoise(p3 + worldLightVector.xyz * lightOffset / 5.0f) * 3.0f)) * 0.045f;
		  sundiff += (3.0f - abs(Get2DNoise(p4 + worldLightVector.xyz * lightOffset / 8.0f) * 3.0f)) * 0.015f;
		  sundiff *= 0.66666f;

		  sundiff *= max(0.0f, 1.0f - dist / 14000.0f);

		  sundiff = -GetCoverage(coverage * 1.0f, 0.0f, sundiff);
	float secondOrder 	= pow(saturate(sundiff      * 1.1f + 1.45f), 4.0f);
	float firstOrder 	= pow(saturate(largeSundiff * 1.1f + 1.66f), 3.0f);



	float directLightFalloff = firstOrder * secondOrder;
	float anisoBackFactor = mix(saturate(pow(noise, 1.6f) * 2.5f), 1.0f, pow(sunglow, 1.0f));

		  directLightFalloff *= anisoBackFactor;
	 	  directLightFalloff *= mix(11.5f, 1.0f, pow(sunglow, 0.5f));

	//noise *= saturate(1.0 - directLightFalloff);

	vec3 colorDirect = colorSunlight * 11.215f;
		 colorDirect = mix(colorDirect, colorDirect * vec3(0.2f), timeMidnight);
		 colorDirect *= 1.0f + pow(sunglow, 2.0f) * 120.0f * pow(directLightFalloff, 1.1f) * (1.0 - rainStrength * 0.8);


	vec3 colorAmbient = mix(colorSkylight, colorSunlight * 2.0f, vec3(0.15f)) * 0.93f;
		 colorAmbient = mix(colorAmbient, vec3(0.4) * Luminance(colorSkylight), vec3(rainStrength));
		 colorAmbient *= mix(1.0f, 0.3f, timeMidnight);
		 colorAmbient = mix(colorAmbient, colorAmbient * 3.0f + colorSunlight * 0.05f, vec3(saturate(pow(1.0f - noise, 12.0f))));




	directLightFalloff *= mix(1.0, 0.085, rainStrength);



	vec3 color = mix(colorAmbient, colorDirect, vec3(min(1.0f, directLightFalloff)));

	color = mix(color, color * 0.9, rainStrength);


	vec4 result = vec4(color.rgb, noise);

	return result;

}

void CloudPlane(inout vec3 color, vec3 viewDir, vec3 worldVector, float linearDepth, vec3 worldLightVector, vec3 lightVector, float gbufferdepth)
{
	//Initialize view ray


	Ray viewRay;

	viewRay.dir = normalize(worldVector.xyz);
	// viewRay.origin = (gbufferModelViewInverse * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	viewRay.origin = vec3(0.0);

	float sunglow = CalculateSunglow(viewDir, lightVector);



	float cloudsAltitude = 540.0f;
	float cloudsThickness = 150.0f;

	float cloudsUpperLimit = cloudsAltitude + cloudsThickness * 0.5f;
	float cloudsLowerLimit = cloudsAltitude - cloudsThickness * 0.5f;

	float density = 1.0f;

	float planeHeight = cloudsUpperLimit;
	float stepSize = 25.5f;
	planeHeight -= cloudsThickness * 0.85f;


	Plane pl;
	pl.origin = vec3(0.0f, cameraPosition.y - planeHeight, 0.0f);
	pl.normal = vec3(0.0f, 1.0f, 0.0f);

	Intersection intersection = RayPlaneIntersectionWorld(viewRay, pl);

	vec3 original = color.rgb;

	if (intersection.angle < 0.0f)
	{
		vec4 cloudSample = CloudColor(vec4(intersection.pos.xyz * 0.5f + vec3(30.0f) + vec3(1000.0, 0.0, 0.0), 1.0f), sunglow, worldLightVector, cloudsAltitude, cloudsThickness, false);
		 	 cloudSample.a = min(1.0f, cloudSample.a * density);


		float cloudDist = length(intersection.pos.xyz - cameraPosition.xyz);

		const vec3 absorption = vec3(0.2, 0.4, 1.0);

		cloudSample.rgb *= exp(-cloudDist * absorption * 0.0001 * saturate(1.0 - sunglow * 2.0) * (1.0 - rainStrength));

		cloudSample.a *= exp(-cloudDist * (0.0002 + rainStrength * 0.0029));


		//cloudSample.rgb *= sin(cloudDist * 0.3) * 0.5 + 0.5;

		color.rgb = mix(color.rgb, cloudSample.rgb * 1.0f, cloudSample.a);
	}
}

void main()
{
	vec3 finalComposite = vec3(0.0f);
	vec3 skyCol = vec3(0.0f);

if (skyCoord.s <= 1.0f && skyCoord.s >= 0.0f
 && skyCoord.t <= 1.0f && skyCoord.t >= 0.0f)
{
	float depth = texture2D(depthtex1, skyCoord.st).x;

	vec4 viewPos      = GetViewPositionRaw(skyCoord.st, depth);
		 viewPos     *= (isEyeInWater > 0.5) ? 0.8 : 1.0;
	vec4 worldPos     = gbufferModelViewInverse * vec4(viewPos.xyz, 0.0);
	vec3 viewDir      = normalize(viewPos.xyz);
	vec3 worldDir     = normalize(worldPos.xyz);
	float linearDepth = length(viewPos.xyz);



	float nightBrightness = 0.00025 * (1.0 + 32.0 * nightVision);

	vec3 atmosphere = AtmosphericScattering(vec3(worldDir.x, (worldDir.y), worldDir.z), worldSunVector, 1.0);
	atmosphere = mix(atmosphere, vec3(0.6) * Luminance(colorSkylight), vec3(rainStrength * 0.95));

	skyCol = atmosphere;

	vec3 moonAtmosphere = AtmosphericScattering(vec3(worldDir.x, (worldDir.y), worldDir.z), -worldSunVector, 1.0);
	moonAtmosphere = mix(moonAtmosphere, vec3(0.6) * nightBrightness, vec3(rainStrength * 0.95));

	skyCol += moonAtmosphere * nightBrightness;


	vec3 sunDisc = vec3(RenderSunDisc(worldDir, worldSunVector));
		 sunDisc *= colorSunlight;
		 sunDisc *= pow(saturate(worldSunVector.y + 0.1), 0.9);

	skyCol += sunDisc * 5000.0 * pow(1.0 - rainStrength, 5.0);


	CloudPlane(skyCol, viewDir, -worldDir, linearDepth, worldLightVector, lightVector, depth);

	skyCol = LinearToGamma(skyCol * 0.0001);
}



if (envCoord.s <= 1.0f && envCoord.s >= 0.0f
 && envCoord.t <= 1.0f && envCoord.t >= 0.0f)
{
	GbufferData gbuffer       = GetGbufferData(envCoord);
	MaterialMask materialMask = CalculateMasks(gbuffer.materialID);


	vec4 viewPos            = GetViewPosition(envCoord.st, gbuffer.depth);
	vec4 viewPosTransparent = GetViewPosition(envCoord.st, texture2D(gdepthtex, envCoord.st).x);

	if (isEyeInWater > 0.5)
	{
		viewPos.xy *= 0.80;
	}

	vec4 worldPos     = gbufferModelViewInverse * vec4(viewPos.xyz, 0.0);
	vec3 viewDir      = normalize(viewPos.xyz);
	vec3 worldDir     = normalize(worldPos.xyz);
	vec3 worldNormal  = normalize((gbufferModelViewInverse * vec4(gbuffer.normal, 0.0)).xyz);


	if (materialMask.water > 0.5 || materialMask.ice > 0.5)
	{
		gbuffer.mcLightmap = CurveBlockLightSky(texture2D(composite, envCoord.st).g);
	}


	//grass points up
	if (materialMask.grass > 0.5)
	{
		worldNormal = vec3(0.0, 1.0, 0.0);
	}

	float ao = 1.0;

	//shading from sky
	vec3 skylight = FromSH(skySHR, skySHG, skySHB, worldNormal);
	skylight = mix(skylight, vec3(0.3) * (dot(worldNormal, vec3(0.0, 1.0, 0.0)) * 0.35 + 0.65) * Luminance(colorSkylight), vec3(rainStrength));
	skylight *= gbuffer.mcLightmap;
	
	finalComposite += skylight * 2.0 * ao;





	if(rainStrength <= 0.99) {
		//sunlight
		float sunlightMult = 12.0 * exp(-contextualFogFactor * 2.5) * (1.0 - rainStrength) * SUNLIGHT_INTENSITY;

		float sunlight = OrenNayar(worldNormal, -worldDir, worldLightVector);
		if (materialMask.leaves > 0.5)
		{
			sunlight = 0.5;
		}
		if (materialMask.grass > 0.5)
		{
			gbuffer.metallic = 0.0;
		}

		if (materialMask.water > 0.5 || isEyeInWater > 0.5)
		{
			sunlight *= CalculateWaterCaustics(viewPos, materialMask);
		}


		sunlight *= pow(gbuffer.mcLightmap, 0.1 + isEyeInWater * 0.4);

		vec3 shadow = CalculateSunlightVisibility(viewPos, materialMask);
			 shadow *= gbuffer.parallaxShadow;

		finalComposite += sunlight * shadow * sunlightMult * colorSunlight;
	}





	finalComposite *= 0.0001;
}

	vec2 waveNorm = texture2D(gnormal, texcoord.st).rg;
/* DRAWBUFFERS:26 */
	gl_FragData[0] = vec4(waveNorm, skyCol.rg);
	gl_FragData[1] = vec4(LinearToGamma(finalComposite), skyCol.b);
}