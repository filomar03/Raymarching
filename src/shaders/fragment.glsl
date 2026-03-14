#version 330 core

#define MAX_STEPS 80
#define HIT_DISTANCE 0.001
#define MAX_DISTANCE 50.0

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uMouse;
uniform float uFov;
out vec4 FragColor;

float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float map(vec3 p) {
    vec3 sp1_origin = vec3(-5, 0, 10);
    vec3 sp2_origin = vec3(10, 0, 20);
    float sp1 = sdSphere(sp1_origin - p, 3.0 + abs(sin(uTime) * 5.0));
    float sp2 = sdSphere(sp2_origin - p, 8);
    return min(sp1, sp2);
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1;
    float cam_z_offset = 1.0 / tan(radians(uFov));
    vec3 origin = vec3(uv.xy, 0);
    vec3 camera = vec3(0, 0, -cam_z_offset);
    vec3 ray = normalize(origin - camera);

    vec3 p = origin;
    float distance = 0.0;
    int step = 0;

    while (true) {
        float d = map(p);

        distance += d;

        p += ray * d;

        step += 1;
        if (step > MAX_STEPS) {
            break;
        }

        if (distance <= HIT_DISTANCE) {
            break;
        }
    }

    FragColor = vec4(vec3(distance / MAX_DISTANCE), 1.0);
}
