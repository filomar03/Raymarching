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
#define MAX_STEP 500
#define MAX_TRAVEL 3000.0
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
#define COLOR_OUT_OF_STEP COLOR_SKY_BOX
// #define COLOR_OUT_OF_STEP vec3(0, 1, 0)
#define COLOR_SKY_BOX vec3(213, 227, 229) / 255.0
#define COLOR_LIGHT vec3(238, 202, 198) / 255.0

#define DIR_LIGHT 99999999
#define AMBIENT_I 0.15
Light lights[] = Light[](
    Light(vec3(0.0, 0.0, 0.0), true, COLOR_LIGHT, 0.45),
    Light(normalize(vec3(1.0, 3.0, -1.0)) * DIR_LIGHT, false, COLOR_LIGHT, 0.07)
);

#define MAT_BLOCK        0
#define MAT_PISTON       1
#define MAT_CONROD       2
#define MAT_CRANKSHAFT   3
#define MAT_RINGS        4
#define MAT_GEARS        5

Material mats[] = Material[](
    Material(vec3(0.47, 0.47, 0.47), 0.0, 0.01), // BLOCK
    Material(vec3(0.75, 0.77, 0.80), 4096.0, 0.35), // PISTON
    Material(vec3(0.35, 0.33, 0.32), 16.0, 0.15), // CONROD
    Material(vec3(0.28, 0.28, 0.30), 128.0, 0.25), // CRANKSHAFT
    Material(vec3(0.12, 0.12, 0.13), 16.0, 0.05), // RINGS
    Material(vec3(0.35, 0.33, 0.32), 16.0, 0.15) // GEAR
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

SceneInfo map(vec3 p) {
    vec3 engine_pos = p - vec3(0.0, -3.0, 3.0);

    float cylinder_spacing = 0.2;
    float cylinder_bore = 2.0;

    float engine_squish = 0.2;

    float piston_height = 1.0;
    float piston_skirt_height = 0.45;
    float piston_skirt_tickness = 0.1;
    float piston_pin_bore = 0.2;
    float piston_ring_thickness = 0.025;
    float piston_ring_height = 0.05;
    float piston_ring_top_dist = 0.1;
    float piston_rings_dist = 0.15;

    float conrod_length = 1.5;
    float conrod_radius = 0.2;
    float conrod_head_radius = 0.275;
    float conrod_head_length = 0.75;

    float crank_radius = 0.5;
    float crank_journal_radius = 0.25;
    float crank_journal_length = 1.0;
    float crank_cweight_length = 0.3;

    float crank_angle = uCrankAngle;
    float phases[4] = float[](0.0, 1.57079, 4.71238, 3.14159);

    vec3 timing_gear_pos;
    float crank_gear_radius = 1.0;
    float crank_gear_teeth = 32;
    float crank_gear_thickness = 0.1;
    float crank_gear_tdepth = 0.03;

    float engine_lenght = phases.length() * (cylinder_bore + cylinder_spacing) + cylinder_spacing;
    float engine_height = (piston_height - piston_skirt_height) + conrod_length + crank_radius * 2 + crank_journal_radius + engine_squish + cylinder_spacing * 2;
    float block_h = engine_height * 0.5;
    float block_w = cylinder_bore * 0.5 + cylinder_spacing;
    float block_l = engine_lenght * 0.5;

    // DUPLICATE PARTS
    float d_pistons = MAX_TRAVEL;
    float d_rings = MAX_TRAVEL;
    float d_conrods = MAX_TRAVEL;
    float d_cranks = MAX_TRAVEL;
    float d_block_cyllinders = MAX_TRAVEL;
    for (int i = 0; i < phases.length(); i++) {
        float crank_pin_angle = crank_angle + phases[i];
        vec3 cylinder_offset = Z * (cylinder_bore + cylinder_spacing) * i;

        float journal_h = crank_journal_length * 0.5;
        float journal_r = crank_journal_radius * 0.5;

        vec3 crank_pos = engine_pos - cylinder_offset;
        vec3 crank_pin_offset = vec3(cos(crank_pin_angle), sin(crank_pin_angle), 0.0) * crank_radius;

        float conrod_y = sqrt(conrod_length * conrod_length - crank_pin_offset.x * crank_pin_offset.x);

        // PISTONS
        float outer_h = piston_height * 0.5;
        float outer_r = cylinder_bore * 0.5 - piston_ring_thickness;
        float inner_h = piston_skirt_height * 0.5;
        float inner_r = outer_r - piston_skirt_tickness;
        float pin_h = outer_r + A_NUDGE;
        float pin_r = piston_pin_bore * 0.5;

        vec3 piston_pin_pos = crank_pos - Y * (crank_pin_offset.y + conrod_y);
        vec3 piston_bot_pos = piston_pin_pos + Y * piston_skirt_height;
        vec3 outer_pos = piston_bot_pos - Y * outer_h;
        vec3 inner_pos = piston_bot_pos - Y * (inner_h - A_NUDGE);

        float d_piston_outer = sdCylinder(outer_pos, vec2(outer_r, outer_h));
        float d_piston_inner = sdCylinder(inner_pos, vec2(inner_r, inner_h));
        float d_piston_pin_bore = sdCylinder(piston_pin_pos.xzy, vec2(pin_r, pin_h));

        float d_piston = d_piston_outer;
        d_piston = opSubtract(d_piston, d_piston_inner);
        d_piston = opSubtract(d_piston, d_piston_pin_bore);
        d_pistons = opUnion(d_pistons, d_piston);

        // RINGS
        float ring_h = piston_ring_height * 0.5;
        float ring_r = cylinder_bore * 0.5;

        vec3 ring_pos = piston_bot_pos - Y * (piston_height - ring_h - piston_ring_top_dist);

        float d_piston_ring1 = sdCylinder(ring_pos, vec2(ring_r, ring_h));
        float d_piston_ring2 = sdCylinder(ring_pos + Y * piston_rings_dist, vec2(ring_r, ring_h));

        float d_ring = d_piston_ring1;
        d_ring = opUnion(d_ring, d_piston_ring2);
        d_rings = opUnion(d_rings, d_ring);

        // CONROD
        float conrod_head_h = conrod_head_length * 0.5;

        vec3 conrod_head_pos = crank_pos - crank_pin_offset;

        float d_conrod_caps = sdCapsule(p, p - piston_pin_pos, p - conrod_head_pos, conrod_radius);
        float d_conrod_wrist = sdCylinder(piston_pin_pos.xzy, vec2(pin_r, pin_h));
        float d_conrod_head = sdCylinder(conrod_head_pos.xzy, vec2(conrod_head_radius, conrod_head_h));

        float d_conrod = d_conrod_caps;
        d_conrods = opUnion(d_conrods, d_conrod);
        d_conrods = opUnion(d_conrods, d_conrod_wrist);
        d_conrods = opUnion(d_conrods, d_conrod_head);

        // CRANKSHAFT
        float cweight_h = crank_cweight_length * 0.5;
        float cweight_offset = journal_h + cweight_h;
        float jorunal_h = crank_journal_length * 0.5;

        vec3 cweight_fw_pos = crank_pos + Z * cweight_offset;
        vec3 cweight_bw_pos = crank_pos - Z * cweight_offset;
        vec3 journal_next_pos = crank_pos - Z * (cylinder_bore + cylinder_spacing) * 0.5;

        float journal_next_h = (cylinder_bore + cylinder_spacing - crank_journal_length) * 0.5 - crank_cweight_length;

        timing_gear_pos = journal_next_pos - Z * (journal_next_h + crank_gear_thickness * 0.5);

        float d_journal = sdCylinder(conrod_head_pos.xzy, vec2(crank_journal_radius, jorunal_h));
        float d_cweight_fw = sdCylinder(cweight_fw_pos.xzy, vec2(crank_radius + crank_journal_radius, cweight_h));
        float d_cweight_bw = sdCylinder(cweight_bw_pos.xzy, vec2(crank_radius + crank_journal_radius, cweight_h));
        float d_journal_next = sdCylinder(journal_next_pos.xzy, vec2(crank_journal_radius, journal_next_h));

        float d_crank = d_journal;
        d_crank = opUnion(d_crank, d_cweight_fw);
        d_crank = opUnion(d_crank, d_cweight_bw);
        d_crank = opUnion(d_crank, d_journal_next);
        d_cranks = opUnion(d_cranks, d_crank);

        // BLOCK
        float cyl_h = engine_height * 0.5 - cylinder_spacing;
        float cyl_r = cylinder_bore * 0.5;

        vec3 cylinder_pos = vec3(crank_pos.x, crank_pos.y + (crank_radius + crank_journal_radius - cyl_h), crank_pos.z);

        float d_cylinder = sdCylinder(cylinder_pos, vec2(cyl_r, cyl_h));
        d_block_cyllinders = opUnion(d_block_cyllinders, d_cylinder);
    }

    // TIMING GEAR
    float d_crank_gear = sdGear(timing_gear_pos, crank_gear_radius, crank_gear_thickness, crank_gear_teeth, crank_gear_tdepth, crank_angle);
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
