#version 330 core

out float Distance;

uniform vec2 uResolution;
uniform float uFov;
uniform vec3 uCamPos;
uniform vec4 uCamRot;
uniform float uCrankAngle;

// - RENDERING PARAMS
#define MAX_STEP 1000
#define HIT_DISTANCE 0.001
#define MAX_TRAVEL 30.0
// MAX_TRAVEL ISN'T an hard limit. It can be exceeded cause HIT_DISTANCE is checked first while marching
#define RELAX_MOD 0.8
#define INFLATE_MOD 0.05

vec3 rotate(vec4 q, vec3 p) { // fast formula to rotate a point with a unit quaternion
    return p + 2 * q.w * cross(q.xyz, p) + 2 * cross(q.xyz, cross(q.xyz, p));
}

float coneMarch(vec3 p, vec3 ray) {
    int step = 0;
    float travel = 0;

    float ratio = uResolution.x / uResolution.y;
    float rad_per_pixel = radians(uFov) / (2 * uResolution.y)
    float depth_pixel_size_ratio = tan(rad_per_pixel);
    float pixel_diag = sqrt(1 + ratio * ratio);

    while (step < MAX_STEP) {
        float distance = map(p);

        if (dist - INFLATE_MOD <= cone_r) {
            return travel + distance;
        }

        if (travel > MAX_TRAVEL) {
            return MAX_TRAVEL;
        }

        distance *= RELAX_MOD;
        p += ray * distance;
        travel += distance;

        float cone_r = travel * depth_pixel_size_ratio * ;
        // cone that cover the entire pixel (radius = pixel diag)

        step++;
    }

    return travel;
}

void main()
{
    computeFrameValues(); // This computes constant that mantain their values for the entire frame,
                          // it has to be done this way cause the model is hardcoded in shader

    float aspect_ratio = uResolution.x / uResolution.y;
    float fov_scale = tan(radians(uFov / 2)); // projection plane half height over near distance factor
    vec2 ndc = gl_FragCoord.xy / uResolution * 2.0 - 1;
    ndc *= fov_scale; // scale to adjust for FOV (no need to mul by near since it's 1)
    ndc.x *= aspect_ratio; // scale x to maintain ratio

    vec3 p = uCamPos;
    vec3 ray = normalize(rotate(uCamRot, vec3(ndc, 1))); // near fixes as 1, since it doesn't work
                                                         // like in traditional rendering
    Distance = coneMarch(p, ray);
}
