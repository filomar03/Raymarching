#version 330 core

out vec4 FragColor;

uniform vec2 uResolution;
// uniform float uTime;
uniform float uFov;
uniform vec3 uCamPos;
uniform vec4 uCamRot;
uniform float uCrankAngle;
uniform sampler2D uSampler;

// - RENDERING PARAMS
#define HIT_DISTANCE 0.0001
#define MAX_STEP 300
#define MAX_TRAVEL 30
#define EPSILON 0.001
#define MAX_BOUNCE 0
#define REFLECT_DISPLACMENT 0.01

// - DEBUG PARAMS
#define DEBUG_TEX
// #define DEBUG_SKIP_DEPTH_TEX
// #define DEBUG_BOUNCE 0
// #define DEBUG_DEPTH
// #define DEBUG_STEPS
// #define DEBUG_COLLISION
// #define DEBUG_NORMS
// #define DEBUG_REFLECTIONS

// - RENDERING EFFECTS
// #define CRT_EFFECT
// #define CEL_SHADING
// #define CEL_SHADING_Q 7

// - RENDERING STRUCTS
struct SceneInfo {
    float distance;
    int mat_index;
};

struct HitInfo {
    int reason;
    float travel;
    float steps;
    float distance;
    int mat_index;
};
// | - HitInfo reason set
#define HIT 0
#define FAR 1
#define OUT_OF_STEPS 2

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

// - COLORS
#define COLOR_OUT_OF_STEP vec3(255, 0, 123) / 255
#define COLOR_SKY_BOX vec3(16) / 255
#define COLOR_LIGHT vec3(1.0, 0.92, 0.75)

// - LIGHTS
#define DIR_LIGHT 99999999
#define AMBIENT_I 0.2
Light lights[] = Light[](
    Light(vec3(0.0, 0.0, 0.0), true, COLOR_LIGHT, 0.7),
    Light(normalize(vec3(1.0, 3.0, -1.0)) * DIR_LIGHT, false, COLOR_LIGHT, 0.25)
);

// - MATERIALS
Material mats[] = Material[](
    Material(vec3(0.28, 0.29, 0.31), 0, 0.01),
    Material(vec3(0.85, 0.86, 0.88), 2048, 0.25),
    Material(vec3(0.42, 0.39, 0.37), 16, 0.15),
    Material(vec3(0.50, 0.51, 0.53), 32, 0.03),
    Material(vec3(0.12, 0.12, 0.13), 16, 0.05),
    Material(vec3(0.45, 0.46, 0.45), 16, 0.15)
);
// | - MATERIALS SET
#define MAT_BLOCK        0
#define MAT_PISTON       1
#define MAT_CONROD       2
#define MAT_CRANKSHAFT   3
#define MAT_RINGS        4
#define MAT_GEARS        5

vec3 rotate(vec4 q, vec3 p) { // fast formula to rotate a point with a unit quaternion
    return p + 2 * q.w * cross(q.xyz, p) + 2 * cross(q.xyz, cross(q.xyz, p));
}

HitInfo rayMarch(vec3 p, vec3 ray) {
    int step = 0;
    float travel = 0;

    while (step < MAX_STEP) {
        SceneInfo scene = map(p);

        if (abs(scene.distance) <= HIT_DISTANCE) {
            return HitInfo(HIT, travel + distance, step, scene.distance, scene.mat_index);
        }

        p += ray * scene.distance;
        travel += scene.distance;


        if (travel > MAX_TRAVEL) {
            return HitInfo(FAR, travel, step, scene.distance, scene.mat_index);
        }

        step += 1;
    }

    return HitInfo(OUT_OF_STEPS, travel, step, 1.0 / 0, -1); // inf+ as distance
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

vec3 computeSpecular(vec3 p, vec3 norm, vec3 observer_pos, Light l, Material mat) { // Phong model
    vec3 l2p_dir = normalize(p - l.position);
    vec3 reflection = reflect(l2p_dir, norm);
    vec3 p2observer_dir = normalize(observer_pos - p);
    float spec_feature = pow(max(0, dot(reflection, p2observer_dir)), mat.shininess);
#ifdef CEL_SHADING
    return floor(spec_feature * l.color * l.intensity * CEL_SHADING_Q) / CEL_SHADING_Q;
#endif
#ifndef CEL_SHADING
    return spec_feature * l.color * l.intensity;
#endif
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

    vec2 uv = gl_FragCoord.xy / uResolution;
#ifdef DEBUG_SKIP_DEPTH_TEX
    float approx_dist = 0;
#else
    float approx_dist = texture(uSampler, uv).r;
#endif

    vec3 p = uCamPos;
    vec3 ray = normalize(rotate(uCamRot, vec3(ndc, 1))); // near fixes as 1, since it doesn't work
                                                         // like in traditional rendering
    vec3 observer_position = uCamPos;
    p += ray * approx_dist;

    float ray_energy = 1.0;
    vec3 final_color;

    for (int bounce = 0; bounce <= MAX_BOUNCE; bounce++) {
        HitInfo hit = rayMarch(p, ray);
        p += ray * hit.travel;

#ifdef DEBUG_TEX
        FragColor = vec4(vec3(approx_dist / MAX_TRAVEL), 1);
        return;
#endif
#ifdef DEBUG_BOUNCE
        if (bounce == DEBUG_BOUNCE) {
#endif
#ifdef DEBUG_DEPTH
            FragColor = vec4(vec3(1 - hit.travel / MAX_TRAVEL), 1);
            return;
#endif
#ifdef DEBUG_STEPS
            float step_ratio = hit.steps / MAX_STEP;
            float budget_exceed = step(MAX_STEP, hit.steps);
            vec3 step_color = step_ratio * (1 - COLOR_OUT_OF_STEP);
            vec3 final_color = mix(step_color, COLOR_OUT_OF_STEP, budget_exceed);
            FragColor = vec4(final_color, 1.0);
            return;
#endif
#ifdef DEBUG_COLLISION
            if (hit.reason != FAR) {
                vec3 col = mix(COLOR_OUT_OF_STEP, 1 - COLOR_OUT_OF_STEP, step(0, hit.distance));
                FragColor = vec4(col, 1);
                return;
            }
#endif
#ifdef DEBUG_NORMS
            if (hit.reason != FAR) {
                FragColor = vec4(abs(approx_norm(p)), 1);
                return;
            }
#endif
#ifdef DEBUG_REFLECTIONS
            if (hit.reason != FAR) {
                FragColor = vec4(abs(normalize(reflect(ray, approx_norm(p)))), 1);
                return;
            }
#endif
#ifdef DEBUG_BOUNCE
        }
#endif

        if (hit.reason == HIT) {
            vec3 norm = approx_norm(p);
            Material mat = mats[hit.mat_index];

            float absorbtion = 1.0 - mat.reflectivity;
            if (bounce == MAX_BOUNCE - 1) {
                absorbtion = 1.0;
            }

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
                        specular += computeSpecular(p, norm, observer_position, l, mat);
                    }
                }

                float local_light = clamp(ambient + diffuse, 0.0, 1.0);
#ifdef CEL_SHADING
                local_light = floor(local_light * CEL_SHADING_Q) / CEL_SHADING_Q;
#endif

                vec3 color = local_light * mat.color + specular;
                final_color += color * absorbtion * ray_energy;
            }

            if (mat.reflectivity > 0.0) {
                ray = normalize(reflect(ray, norm));
                observer_position = p;
                p += ray * REFLECT_DISPLACMENT;

                ray_energy *= mat.reflectivity;
            } else {
                break;
            }
        }
        else if (hit.reason == FAR) {
            final_color += COLOR_SKY_BOX * ray_energy;
            break;
        }
        else if (hit.reason == OUT_OF_STEPS) {
            final_color += COLOR_OUT_OF_STEP * ray_energy;
            break;
        }
    }

#ifdef CRT_EFFECT
    float m = mod(gl_FragCoord.x, 3.0);
    float r = step(m, 1.0);
    float g = step(m, 2.0) * step(1.0, m);
    float b = step(m, 3.0) * step(2.0, m);
    vec3 crtMask = vec3(r, g, b);
    FragColor = vec4(final_color * crtMask, 1);
#endif
#ifndef CRT_EFFECT
    FragColor = vec4(final_color, 1);
#endif
}
