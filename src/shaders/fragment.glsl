#version 330 core

#define MAX_DISTANCE 300.0
#define MAX_STEPS 80
#define HIT_DISTANCE 0.0001

uniform vec2 uResolution;
out vec4 FragColor;

vec3 origin = vec3(gl_FragCoord.xy, 0);

float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float map(vec3 p) {
    vec3 sphere_origin = vec3(origin.xy, 5);
    return sdSphere(sphere_origin - p, 3);
}

void main()
{
    vec3 camera = vec3(uResolution / 2, -100);
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

    FragColor = vec4(vec3(distance / 15), 1.0);
}
