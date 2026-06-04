#version 330 core

// Uniforms
uniform vec2 uResolution;
uniform float uTime;
uniform float uFov;
uniform vec3 uCamPos;
uniform vec4 uCamRot;

// Shader output
out vec4 FragColor;

// Rendering params
#define HIT_DISTANCE 0.0001
#define MAX_STEP 500
#define MAX_TRAVEL 5000.0
#define EPSILON 0.0001

// Structs
struct Light {
    vec3 position;
    bool follow_cam;
    float intensity;
};

struct Material {
    vec3 color;
    float shininess;
};

struct HitInfo {
    float distance;
    int mat_index;
};

// Colors
#define HIT vec3(1.0, 0.95, 0.85)
#define FAR vec3(0.0, 0.0, 0.0)
#define OUT_OF_STEP vec3(0.1, 1.0, 0)

// Lights
// Directional lights dont work this way, but it was a quick
#define DIR_LIGHT -99999999
#define AMBIENT_I 0.15
Light lights[] = Light[](
    Light(vec3(0.0, 3.0, 0.0), true, 0.7),
    Light(vec3(3.0, 7.0, 9.0), false, 0.2),
    Light(normalize(vec3(-1.0, -3.0, 1.0)) * DIR_LIGHT, false, 0.2)
);

// Materials
Material mats[] = Material[](
    Material(vec3(0.1, 0.1, 0.1), 4096),
    Material(vec3(0.1, 0.1, 0.1), 64),
    Material(vec3(0.5, 0.2, 0.6), 512),
    Material(vec3(1.0, 0.7, 0.3), 64),
    Material(vec3(1.0, 0.7, 0.3), 4096),
    Material(vec3(1.0, 0.7, 0.3), 4096)
);

// SDFs
float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

// - Box
// - Cone
// - Cylinder

// Shape operations
// - Revolution
// - Extrusion
// - Round

// Interaction operations
HitInfo opUnion(HitInfo a, HitInfo b) {
    return (a.distance < b.distance) ? a : b;
}

HitInfo opIntersect(HitInfo a, HitInfo b) {
    return (a.distance < b.distance) ? b : a;
}

HitInfo opSubtract(HitInfo a, HitInfo b) {
    HitInfo res = a;
    res.distance = max(a.distance, -b.distance);
    return res;
}

HitInfo opSmoothUnion(HitInfo a, HitInfo b) {
    return a; // NOT IMPLEMENTED!!
}

HitInfo opSmoothIntersect(HitInfo a, HitInfo b) {
    return a; // NOT IMPLEMENTED!!
}

HitInfo opSmoothSubtract(HitInfo a, HitInfo b) {
    return a; // NOT IMPLEMENTED!!
}

// Either map code gets created by cpu every time the scene changes
// or
// The objects are in an UBO and store information about their type
HitInfo map(vec3 p) {
    vec3 sp1_origin = vec3(0, 0, 10) - p;
    vec3 sp2_origin = vec3(5, 0, 12) - p;

    HitInfo sp1 = HitInfo(sdSphere(sp1_origin, 3.0 + abs(sin(uTime * 0.2) * 2.0)), 5);
    HitInfo sp2 = HitInfo(sdSphere(sp2_origin, 8), 5);

    return opSubtract(sp2, sp1);
}

vec3 approx_norm(vec3 p) {
    vec2 h = vec2(EPSILON, 0.0);

    // central difference gradient
    float dx = map(p + h.xyy).distance - map(p - h.xyy).distance;
    float dy = map(p + h.yxy).distance - map(p - h.yxy).distance;
    float dz = map(p + h.yyx).distance - map(p - h.yyx).distance;

    vec3 norm = normalize(vec3(dx, dy, dz));
    return norm;
}

float computeDiffuse(vec3 p, vec3 norm, Light l) { // Lambert model
    vec3 p2l_dir = normalize(l.position - p);
    return max(0, dot(norm, p2l_dir)) * l.intensity;
}

float computeSpecular(vec3 p, vec3 norm, Light l, Material mat) { // Phong model
    vec3 l2p_dir = normalize(p - l.position);
    vec3 reflection = reflect(l2p_dir, norm);
    vec3 p2cam_dir = normalize(uCamPos - p);
    return pow(max(0, dot(reflection, p2cam_dir)), mat.shininess);
}

vec3 rotate(vec4 q, vec3 p) { // fast formula to rotate a point with a unit quaternion
    return p + 2 * q.w * cross(q.xyz, p) + 2 * cross(q.xyz, cross(q.xyz, p));
}

void main()
{
    float aspect_ratio = uResolution.x / uResolution.y;
    float tan_half_fov = tan(radians(uFov * 0.5)); // projection plane half height over near distance factor
    vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1; // normalize
    uv *= vec2(tan_half_fov); // scale to adjust for FOV (no need to mul by near since it's 1)
    uv.x *= aspect_ratio; // scale x to maintain ratio

    vec3 ray = normalize(rotate(uCamRot, vec3(uv, 1))); // near is set to 1, since changing it doesn't affect the rendering (for now)

    vec3 p = uCamPos;
    float travel = 0.0;
    int step = 0;

    while (true) {
        HitInfo hit = map(p);

        travel += hit.distance;

        p += ray * hit.distance;

        if (hit.distance <= HIT_DISTANCE) {
            vec3 norm = approx_norm(p);
            Material mat = mats[hit.mat_index];

            float ambient = AMBIENT_I;
            float diffuse = 0.0;
            float specular = 0.0;

            for (int i = 0; i < lights.length(); i++) {
                Light l = lights[i];

                if (l.follow_cam) {
                    l.position += uCamPos;
                }

                diffuse += computeDiffuse(p, norm, l);
                if (mat.shininess > 0) {
                    specular += computeSpecular(p, norm, l, mat);
                }
            }

            FragColor = vec4((ambient + diffuse + specular) * mat.color, 1);
            return;
        }

        if (step > MAX_STEP) {
            FragColor = vec4(OUT_OF_STEP, 1);
            return;
        }

        if (travel > MAX_TRAVEL) {
            FragColor = vec4(FAR, 1);
            return;
        }

        step += 1;
    }
}
