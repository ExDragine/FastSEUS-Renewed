#version 120


varying vec4 texcoord;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float sunAngle;

varying vec3 lightVector;
varying vec3 upVector;

void main() {
	gl_Position = ftransform();
	
	texcoord = gl_MultiTexCoord0;

	if (sunAngle < 0.5f) {
		lightVector = normalize(sunPosition);
	} else {
		lightVector = normalize(moonPosition);
	}

	upVector = normalize(upPosition);

	
}
