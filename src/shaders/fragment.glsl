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
#define HIT_DISTANCE 0.001
#define MAX_STEP 500
#define MAX_TRAVEL 5000.0
#define EPSILON 0.001
#define MAX_BOUNCE 3
#define NUDGE 0.01

#define HIT 0
#define FAR 1
#define OUT_OF_STEPS 2

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

struct SceneInfo {
    float distance;
    int mat_index;
};

struct HitInfo {
    int reason;
    float travel;
    int mat_index;
};


// Scene constants
#define COLOR_SKY_BOX vec3(0.75, 0.87, 0.89)
#define COLOR_OUT_OF_STEP vec3(0, 1, 0.24)

#define DIR_LIGHT 99999999
#define AMBIENT_I 0.15
Light lights[] = Light[](
    Light(vec3(0.0, 0.0, 0.0), true, vec3(1), 0.7),
    Light(normalize(vec3(1.0, 3.0, -1.0)) * DIR_LIGHT, false, vec3(1), 0.2)
);

Material mats[] = Material[](
    Material(vec3(0.25, 0.25, 0.28), 16, 0.0),  // engine block
    Material(vec3(0.80, 0.82, 0.85), 128.0, 0.3), // piston
    Material(vec3(0.75, 0.55, 0.25), 128.0, 0.1), // conrod
    Material(vec3(0.70, 0.70, 0.75), 512.0, 0.05), // crankshaft
    Material(vec3(0.65, 0.65, 0.70), 512.0, 0.05), // camshaft
    Material(vec3(0.85, 0.85, 0.90), 256.0, 0.0), // valves
    Material(vec3(0.35, 0.35, 0.40), 64.0, 0.0)   // timing gear
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

float sdLink( vec3 p, float le, float r1, float r2 )
{
  vec3 q = vec3( p.x, max(abs(p.y)-le,0.0), p.z );
  return length(vec2(length(q.xy)-r1,q.z)) - r2;
}

// questa sdf, non essendo comune l'ho creata con l'aiuto dell'intelligenza artificiale
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

// float opRepetition( in vec3 p, in vec3 s, in sdf3d primitive )
// {
//     vec3 q = p - s*round(p/s);
//     return primitive( q );
// }

SceneInfo map(vec3 p) {
    
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

HitInfo rayMarch(vec3 starting_point, vec3 ray, float start_travel, int start_step) {
    vec3 p = starting_point;
    float travel = start_travel;
    int step = start_step;

    while (step < MAX_STEP) {
        SceneInfo scene = map(p);

        travel += scene.distance;
        p += ray * scene.distance;

        if (scene.distance <= HIT_DISTANCE) {
            return HitInfo(HIT, travel, scene.mat_index);
        }

        if (travel > MAX_TRAVEL) {
            return HitInfo(FAR, travel, scene.mat_index);
        }

        step += 1;
    }

    return HitInfo(OUT_OF_STEPS, travel, -1);
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

    float ray_energy = 1.0;
    vec3 final_color;

    for (int bounce = 0; bounce < MAX_BOUNCE; bounce++) {
        HitInfo hit = rayMarch(p, ray, 0, 0);
        p += ray * hit.travel;

        if (hit.reason == HIT) {
            vec3 norm = approx_norm(p);
            Material mat = mats[hit.mat_index];

            if (mat.reflectivity < 1.0) {
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

                vec3 color = (ambient + diffuse) * mat.color + specular;
                final_color += color * (1 - mat.reflectivity) * ray_energy; // se ultimo bounce considero opaco?
            }

            if (mat.reflectivity > 0) {
                ray = normalize(reflect(ray, norm));
                observer_position = p;
                p += ray * NUDGE;

                ray_energy *= mat.reflectivity;
                continue;
            } else {
                break;
            }
        }

        if (hit.reason == FAR) {
            final_color += COLOR_SKY_BOX * ray_energy;
            break;
        }

        if (hit.reason == OUT_OF_STEPS) {
            final_color += COLOR_OUT_OF_STEP * ray_energy;
            break;
        }
    }

    FragColor = vec4(final_color, 1);
}
