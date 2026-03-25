#version 330 core

// Rendering params
#define HIT_DISTANCE 0.01
#define MAX_STEP 300
#define MAX_TRAVEL 5000.0
#define EPSILON 0.0001

// Colors
#define HIT vec3(1.0, 0.95, 0.75)
#define FAR vec3(0.0, 0.0, 0.0)
#define OUT_OF_STEP vec3(0.3, 0, 0)

uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uMouse;
uniform float uFov;
out vec4 FragColor;

float sdSquare(vec3 p, float size) {
    vec2 d = abs(p.xy) - vec2(size);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float map(vec3 p) {
    // vec3 sp1_origin = vec3(0, 0, 10);
    // vec3 sp2_origin = vec3(10, 0, 20);

    // float sp1 = sdSphere(sp1_origin - p, 3.0 + abs(sin(uTime * 0.3) * 5.0));
    // float sp2 = sdSphere(sp2_origin - p, 8);

    // return min(sp1, sp2);

    return min(sdSphere(vec3(0, 1, 1) - p, 1), min(sdSquare(p, 1), sdSphere(vec3(3, 0, 1) - p, 1)));
}

vec3 approx_norm(vec3 p) {
    // central difference gradient
    vec2 h = vec2(EPSILON, 0.0);

    float dx = map(p + h.xyy) - map(p - h.xyy);
    float dy = map(p + h.yxy) - map(p - h.yxy);
    float dz = map(p + h.yyx) - map(p - h.yyx);

    vec3 norm = normalize(vec3(dx, dy, dz));
    return norm;
}

void main()
{
    vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1; // near plane coords
    float aspect_ratio = uResolution.x / uResolution.y;
    // expand uv to match window ratio
    uv.x *= max(1, aspect_ratio);
    uv.y *= max(1, 1 / aspect_ratio);
    float thf = tan(radians(uFov * 0.5)); // nearplane half height / distance from cam ratio

    vec3 origin = vec3(uv.xy, 0);
    float near_plane_half_height = max(1, 1 / aspect_ratio);
    vec3 camera = vec3(0, 0, -(near_plane_half_height / thf)); // TODO: spostare conti su cpu e eseguire correggere uv in base a near
    vec3 ray = normalize(origin - camera);

    vec3 p = origin;
    float travel = 0.0;
    int step = 0;

    while (true) {
        float d = map(p);

        travel += d;

        p += ray * d;

        if (d <= HIT_DISTANCE) {
            // DEBUG!!!
            FragColor = vec4(approx_norm(p).xy, -abs(approx_norm(p)).z, 1);
            return;

            vec3 norm = approx_norm(p);
            vec3 color = HIT;

            // -- Directional light
            // vec3 light_dir = normalize(vec3(-1, -2, 2));
            // float intensity = 0.9;

            // -- Point light
            vec3 light_pos = vec3(0, 0, 0);
            vec3 light_dir = normalize(p - light_pos);

            // Ambient lighting
            float ambient_i = 0.05;
            vec3 ambient = color * ambient_i;

            // Diffuse lighting (Lambert)
            float diffuse_i = 0.75;
            vec3 diffuse = max(0, dot(norm, -light_dir)) * color * diffuse_i;

            // Specular lighting (Phong)
            vec3 reflected = reflect(light_dir, norm);
            vec3 specular_color = vec3(1, 1, 1);
            float shininness = 512;
            vec3 specular = pow(max(0, dot(reflected, norm)), shininness) * specular_color;

            FragColor = vec4(ambient + diffuse + specular, 1);
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
