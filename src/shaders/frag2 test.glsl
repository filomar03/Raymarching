#version 330 core

out vec4 FragColor;

uniform sampler2D sampler;
uniform vec2 uResolution;

// We know from Pass 1 that the max distance is 100.0
#define MAX_TRAVEL 100.0

void main() {
    // 1. Normalize the screen coordinates
    vec2 uv = gl_FragCoord.xy / uResolution;

    // 2. Read the raw distance from the R32F texture
    float travel = texture(sampler, uv).r;

    // 3. Scale the distance down to a 0.0 -> 1.0 range
    // Now, 0.0 is right in your face, and 1.0 (100 units away) is the skybox
    float depthColor = travel / MAX_TRAVEL;

    // OPTIONAL: Invert it so closer objects are brighter and the sky is black
    // depthColor = 1.0 - depthColor;

    FragColor = vec4(vec3(depthColor), 1.0);
}
