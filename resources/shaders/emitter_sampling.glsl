#include "color_spaces.glsl"

struct EmitterSample {
    vec3 position;
    vec3 direction;
    vec3 normal;
    vec3 radiance;
    float pdf;
};

EmitterSample sample_light(vec3 hit_pos, inout uint seed, inout float wavelength) {
    EmitterSample result;
    // default values
    result.position = vec3(1, 0, 0);
    result.direction = vec3(1, 0, 0);
    result.normal = vec3(1, 0, 0);
    result.radiance = vec3(0);
    result.pdf = 1;

    // pick a random emitter
    uint light_i = uint(rnd(seed) * lights.num_lights);
    Light light = lights.lights[light_i];

    if (light.type == EMITTER_TYPE_POINT) {
        result.position = light.position;
        result.direction = normalize(light.position - hit_pos);
        result.normal = -result.direction;
        result.radiance = vec3(rgb_to_spectrum(light.color, wavelength));
        result.pdf = 1.0 / lights.num_lights;
    } else if (light.type == EMITTER_TYPE_AREA) {
        // sample random point on triangle
        float s = rnd(seed);
        float t = sqrt(rnd(seed));
        float a = 1 - t;
        float b = (1 - s) * t;
        float c = s * t;

        vec3 ab = light.data[1] - light.data[0];
        vec3 ac = light.data[2] - light.data[0];
        vec3 normal = cross(ab, ac);
        float area = length(normal) / 2;
        normal = normalize(normal);

        result.position = a * light.data[0] + b * light.data[1] + c * light.data[2];

        result.direction = normalize(result.position - hit_pos);
        float cos_angle_to_light = dot(-result.direction, normal);
        bool visible = false;
        if (light.emit_type == 0.0 && cos_angle_to_light >= 0.996) {
            visible = true;
        } else if (light.emit_type == 1.0 && cos_angle_to_light >= 0.0) {
            visible = true;
        }
        if (visible) {
            result.pdf = 1.0 / lights.num_lights / area;
            result.normal = normal;
            result.radiance = vec3(rgb_to_spectrum(light.color, wavelength));
        }
    } else if (light.type == EMITTER_TYPE_DIRECTIONAL) {
        vec3 light_dir = normalize(light.data[0]);
        vec3 dir_to_light = -light_dir;
        float radius = light.data[1].r;

        vec3 to_hit = hit_pos - light.position;
        float along_axis = dot(to_hit, light_dir);
        vec3 perpendicular = to_hit - along_axis * light_dir;
        float perp_dist = length(perpendicular);
        bool in_beam = along_axis > 0.0 && perp_dist <= radius;

        vec3 emitter_pos = light.position + perpendicular;
        float dist_sq = max(along_axis * along_axis, 1.0);

        result.position = emitter_pos;
        result.direction = dir_to_light;
        result.normal = light_dir;
        result.radiance = in_beam ? vec3(rgb_to_spectrum(light.color, wavelength)) * dist_sq : vec3(0);
        result.pdf = 1.0 / lights.num_lights;
    }

    return result;
}
