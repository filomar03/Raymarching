#version 330 core

// Rendering params
#define HIT_DISTANCE 0.01
#define MAX_STEP 300
#define MAX_TRAVEL 5000.0
#define EPSILON 0.0001

// Colors
#define HIT vec3(1.0, 0.95, 0.85)
#define FAR vec3(0.0, 0.0, 0.0)
#define OUT_OF_STEP vec3(0.3, 0, 0)

uniform vec2 uResolution;
uniform float uTime;
uniform float uFov;
uniform float uNear;
uniform vec3 uCamPos;
out vec4 FragColor;

struct Light {
    vec3 position;
    bool follow_cam;
    float intensity;
};

struct Material {
    vec3 color;
    float shininess;
};

float sdSquare(vec3 p, float size) {
    vec2 d = abs(p.xy) - vec2(size);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSphere(vec3 center, float radius) {
    return length(center) - radius;
}

float map(vec3 p) {
    vec3 sp1_origin = vec3(0, 0, 10);
    vec3 sp2_origin = vec3(10, 0, 20);

    float sp1 = sdSphere(sp1_origin - p, 3.0 + abs(sin(uTime * 1.2) * 2.0));
    float sp2 = sdSphere(sp2_origin - p, 8);

    return min(sp1, sp2);
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

#define DIR_LIGHT 999999
#define AMBIENT_I 0.15
#define LIGHTS_NUM 1
Light lights[LIGHTS_NUM] = Light[](
    Light(vec3(0.0, 3.0, 0.0), true, 0.7)
);

float computeDiffuse() { // computes diffuse lighting (Lambert model)
    return 1.0; // TODO: move here calculations
}

float computeSpecular() { // computes specular lighting (Phong model)
    return 1.0; // TODO: move here calculations
}

void main()
{
    float aspect_ratio = uResolution.x / uResolution.y;
    float thf = tan(radians(uFov * 0.5)); // projection plane half height / near distance ratio
    vec2 uv = gl_FragCoord.xy / uResolution * 2.0 - 1; // normalize
    uv *= vec2(thf * uNear); // scale (according to FOV & near)
    uv.x *= aspect_ratio; // scale x (to respect ratio)

    vec3 origin = vec3(uv, uNear);
    vec3 ray = normalize(origin);

    vec3 p = origin + uCamPos;
    float travel = 0.0;
    int step = 0;

    while (true) {
        float d = map(p);

        travel += d;

        p += ray * d;

        if (d <= HIT_DISTANCE) {
            vec3 norm = approx_norm(p);
            Material mat = Material(HIT, 512);

            // ambient lighting
            float ambient = AMBIENT_I;
            float diffuse = 0.0;
            float specular = 0.0;

            for (int i = 0; i < LIGHTS_NUM; i++) {
                Light l = lights[i];

                if (l.follow_cam) {
                    l.position += uCamPos;
                }

                vec3 p2l_dir = normalize(l.position - p);
                diffuse += max(0, dot(norm, p2l_dir)) * l.intensity;
                vec3 l2p_dir = -p2l_dir;
                vec3 reflection = reflect(l2p_dir, norm); // TODO: maybe i should normalize, maybe even just to correct fp errors
                vec3 p2cam_dir = normalize(uCamPos - p);
                specular += pow(max(0, dot(reflection, p2cam_dir)), mat.shininess);
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
