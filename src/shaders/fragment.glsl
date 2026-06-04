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
// Directional lights quick implementation
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

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - q;
    return lenght(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdCone(vec3 p, vec2 c, float h) {
    vec2 q = h * vec2(c.x / c.y, -1.0);
    vec2 w = vec2(length(p.xz), p.y);
    vec2 a = w - q * clamp(dot(w, q) / dot(q, q), 0.0, 1.0);
    vec2 b = w - q * vec2(clamp(w.x / q.x, 0.0, 1.0), 1.0);
    float k = sign(q.y);
    float d = min(dot(a, a), dot(b, b));
    float s = max(k * (w.x * q.y - w.y * q.x), k * (w.y - q.y));
    return sqrt(d) * sign(s);
}

float sdCylinder(vec3 p, vec2 h) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// Shape operations
vec2 opRevolution(vec3 p, float w) {
    return vec2(length(p.xz) - w, p.y);
}

float opExtrusion(vec3 p, float sdf2d, float h) {
    vec2 w = vec2(sdf2d, abs(p.z) - h);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

float opRound(float sdf, float r) {
    return sdf - r;
}

// Interaction operations
HitInfo opUnion(HitInfo a, HitInfo b) {
    return (a.distance < b.distance) ? a : b;
}

HitInfo opIntersect(HitInfo a, HitInfo b) {
    return (a.distance < b.distance) ? b : a;
}

HitInfo opSubtract(HitInfo a, HitInfo b) {
    HitInfo res = a;
    float d = max(a.distance, -b.distance);
    res.distance = d;
    return res;
}

HitInfo opSmoothUnion(HitInfo a, HitInfo b, float k) {
    HitInfo res = (a.distance < b.distance) ? a : b;
    float h = clamp(0.5 + 0.5 * (b.distance - a.distance) / k, 0.0, 1.0);
    float d = mix(b.distance, a.distance, h) - k * h * (1.0 - h);
    res.distance = d;
    return res;
}

HitInfo opSmoothIntersect(HitInfo a, HitInfo b, float k) {
    HitInfo res = (a.distance > b.distance) ? a : b;
    float h = clamp(0.5 - 0.5 * (b.distance - a.distance) / k, 0.0, 1.0);
    float d = mix(b.distance, a.distance, h) + k * h * (1.0 - h);
    res.distance = d;
    return res;
}

HitInfo opSmoothSubtract(HitInfo a, HitInfo b, float k) {
    HitInfo res = a;
    float h = clamp(0.5 - 0.5 * (a.distance + b.distance) / k, 0.0, 1.0);
    float d = mix(a.distance, -b.distance, h) + k * h * (1.0 - h);
    res.distance = d;
    return res;
}

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
