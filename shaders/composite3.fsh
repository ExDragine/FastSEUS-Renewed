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




#define RAYLEIGH_AMOUNT 1.0 // Density of atmospheric scattering. [0.5 1.0 1.5 2.0 3.0 4.0]

#define SUNLIGHT_INTENSITY 1.0 // Intensity of sunlight. [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]


const int 		noiseTextureResolution  = 64;


/* DRAWBUFFERS:6 */


const bool gaux3MipmapEnabled = true;

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
varying vec3 sunVector;

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

varying vec3 worldSunVector;

uniform float blindness;
uniform float nightVision;

#define ANIMATION_SPEED 1.0f


#define FRAME_TIME frameTimeCounter * ANIMATION_SPEED

/////////////////////////FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////FUNCTIONS/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

vec4 GetViewPosition(in vec2 coord, in float depth) 
{	
	vec4 fragposition = gbufferProjectionInverse * vec4(coord.s * 2.0f - 1.0f, coord.t * 2.0f - 1.0f, 2.0f * depth - 1.0f, 1.0f);
		 fragposition /= fragposition.w;
	
	return fragposition;
}

float 	ExpToLinearDepth(in float depth)
{
	return 2.0f * near * far / (far + near - (2.0f * depth - 1.0f) * (far - near));
}

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

float CurveBlockLightSky(float blockLight)
{
	//blockLight = pow(blockLight, 3.0);

	//blockLight = InverseSquareCurve(1.0 - blockLight, 0.2);
	blockLight = 1.0 - pow(1.0 - blockLight, 0.45);
	blockLight *= blockLight * blockLight;

	return blockLight;
}

float CurveBlockLightTorch(float blockLight)
{

///*
	float falloff = 10.0;

	blockLight = exp(-(1.0 - blockLight) * falloff);
	blockLight = max(0.0, blockLight - exp(-falloff));
//*/

/*
	float lightmap = blockLight;

	//Apply inverse square law and normalize for natural light falloff
	lightmap 		= clamp(lightmap * 1.22f, 0.0f, 1.0f);
	lightmap 		= 1.0f - lightmap;
	lightmap 		*= 5.6f;
	lightmap 		= 1.0f / pow((lightmap + 0.8f), 2.0f);
	lightmap 		-= 0.02435f;

	// if (lightmap <= 0.0f)
		// lightmap = 1.0f;

	lightmap 		= max(0.0f, lightmap);
	lightmap 		*= 0.008f;
	lightmap 		= clamp(lightmap, 0.0f, 1.0f);
	lightmap 		= pow(lightmap, 0.9f);


	blockLight = lightmap * 10.0;
*/
	return blockLight;
}

vec3 	CalculateNoisePattern1(vec2 offset, float size) 
{
	vec2 coord = texcoord.st;

	coord *= vec2(viewWidth, viewHeight);
	coord = mod(coord + offset, vec2(size));
	coord /= noiseTextureResolution;

	return texture2D(noisetex, coord).xyz;
}

float GetDepthLinear(in vec2 coord) 
{					
	return (near * far) / (texture2D(depthtex1, coord).x * (near - far) + far);
}

vec3 GetNormals(vec2 coord)
{
	return DecodeNormal(texture2D(gnormal, coord).xy);
}

/////////////////////////STRUCTS///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////STRUCTS///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct GbufferData
{
	vec3 albedo;
	vec3 normal;
	float depth;
	vec2 mcLightmap;
	float smoothness;
	float metallic;
	float emissive;
	float materialID;
};


struct MaterialMask
{
	float sky;
	float land;
	float grass;
	float leaves;
	float hand;
	float entityPlayer;
	float water;
	float stainedGlass;
	float ice;
};


/////////////////////////STRUCT FUNCTIONS//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////STRUCT FUNCTIONS//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

GbufferData GetGbufferData()
{
	GbufferData data;


	vec3 gbuffer0 = texture2D(gcolor, texcoord.st).rgb;
	vec3 gbuffer1 = texture2D(gdepth, texcoord.st).rgb;
	vec2 gbuffer2 = texture2D(gnormal, texcoord.st).rg;
	vec3 gbuffer3 = texture2D(composite, texcoord.st).rgb;
	float depth = texture2D(gdepthtex, texcoord.st).x;


	data.albedo = GammaToLinear(gbuffer0);

	data.mcLightmap = gbuffer3.rg;
	data.mcLightmap.g = CurveBlockLightSky(data.mcLightmap.g);
	data.mcLightmap.r = CurveBlockLightTorch(data.mcLightmap.r);
	data.emissive = gbuffer1.b;

	data.normal = DecodeNormal(gbuffer2);

	data.smoothness = gbuffer3.r;
	data.metallic = gbuffer3.g;
	data.materialID = gbuffer3.b;

	data.depth = depth;

	return data;
}

MaterialMask CalculateMasks(float materialID)
{
	MaterialMask mask;

	materialID *= 255.0;

	if (isEyeInWater > 0)
		mask.sky = 0.0f;
	else
		mask.sky = GetMaterialMask(0, materialID);

	mask.land 			= GetMaterialMask(1, materialID);
	mask.grass 			= GetMaterialMask(2, materialID);
	mask.leaves 		= GetMaterialMask(3, materialID);
	mask.hand 			= GetMaterialMask(4, materialID);
	mask.entityPlayer 	= GetMaterialMask(5, materialID);
	mask.water 			= GetMaterialMask(6, materialID);
	mask.stainedGlass	= GetMaterialMask(7, materialID);
	mask.ice 			= GetMaterialMask(8, materialID);

	return mask;
}

float GetMaterialIDs(vec2 coord)
{
	return texture2D(composite, coord).b;
}

vec3  	GetWaterNormals(in vec2 coord) {				//Function that retrieves the screen space surface normals. Used for lighting calculations
	return DecodeNormal(texture2D(gaux1, coord).xy);
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




void FixNormals(inout vec3 normal, in vec3 viewPosition)
{
	vec3 V = normalize(viewPosition.xyz);
	vec3 N = normal;

	float NdotV = dot(N, V);

	N = normalize(mix(normal, -V, clamp(pow((NdotV * 1.0), 1.0), 0.0, 1.0)));
	N = normalize(N + -V * 0.1 * clamp(NdotV + 0.4, 0.0, 1.0));

	normal = N;
}

vec3 GetWavesNormal(vec3 position, float time) {

	vec2 coord = position.xz / 50.0;
	coord.xy -= position.y / 50.0;
	//coord -= floor(coord);

	coord = mod(coord, vec2(1.0));


	float texelScale = 1.0;

	//to fix color error with GL_CLAMP
	coord.x = coord.x * ((viewWidth - 1 * texelScale) / viewWidth) + ((0.5 * texelScale) / viewWidth);
	coord.y = coord.y * ((viewHeight - 1 * texelScale) / viewHeight) + ((0.5 * texelScale) / viewHeight);

	coord *= 0.1995f;

	//coord.xy = clamp(coord.xy, (0.5 / vec2(viewWidth, viewHeight)), 1.0 - (0.5 / vec2(viewWidth, viewHeight)));

	vec3 normal;
	if (coord.s <= 1.0f && coord.s >= 0.0f
	 && coord.t <= 1.0f && coord.t >= 0.0f)
	{
		normal.xyz = DecodeNormal(texture2D(gaux1, coord).zw);
	}

	return normal;
}


void WaterRefraction(inout vec3 color, MaterialMask mask, vec4 worldSpacePosition, float waterDepth, float opaqueDepth, out vec2 refractionCoord)
{
	refractionCoord = texcoord.st;

	if (mask.water > 0.5 || mask.ice > 0.5 || mask.stainedGlass > 0.5)
	{
		vec3 wavesNormal;
		if (mask.water > 0.5)
			 wavesNormal = GetWavesNormal(worldSpacePosition.xyz + cameraPosition.xyz, frameTimeCounter).xzy;
		else if (mask.ice > 0.5 || mask.stainedGlass > 0.5)
		{
			 wavesNormal = vec3(0.0, 1.0, 0.0);
		}

		if (mask.stainedGlass > 0.5)
		{
			if (texture2D(gaux2, texcoord.st).a >= 0.99)
			{
				return;
			}
		}


		float waterDeep = opaqueDepth - waterDepth;

		float refractAmount = saturate(waterDeep / 1.0) * 0.125;

		if (mask.ice > 0.5 || mask.stainedGlass > 0.5)
		{
			refractAmount *= 0.5;
		}

		if (isEyeInWater > 0)
		{
			refractAmount *= 2.0;
		}

		vec4 wnv = gbufferModelView * vec4(wavesNormal.xyz, 0.0);
		vec3 wavesNormalView = normalize(wnv.xyz);
		vec4 nv = gbufferModelView * vec4(0.0, 1.0, 0.0, 0.0);
			   nv.xyz = normalize(nv.xyz);
				 wavesNormalView.xy -= nv.xy;
		float aberration = 0.2;
		float refractionAmount = 1.82;
		vec2 refractCoord0 = texcoord.st - wavesNormalView.xy * refractAmount * (refractionAmount) / (waterDepth + 0.0001);
		vec2 refractCoord1 = texcoord.st - wavesNormalView.xy * refractAmount * (refractionAmount + aberration) / (waterDepth + 0.0001);
		vec2 refractCoord2 = texcoord.st - wavesNormalView.xy * refractAmount * (refractionAmount + aberration * 2.0) / (waterDepth + 0.0001);
		

		float fogDensity = 0.40;
		float visibility = 1.0f / (pow(exp(waterDeep * fogDensity), 1.0f));


		float blendWeights = pow(0.46875, visibility);

		float blendWeightsTotal = dot(vec4(1.0, 0.5, 0.25, 0.125), vec4(1.0));

		color.r = pow(texture2DLod(gaux3, refractCoord0.xy, 2.5).r, (2.2));
		color.g = pow(texture2DLod(gaux3, refractCoord1.xy, 2.5).g, (2.2));
		color.b = pow(texture2DLod(gaux3, refractCoord2.xy, 2.5).b, (2.2));
		color = (color * blendWeights * 4.0f) / blendWeightsTotal;

		//color = vec3(refractAmount * 0.00001);

		refractionCoord = refractCoord0.xy;
	}
}

vec3 convertScreenSpaceToWorldSpace(vec2 co) {
    vec4 fragposition = gbufferProjectionInverse * vec4(vec3(co, texture2DLod(gdepthtex, co, 0).x) * 2.0 - 1.0, 1.0);
    fragposition /= fragposition.w;
    return fragposition.xyz;
}

vec3 convertCameraSpaceToScreenSpace(vec3 cameraSpace) {
    vec4 clipSpace = gbufferProjection * vec4(cameraSpace, 1.0);
    vec3 NDCSpace = clipSpace.xyz / clipSpace.w;
    vec3 screenSpace = 0.5 * NDCSpace + 0.5;
		 screenSpace.z = 0.1f;
    return screenSpace;
}

vec4 	ComputeRaytraceReflection(vec3 normal, bool edgeClamping)
{
    float initialStepAmount = 1.0 - clamp(0.1f / 100.0, 0.0, 0.99);

    vec3 cameraSpacePosition = convertScreenSpaceToWorldSpace(texcoord.st) + (rand(texcoord.st + sin(frameTimeCounter)).xyz * 2.0 - 1.0) * 0.005;
    vec3 cameraSpaceNormal = normal;

    vec3 cameraSpaceViewDir = normalize(cameraSpacePosition);
    vec3 cameraSpaceVector = initialStepAmount * normalize(reflect(cameraSpaceViewDir,cameraSpaceNormal));
    vec3 cameraSpaceVectorFar = far * normalize(reflect(cameraSpaceViewDir, cameraSpaceNormal));
    vec3 cameraSpaceVectorPosition = cameraSpacePosition + cameraSpaceVector;
    vec3 currentPosition = convertCameraSpaceToScreenSpace(cameraSpaceVectorPosition);

    const int maxRefinements = 3;
	int numRefinements = 0;
    int count = 0;
	vec2 finalSamplePos = vec2(0.0f);

	int numSteps = 0;

	float finalSampleDepth = 0.0;

    for (int i = 0; i < 20; i++)
    {
        if(
           -cameraSpaceVectorPosition.z > far * 1.4f ||
           -cameraSpaceVectorPosition.z < 0.0f)
        {
		   break;
		}

        vec2 samplePos = currentPosition.xy;
        float sampleDepth = convertScreenSpaceToWorldSpace(samplePos).z;

        float currentDepth = cameraSpaceVectorPosition.z;
        float diff = sampleDepth - currentDepth;
        float error = length(cameraSpaceVector / pow(2.0f, numRefinements));


        //If a collision was detected, refine raymarch
        if(diff >= 0 && diff <= error * 1.00f && numRefinements <= maxRefinements)
        {
        	//Step back
        	cameraSpaceVectorPosition -= cameraSpaceVector / pow(2.0f, numRefinements);
        	++numRefinements;
		//If refinements run out
		}
		else if (diff >= 0 && diff <= error * 16.0f && numRefinements > maxRefinements)
		{
			finalSamplePos = samplePos;
			finalSampleDepth = sampleDepth;
			break;
		}



        cameraSpaceVectorPosition += cameraSpaceVector / pow(2.0f, numRefinements);

        if (numSteps > 1)
        cameraSpaceVector *= 1.5f;	//Each step gets bigger

		currentPosition = convertCameraSpaceToScreenSpace(cameraSpaceVectorPosition);

		if (edgeClamping)
		{
			currentPosition = clamp(currentPosition, vec3(0.001), vec3(0.999));
		}
		else if (currentPosition.x < 0 || currentPosition.x > 1 ||
				 currentPosition.y < 0 || currentPosition.y > 1 ||
				 currentPosition.z < 0 || currentPosition.z > 1)
		{
			break;
		}



        count++;
        numSteps++;
    }

	vec4 color = vec4(1.0, 1.0, 1.0, 0.0);
	
	if ((finalSamplePos.x * finalSamplePos.y) != 0.0f) {
		color = vec4(GammaToLinear(texture2D(gaux3, finalSamplePos).rgb), 1.0);
	}


    return color;
}

float RenderSunDisc(vec3 worldDir, vec3 sunDir)
{
	float d = dot(worldDir, sunDir);

	float disc = 0.0;

	//if (d > 0.99)
	//	disc = 1.0;

	float size = 0.00195;
	float hardness = 1000.0;

	disc = pow(curve(saturate((d - (1.0 - size)) * hardness)), 2.0);

	float visibility = curve(saturate(worldDir.y * 30.0));

	disc *= visibility;

	return disc;
}

vec4 ComputeFakeSkyReflection(vec3 dir, vec3 normal, MaterialMask mask, float metallic)
{
	float nightBrightness = 0.00025 * (1.0 + 32.0 * nightVision);


	vec3 worldDir = normalize((gbufferModelViewInverse * vec4(dir.xyz, 0.0)).xyz);

	vec3 sky = AtmosphericScattering(worldDir, worldSunVector, 1.0);
	sky = mix(sky, vec3(0.5) * Luminance(colorSkylight), vec3(rainStrength * 0.95));
	vec3 skyNight = AtmosphericScattering(worldDir, -worldSunVector, 1.0) * nightBrightness;
	skyNight = mix(skyNight, vec3(0.5) * nightBrightness, vec3(rainStrength * 0.95));

	float fresnel = pow(saturate(dot(-dir, normal) + 1.0), 5.0) * 0.98 + 0.02;


	vec3 sunDisc = vec3(RenderSunDisc(worldDir, worldSunVector));
	sunDisc *= normalize(sky + 0.001);
	sunDisc *= 10000.0 * pow(1.0 - rainStrength, 5.0);

	//if (mask.water > 0.5)

	sunDisc *= saturate(mask.water + metallic);
	sky += sunDisc;



	return vec4((sky + skyNight) * 0.0001, fresnel);
	//return vec4(vec3(0.0001), fresnel);
}

void 	CalculateSpecularReflections(inout vec3 color, vec3 normal, MaterialMask mask, vec3 albedo, float smoothness, float metallic, float skylight, vec3 viewVector, vec2 refractionCoord) {

	float specularity = smoothness * smoothness * smoothness;
	      specularity = max(0.0f, specularity * 1.15f - 0.15f);
	vec3 specularColor = vec3(1.0f);
	//surface.specularity = 1.0f;
	//surface.roughness *= surface.roughness;

	metallic = pow(metallic, 2.2);

	bool defaultItself = true;

	//surface.rDepth = 0.0f;

	if (mask.sky > 0.5)
		specularity = 0.0f;


	if (mask.water > 0.5 || mask.ice > 0.5)
	{
		defaultItself = false;
		specularity = 1.0f;
		metallic = 0.0;
		//surface.roughness = 0.0f;
		//surface.fresnelPower = 6.0f;
		//surface.baseSpecularity = 0.02f;
	}
	else
	{
		skylight = CurveBlockLightSky(texture2D(gdepth, texcoord.st).g);
	}

	if (mask.stainedGlass > 0.5)
	{
		specularity = 0.0;
	}


	vec3 original = color.rgb;

	if (specularity > 0.00f) 
	{
		if (isEyeInWater > 0 && mask.water > 0.5)
		{
			float totalInternalReflectionMask = texture2D(gnormal, refractionCoord.st).b;
			vec4 reflection = ComputeRaytraceReflection(normal, true);
			reflection.a *= totalInternalReflectionMask;

			color.rgb = mix(color.rgb, reflection.rgb, vec3(reflection.a));

		}
		else
		{
			vec4 reflection = ComputeRaytraceReflection(normal, false);
			//vec4 reflection = vec4(0.0f);

			vec3 reflectVector = reflect(viewVector, normal);

			vec4 fakeSkyReflection = (reflection.a >= 0.01f) ? vec4(0.0f) : ComputeFakeSkyReflection(reflectVector, normal, mask, metallic);

			vec3 noSkyToReflect = vec3(0.0f);

			if (defaultItself)
			{
				noSkyToReflect = color.rgb;
			}

			fakeSkyReflection.rgb = mix(noSkyToReflect, fakeSkyReflection.rgb, clamp(skylight * 16 - 5, 0.0f, 1.0f));
			reflection.rgb = mix(reflection.rgb, fakeSkyReflection.rgb, pow(vec3(1.0f - reflection.a), vec3(10.1f)));
			reflection.a = fakeSkyReflection.a * specularity;


			//reflection.rgb *= specularColor;
			reflection.a = mix(reflection.a, 1.0, metallic);
			reflection.rgb *= mix(vec3(1.0), albedo.rgb, vec3(metallic));

			color.rgb = mix(color.rgb, reflection.rgb, vec3(reflection.a));
			reflection = reflection;
		}
	}

	//color.rgb = mix(color.rgb, original, vec3(surface.cloudAlpha));
}

void TransparentAbsorption(inout vec3 color, MaterialMask mask, vec4 worldSpacePosition, float waterDepth, float opaqueDepth)
{
	if (mask.stainedGlass > 0.5)
	{
		vec4 transparentAlbedo = texture2D(gaux2, texcoord.st);

		transparentAlbedo.rgb = GammaToLinear(transparentAlbedo.rgb);

		transparentAlbedo.rgb = pow(length(transparentAlbedo.rgb), 0.5) * normalize(transparentAlbedo.rgb + 0.00001);

		color *= transparentAlbedo.rgb * 2.0;
	}

}


void LandAtmosphericScattering(inout vec3 color, in vec3 viewPos, in vec3 viewDir)
{
	float dist = length(viewPos);

	float fogDensity = 0.003 * RAYLEIGH_AMOUNT;
		  fogDensity *= mix(0.0f, 1.0f, pow(eyeBrightnessSmooth.y / 240.0f, 6.0f));
	
	float fogFactor = pow(1.0 - exp(-dist * fogDensity), 2.0);


	vec3 absorption = vec3(0.2, 0.45, 1.0);

	color *= exp(-dist * absorption * fogDensity * 0.27);
	color += max(vec3(0.0), vec3(1.0) - exp(-fogFactor * absorption)) * mix(colorSunlight, vec3(dot(colorSunlight, vec3(0.33333))), vec3(0.9)) * 2.0;

	float VdotL = dot(viewDir, sunVector);

	float g = 0.72;
				//float g = 0.9;
	float g2 = g * g;
	float theta = VdotL * 0.5 + 0.5;
	float anisoFactor = 1.5 * ((1.0 - g2) / (2.0 + g2)) * ((1.0 + theta * theta) / (1.0 + g2 - 2.0 * g * theta)) + g * theta;

	

	color += colorSunlight * fogFactor * 0.6 * anisoFactor;

}

void RainFog(inout vec3 color, in vec3 worldPos)
{

	float dist = length(worldPos);
	vec3 worldDir = worldPos / dist;

	float fogDensity = 0.006;
		  fogDensity *= mix(0.0f, 1.0f, pow(eyeBrightnessSmooth.y / 240.0f, 6.0f));
		  fogDensity *= rainStrength;
	
	float fogFactor = pow(1.0 - exp(-dist * fogDensity), 2.0);

	vec3 fogColor = vec3(dot(colorSkylight, vec3(0.18)));

	fogColor *= saturate(worldDir.y * 0.5 + 0.5);

	color = mix(color, fogColor, vec3(fogFactor));

}

void BlindnessFog(inout vec3 color, in vec3 viewPos, in vec3 viewDir)
{
	if (blindness < 0.001)
	{
		return;
	}
	float dist = length(viewPos);

	float fogDensity = 1.0 * blindness;
	
	float fogFactor = pow(1.0 - exp(-dist * fogDensity), 2.0);

	vec3 fogColor = vec3(0.0);

	color = mix(color, fogColor, vec3(fogFactor));
}

/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////MAIN//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void main() 
{

	GbufferData gbuffer 			= GetGbufferData();



	MaterialMask materialMask 		= CalculateMasks(gbuffer.materialID);
	vec4 viewPos 					= GetViewPosition(texcoord.st, gbuffer.depth);
	vec4 worldPos					= gbufferModelViewInverse * vec4(viewPos.xyzw);
	vec3 viewDir 					= normalize(viewPos.xyz);

	vec3 worldDir 					= normalize(worldPos.xyz);
	vec3 worldNormal 				= normalize((gbufferModelViewInverse * vec4(gbuffer.normal, 0.0)).xyz);
	vec3 worldTransparentNormal 	= normalize((gbufferModelViewInverse * vec4(GetWaterNormals(texcoord.st), 0.0)).xyz);


	gbuffer.normal = normalize(gbuffer.normal - viewDir.xyz * (1.0 / (saturate(dot(gbuffer.normal, -viewDir.xyz)) + 0.01) ) * 0.0025);


	vec3 color = GammaToLinear(texture2D(gaux3, texcoord.st).rgb);

	if (materialMask.water > 0.5 || materialMask.ice > 0.5)
	{
		gbuffer.normal = DecodeNormal(texture2D(gaux1, texcoord.st).xy);

		//FixNormals(gbuffer.normal, viewPos.xyz);
	}

	float opaqueDepth = ExpToLinearDepth(texture2D(depthtex1, texcoord.st).x);
	float waterDepth = ExpToLinearDepth(gbuffer.depth);

	vec2 refractionCoord;

	WaterRefraction(color, materialMask, worldPos, waterDepth, opaqueDepth, refractionCoord);

	TransparentAbsorption(color, materialMask, worldPos, waterDepth, opaqueDepth);


	CalculateSpecularReflections(color, gbuffer.normal, materialMask, gbuffer.albedo, gbuffer.smoothness, gbuffer.metallic, gbuffer.mcLightmap.g, viewDir, refractionCoord);

	color /= 0.0001;

	if (materialMask.sky < 0.5)
	{
		LandAtmosphericScattering(color, viewPos.xyz, viewDir);
		RainFog(color, worldPos.xyz);
	}

	BlindnessFog(color, viewPos.xyz, viewDir);

	color *= 0.0001;


	color = LinearToGamma(color);



	gl_FragData[0] = vec4(color.rgb, 1.0);
}
