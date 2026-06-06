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
    vec3 color;
    float intensity;
};

struct Material {
    vec3 color;
    float shininess;
    float reflectivity;
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
#define DIR_LIGHT 99999999
#define AMBIENT_I 0.15
Light lights[] = Light[](
    Light(vec3(0.0, 0.0, 0.0), true, vec3(1), 0.7),
    Light(normalize(vec3(1.0, 3.0, -1.0)) * DIR_LIGHT, false, vec3(1), 0.2)
);

// Materials
Material mats[] = Material[](
    Material(vec3(0.25, 0.25, 0.28), 16.0, 0.2),  // engine block
    Material(vec3(0.80, 0.82, 0.85), 128.0, 0.7), // piston
    Material(vec3(0.75, 0.55, 0.25), 128.0, 0.6), // conrod
    Material(vec3(0.70, 0.70, 0.75), 512.0, 0.7), // crankshaft
    Material(vec3(0.65, 0.65, 0.70), 512.0, 0.7), // camshaft
    Material(vec3(0.85, 0.85, 0.90), 256.0, 0.3), // valves
    Material(vec3(0.35, 0.35, 0.40), 64.0, 0.5)   // timing gear
);

// SDFs (formule sdf prese da: https://iquilezles.org/articles/distfunctions/)
float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float sdBox2D(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
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

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// questa sdf specifica, non essendo comune l'ho creata con l'aiuto dell'intelligenza artificiale
float sdGear(vec3 p, float r, float w, float teeth, float angle) {
    float c = cos(angle), s = sin(angle);
    mat2 rot = mat2(c, -s, s, c);
    vec2 p2 = rot * p.xy;
    float a = atan(p2.y, p2.x);
    float r_mod = r + 0.15 * sin(a * teeth);
    vec2 d = vec2(length(p2) - r_mod, abs(p.z) - w);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// Shape operations
float opUnion(float a, float b) {
    return min(a, b);
}

float opIntersect(float a, float b) {
    return max(a, b);
}

float opSubtract(float a, float b) {
    return max(a, -b);
}

float opSmoothUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    float d = mix(b, a, h) - k * h * (1.0 - h);
    return d;
}

float opSmoothIntersect(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (b - a) / k, 0.0, 1.0);
    float d = mix(b, a, h) + k * h * (1.0 - h);
    return d;
}

float opSmoothSubtract(float a, float b, float k) {
    float h = clamp(0.5 - 0.5 * (a + b) / k, 0.0, 1.0);
    float d = mix(a, -b, h) + k * h * (1.0 - h);
    return d;
}

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

#define MOTORE

HitInfo map(vec3 p) {
#ifdef MOTORE
    // scena motore
#endif
#ifndef MOTORE
    // scena con forme smooth union in movimento e dei riflessi
#endif
    return scene;
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

vec3 computeSpecular(vec3 p, vec3 norm, Light l, Material mat) { // Phong model
    vec3 l2p_dir = normalize(p - l.position);
    vec3 reflection = reflect(l2p_dir, norm);
    vec3 p2cam_dir = normalize(uCamPos - p);
    return pow(max(0, dot(reflection, p2cam_dir)), mat.shininess) * l.color;
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
            vec3 specular = vec3(0);

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

            //rifare cosi:

            // loop max bounce, raggio perde energia ogni rimbalzo
            //      calcolo parte non riflessa
            //      mi fermo se non rifletto piu

            FragColor = vec4((ambient + diffuse) * mat.color + specular, 1);
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
