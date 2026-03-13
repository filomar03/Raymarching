#version 330 core

#define FOV 70
#define CAM_Z_OFFSET 1

#define MAX_STEPS 80
#define HIT_DISTANCE 0.001
#define MAX_DISTANCE 300.0

uniform vec2 uResolution;
uniform float uTime;
out vec4 FragColor;

float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float map(vec3 p) {
    vec3 sphere_origin = vec3(0, 0, 2);
    return sdSphere(sphere_origin - p, 2);
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1;
    vec3 origin = vec3(uv.xy, 0);
    vec3 camera = vec3(0, 0, -CAM_Z_OFFSET);
    vec3 ray = normalize(origin - camera);

    vec3 p = origin;
    float distance = 0.0;
    int step = 0;

    while (true) {
        float d = map(p);

        distance += d;

        p += ray * d;

        step += 1;
        if (step >= MAX_STEPS) {
            break;
        }
    }

    FragColor = vec4(vec3(distance / 4), 1.0);
}
