#version 330 core

// Uniforms
uniform vec2 uResolution;
uniform float uTime;
uniform float uFov;
uniform vec3 uCamPos;
uniform vec4 uCamRot;
uniform float uCrankAngle;

// Shader output
out vec4 FragColor;

// Rendering params
#define HIT_DISTANCE 0.001
#define MAX_STEP 300
#define MAX_TRAVEL 100
#define EPSILON 0.001
#define MAX_BOUNCE 2
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
#define COLOR_OUT_OF_STEP COLOR_SKY_BOX
// #define COLOR_OUT_OF_STEP vec3(0, 1, 0)
#define COLOR_SKY_BOX vec3(213, 227, 229) / 255.0
#define COLOR_LIGHT vec3(1.0, 0.92, 0.75)

#define DIR_LIGHT 99999999
#define AMBIENT_I 0.15
Light lights[] = Light[](
    Light(vec3(0.0, 0.0, 0.0), true, COLOR_LIGHT, 0.5),
    Light(normalize(vec3(1.0, 3.0, -1.0)) * DIR_LIGHT, false, COLOR_LIGHT, 0.15)
);

#define MAT_BLOCK        0
#define MAT_PISTON       1
#define MAT_CONROD       2
#define MAT_CRANKSHAFT   3
#define MAT_RINGS        4
#define MAT_GEARS        5

Material mats[] = Material[](
    Material(vec3(0.28, 0.29, 0.31), 0, 0.01),
    Material(vec3(0.85, 0.86, 0.88), 2048, 0.25),
    Material(vec3(0.42, 0.39, 0.37), 16, 0.15),
    Material(vec3(0.50, 0.51, 0.53), 32, 0.03),
    Material(vec3(0.12, 0.12, 0.13), 16, 0.05),
    Material(vec3(0.45, 0.46, 0.45), 16, 0.15)
);

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

// SDFs (formule prese da: https://iquilezles.org/articles/distfunctions/)
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
float sdGear(vec3 p, float r, float w, float teeth, float td, float angle) {
    float c = cos(angle), s = sin(angle); // ===|
    mat2 rot = mat2(c, -s, s, c);         //    | rotate coordinate space
    vec2 p2 = rot * p.xy;                 // ===|

    float a = atan(p2.y, p2.x); // ===| find angle

    float r_mod = r + td * sin(a * teeth); // ===| creates tooth

    vec2 d = vec2(length(p2) - r_mod, abs(p.z) - w);          // ===| extrude and compute distance
    float ed = min(max(d.x, d.y), 0.0) + length(max(d, 0.0)); // ===|
    return ed * 0.8; // ==| reduces distance since it can overshoot, r_mod is radial distance not euclidean distance
}

#define X vec3(1.0, 0.0, 0.0)
#define Y vec3(0.0, 1.0, 0.0)
#define Z vec3(0.0, 0.0, 1.0)
#define A_NUDGE 0.01
#define LIMITER 10

// Constant engine parameters
const vec3 abs_eng_position = vec3(0.0, -3.0, 3.0);
const float phases[4] = float[](0.0, 1.57079, 4.71238, 3.14159);

const float cylinder_spacing = 0.2;
const float cylinder_bore = 2.0;
const float cylinder_r = cylinder_bore * 0.5;

const float piston_height = 1.0;
const float piston_skirt_height = 0.45;
const float piston_skirt_tickness = 0.1;
const float piston_pin_bore = 0.2;
const float piston_ring_thickness = 0.025;
const float piston_ring_height = 0.05;
const float piston_ring_top_dist = 0.1;
const float piston_rings_dist = 0.15;
const float piston_squish = 0.2;
const float piston_outer_h = piston_height * 0.5;
const float piston_outer_r = cylinder_bore * 0.5 - piston_ring_thickness;
const float piston_inner_h = piston_skirt_height * 0.5;
const float piston_inner_r = piston_outer_r - piston_skirt_tickness;
const float piston_ring_h= piston_ring_height * 0.5;
const float piston_ring_r = cylinder_bore * 0.5;

const float conrod_length = 1.5;
const float conrod_radius = 0.2;
const float conrod_head_radius = 0.275;
const float conrod_head_length = 0.75;
const float conrod_head_h = conrod_head_length * 0.5;

const float crank_radius = 0.5;
const float crank_journal_radius = 0.25;
const float crank_journal_length = 0.8;
const float crank_cweight_length = 0.25;
const float crank_cw_rad_mul = 1.5;
const float crank_cw_smooth = 0.6;
const float crank_journal_h = crank_journal_length * 0.5;
const float crank_pin_h = piston_outer_r + A_NUDGE;
const float crank_pin_r = piston_pin_bore * 0.5;
const float crank_cweight_h = crank_cweight_length * 0.5;
const float crank_cweight_offset = crank_journal_h + crank_cweight_h;
const float crank_jorunal_h = crank_journal_length * 0.5;

const float timing_gear_radius = 1.0;
const float timing_gear_teeth = 32;
const float timing_gear_thickness = 0.1;
const float timing_gear_tdepth = 0.03;
vec3 timing_gear_pos;

const float engine_lenght = phases.length() * (cylinder_bore + cylinder_spacing) + cylinder_spacing;
const float engine_height = (piston_height - piston_skirt_height) + conrod_length + crank_radius * 2 + crank_journal_radius + piston_squish + cylinder_spacing * 2;
const float block_h = engine_height * 0.5;
const float block_w = cylinder_bore * 0.5 + cylinder_spacing;
const float block_l = engine_lenght * 0.5;

const float cylinder_h = engine_height * 0.5 - cylinder_spacing;

// Computed values needed once per frame
float crank_pin_angle[phases.length()];
vec3 cylinder_offset[phases.length()];
vec3 crank_pin_offset[phases.length()];
float conrod_y[phases.length()];

void computeFrameValues() {
    for (int i = 0; i < phases.length(); i++) {
        crank_pin_angle[i] = uCrankAngle + phases[i];
        cylinder_offset[i] = Z * (cylinder_bore + cylinder_spacing) * i;
        crank_pin_offset[i] = vec3(cos(crank_pin_angle[i]), sin(crank_pin_angle[i]), 0.0) * crank_radius;
        conrod_y[i] = sqrt(conrod_length * conrod_length - crank_pin_offset[i].x * crank_pin_offset[i].x);
    }
}

SceneInfo map(vec3 p) {
    vec3 engine_pos = p - abs_eng_position;

    // DUPLICATE PARTS
    float d_pistons = MAX_TRAVEL;
    float d_rings = MAX_TRAVEL;
    float d_conrods = MAX_TRAVEL;
    float d_cranks = MAX_TRAVEL;
    float d_block_cyllinders = MAX_TRAVEL;
    for (int i = 0; i < phases.length(); i++) {
        vec3 crank_pos = engine_pos - cylinder_offset[i];

        // PISTON
        vec3 piston_pin_pos = crank_pos - Y * (crank_pin_offset[i].y + conrod_y[i]);
        vec3 piston_bot_pos = piston_pin_pos + Y * piston_skirt_height;
        vec3 outer_pos = piston_bot_pos - Y * piston_outer_h;
        vec3 inner_pos = piston_bot_pos - Y * (piston_inner_h - A_NUDGE);

        float d_piston_outer = sdCylinder(outer_pos, vec2(piston_outer_r, piston_outer_h));
        float d_piston_inner = sdCylinder(inner_pos, vec2(piston_inner_r, piston_inner_h));
        float d_piston_pin_bore = sdCylinder(piston_pin_pos.xzy, vec2(crank_pin_r, crank_pin_h));

        float d_piston = d_piston_outer;
        d_piston = opSubtract(d_piston, d_piston_inner);
        d_piston = opSubtract(d_piston, d_piston_pin_bore);
        d_pistons = opUnion(d_pistons, d_piston);

        // RINGS
        vec3 ring_pos = piston_bot_pos - Y * (piston_height - piston_ring_h - piston_ring_top_dist);

        float d_piston_ring1 = sdCylinder(ring_pos, vec2(piston_ring_r, piston_ring_h));
        float d_piston_ring2 = sdCylinder(ring_pos + Y * piston_rings_dist, vec2(piston_ring_r, piston_ring_h));

        float d_ring = d_piston_ring1;
        d_ring = opUnion(d_ring, d_piston_ring2);
        d_rings = opUnion(d_rings, d_ring);

        // CONROD
        vec3 conrod_head_pos = crank_pos - crank_pin_offset[i];

        float d_conrod_caps = sdCapsule(p, p - piston_pin_pos, p - conrod_head_pos, conrod_radius);
        float d_conrod_wrist = sdCylinder(piston_pin_pos.xzy, vec2(crank_pin_r, crank_pin_h));
        float d_conrod_head = sdCylinder(conrod_head_pos.xzy, vec2(conrod_head_radius, conrod_head_h));

        float d_conrod = d_conrod_caps;
        d_conrods = opUnion(d_conrods, d_conrod);
        d_conrods = opUnion(d_conrods, d_conrod_wrist);
        d_conrods = opUnion(d_conrods, d_conrod_head);

        // CRANKSHAFT
        vec3 cw_pin_pos = conrod_head_pos;
        vec3 cw_journal_pos = crank_pos;
        vec3 cw_opp_pos = crank_pos + crank_pin_offset[i] * 2;
        vec3 journal_next_pos = crank_pos - Z * (cylinder_bore + cylinder_spacing) * 0.5;

        float journal_next_h = (cylinder_bore + cylinder_spacing - crank_journal_length) * 0.5 - crank_cweight_length;

        timing_gear_pos = journal_next_pos - Z * (journal_next_h + timing_gear_thickness * 0.5);

        float d_journal = sdCylinder(conrod_head_pos.xzy, vec2(crank_journal_radius, crank_jorunal_h));

        float d_cw0_handle = sdCylinder((cw_pin_pos + Z * crank_cweight_offset).xzy, vec2(crank_journal_radius, crank_cweight_h));
        float d_cw0_jint = sdCylinder((cw_journal_pos + Z * crank_cweight_offset).xzy, vec2(crank_radius + crank_journal_radius, crank_cweight_h));
        float d_cw0_oppint = sdCylinder((cw_opp_pos + Z * crank_cweight_offset).xzy, vec2((crank_radius + crank_journal_radius) * crank_cw_rad_mul, crank_cweight_h));
        float d_cw0_opp = opIntersect(d_cw0_jint, d_cw0_oppint);
        float d_cw0 = opSmoothUnion(d_cw0_opp, d_cw0_handle, crank_cw_smooth);
        d_cw0 = opIntersect(d_cw0, d_cw0_jint);

        float d_cw1_handle = sdCylinder((cw_pin_pos - Z * crank_cweight_offset).xzy, vec2(crank_journal_radius, crank_cweight_h));
        float d_cw1_jint = sdCylinder((cw_journal_pos - Z * crank_cweight_offset).xzy, vec2(crank_radius + crank_journal_radius, crank_cweight_h));
        float d_cw1_oppint = sdCylinder((cw_opp_pos - Z * crank_cweight_offset).xzy, vec2((crank_radius + crank_journal_radius) * crank_cw_rad_mul, crank_cweight_h));
        float d_cw1_opp = opIntersect(d_cw1_jint, d_cw1_oppint);
        float d_cw1 = opSmoothUnion(d_cw1_opp, d_cw1_handle, crank_cw_smooth);
        d_cw1 = opIntersect(d_cw1, d_cw1_jint);

        float d_journal_next = sdCylinder(journal_next_pos.xzy, vec2(crank_journal_radius, journal_next_h));

        float d_crank = d_journal;
        d_crank = opUnion(d_crank, d_cw0);
        d_crank = opUnion(d_crank, d_cw1);
        d_crank = opUnion(d_crank, d_journal_next);
        d_cranks = opUnion(d_cranks, d_crank);

        // BLOCK
        vec3 cylinder_pos = vec3(crank_pos.x, crank_pos.y + (crank_radius + crank_journal_radius - cylinder_h), crank_pos.z);

        float d_cylinder = sdCylinder(cylinder_pos, vec2(cylinder_r, cylinder_h));
        d_block_cyllinders = opUnion(d_block_cyllinders, d_cylinder);
    }

    // TIMING GEAR
    float d_crank_gear = sdGear(timing_gear_pos, timing_gear_radius, timing_gear_thickness, timing_gear_teeth, timing_gear_tdepth, uCrankAngle);
    float d_timing_gear = d_crank_gear;

    // BLOCK
    vec3 engine_center = engine_pos + Z * (cylinder_spacing + cylinder_bore * 0.5 - block_l);
    engine_center += Y * (crank_radius + crank_journal_radius + cylinder_spacing - block_h);
    vec3 crank_mjournal_pos = vec3(engine_center.x, engine_center.z, engine_pos.y);

    float d_block = sdBox(engine_center + X * block_w * 0.5, vec3(block_w * 0.5, block_h, block_l));
    float d_crank_cyl = sdCylinder(crank_mjournal_pos, vec2(crank_journal_radius * 1.5, engine_lenght * 0.5 - cylinder_spacing));
    d_block = opSubtract(d_block, d_block_cyllinders);
    d_block = opSubtract(d_block, d_crank_cyl);

    // SECTION
    vec3 section_pos = engine_pos - vec3(MAX_TRAVEL, 0, 0);
    float d_section = sdBox(section_pos, vec3(MAX_TRAVEL));

    SceneInfo scene = SceneInfo(d_pistons, MAT_PISTON);

    if (d_block < scene.distance) scene.mat_index = MAT_BLOCK;
    scene.distance = opUnion(scene.distance, d_block);

    if (d_conrods < scene.distance) scene.mat_index = MAT_CONROD;
    scene.distance = opUnion(scene.distance, d_conrods);

    if (d_rings < scene.distance) scene.mat_index = MAT_RINGS;
    scene.distance = opUnion(scene.distance, d_rings);

    if (d_cranks < scene.distance) scene.mat_index = MAT_CRANKSHAFT;
    scene.distance = opUnion(scene.distance, d_cranks);

    if (d_timing_gear < scene.distance) scene.mat_index = MAT_GEARS;
    scene.distance = opUnion(scene.distance, d_timing_gear);

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

vec3 computeSpecular(vec3 p, vec3 norm, vec3 observer_pos, Light l, Material mat) { // Phong model
    vec3 l2p_dir = normalize(p - l.position);
    vec3 reflection = reflect(l2p_dir, norm);
    vec3 p2observer_dir = normalize(observer_pos - p);
    return pow(max(0, dot(reflection, p2observer_dir)), mat.shininess) * l.color * l.intensity;
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

    vec3 p = uCamPos;
    vec3 ray = normalize(rotate(uCamRot, vec3(uv, 1))); // near is set to 1, since changing it doesn't affect the rendering (for now)
    vec3 observer_position = uCamPos;

    float ray_energy = 1.0;
    vec3 final_color;

    computeFrameValues();
    for (int bounce = 0; bounce < MAX_BOUNCE; bounce++) {
        HitInfo hit = rayMarch(p, ray, 0, 0);
        p += ray * hit.travel;

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

                vec3 color = (ambient + diffuse) * mat.color + specular;
                final_color += color * absorbtion * ray_energy;
            }

            if (mat.reflectivity > 0.0) {
                ray = normalize(reflect(ray, norm));
                observer_position = p;
                p += ray * NUDGE;

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

    FragColor = vec4(final_color, 1);
}
