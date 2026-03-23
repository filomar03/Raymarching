#version 330 core

// Rendering params
#define HIT_DISTANCE 0.01
#define MAX_STEP 300
#define MAX_TRAVEL 5000.0
#define EPSILON 0.0001

// Colors
#define HIT vec4(1, 1, 1, 1)
#define FAR vec4(0, 0, 0, 0)
#define OUT_OF_STEP vec4(1, 0, 0, 1)

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uMouse;
uniform float uFov;
out vec4 FragColor;

float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float map(vec3 p) {
    vec3 sp1_origin = vec3(0, 0, 10);
    vec3 sp2_origin = vec3(10, 0, 20);

    float sp1 = sdSphere(sp1_origin - p, 3.0 + abs(sin(uTime * 0.3) * 5.0));
    float sp2 = sdSphere(sp2_origin - p, 8);

    return min(sp1, sp2);
}

vec3 approx_norm(vec3 p) {
    // metodo differenza centrale
    vec2 h = vec2(EPSILON, 0.0);

    float dx = map(p + h.xyy) - map(p - h.xyy);
    float dy = map(p + h.yxy) - map(p - h.yxy);
    float dz = map(p + h.yyx) - map(p - h.yyx);

    vec3 norm = normalize(vec3(dx, dy, dz));
    return norm;
}

void main()
{
    vec2 ndc = gl_FragCoord.xy / uResolution * 2.0 - 1;
    vec2 aspect_ratio = vec2(1, 1 / (uResolution.x / uResolution.y));
    ndc *= aspect_ratio;
    float cam_z_offset = 1.0 / tan(radians(uFov));

    vec3 origin = vec3(ndc.xy, 0);
    vec3 camera = vec3(0, 0, -cam_z_offset);
    vec3 ray = normalize(origin - camera);

    vec3 p = origin;
    float travel = 0.0;
    int step = 0;

    while (true) {
        float d = map(p);

        travel += d;

        p += ray * d;

        if (d <= HIT_DISTANCE) {
            FragColor = vec4(approx_norm(p).xy, -approx_norm(p).z, 1);
            // FragColor = HIT;
            return;
        }

        if (step > MAX_STEP) {
            FragColor = OUT_OF_STEP;
            return;
        }

        if (travel > MAX_TRAVEL) {
            FragColor = FAR;
            return;
        }

        step += 1;
    }
}
