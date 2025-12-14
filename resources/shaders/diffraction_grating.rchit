#version 460

#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_ray_tracing : enable

#include "ray_common.glsl"
#include "hit_common.glsl"
#include "random.glsl"
#include "sampling.glsl"

layout(location = 0) rayPayloadInEXT RayPayload ray_info;

hitAttributeEXT vec2 bary_coord;

struct BrdfParams {
    float period;
    float height;
    vec3 towards;
};

layout(scalar, set = 0, binding = BRDF_PARAMS_BINDING) readonly buffer Fields {
    BrdfParams params[];
} instance_info;

float bessel(int order, float x) {
    float ans = 0;
    float sgn = 1;
    float denom = 1;
    for (int i = 2; i <= order; i++) {
        denom *= i;
    }
    float numer = pow(x / 2, order);
    float x22 = x * x / 4;
    for (int m = 0; m < 5; m++) {
        ans += sgn * numer / denom;
        numer *= x22;
        denom *= (m + 1) * (m + 1 + order);
        sgn *= -1;
    }
    return ans;
}

void sample_brdf(vec3 hit_normal) {
    ray_info.brdf_val = 1;
    ray_info.brdf_pdf = 1;

    uint brdf_i = offsets.offsets[gl_InstanceID].brdf_i;
    BrdfParams brdf = instance_info.params[brdf_i];

    // get direction of diffraction grating
    vec3 towards = normalize(brdf.towards);
    vec3 towards_along_normal = dot(towards, hit_normal) * hit_normal;
    vec3 towards_perp_normal = towards - towards_along_normal;
    if (length(towards_perp_normal) == 0.0) {
        ray_info.brdf_val = 0;
        return;
    }
    vec3 across_grating = normalize(towards_perp_normal);
    vec3 along_grating = cross(hit_normal, across_grating);

    float wavelength = ray_info.wavelength;
    float x = 4 * PI * brdf.height / wavelength;

    float intensities[9];
    float total = 0;
    for (int i = 0; i < 9; i++) {
        float b = bessel(i+1, x);
        intensities[i] = b * b;
        total += intensities[i];
    }
    float r = rnd(ray_info.seed) * 2 - 1;
    float cdf = 0;
    int lobe = 0;
    for (int i = 0; i < 9; i++) {
        float p = intensities[i];
        cdf += 2 * p;
        if (abs(r) < cdf) {
            lobe = i + 1;
            break;
        }
    }
    if (r < 0) {
        lobe = -lobe;
    }

    vec3 wi_along = dot(gl_WorldRayDirectionEXT, along_grating) * along_grating;
    vec3 wi_across = gl_WorldRayDirectionEXT - wi_along;
    float magnitude_across = length(wi_across);
    vec3 reflected = reflect(normalize(wi_across), hit_normal);

    float cos_i = dot(-normalize(wi_across), hit_normal);
    float sin_i = sqrt(1 - cos_i * cos_i);
    float sin_o = sin_i - lobe * wavelength / brdf.period;
    float cos_o = sqrt(1 - sin_o * sin_o);
    if (isnan(sin_i) || isnan(cos_o)) {
        ray_info.brdf_val = 0;
        return;
    }
    vec3 refl_across = magnitude_across * ((reflected - hit_normal * cos_i) * sin_o / sin_i + hit_normal * cos_o);
    ray_info.brdf_d = refl_across + wi_along;
}

void sample_emitter(vec3 hit_pos, vec3 hit_normal) {
    ray_info.rad = vec3(0);
    ray_info.emitter_brdf_pdf = 1.0;
    ray_info.emitter_pdf = 1.0;
}

void main() {
    Vertex a = vertices.vertices[gl_InstanceCustomIndexEXT + 3*gl_PrimitiveID];
    Vertex b = vertices.vertices[gl_InstanceCustomIndexEXT + 3*gl_PrimitiveID + 1];
    Vertex c = vertices.vertices[gl_InstanceCustomIndexEXT + 3*gl_PrimitiveID + 2];

    vec3 full_bary_coord = vec3(1 - bary_coord.x - bary_coord.y, bary_coord);

    vec3 hit_pos =
        a.position * full_bary_coord.x
        + b.position * full_bary_coord.y
        + c.position * full_bary_coord.z;
    hit_pos = gl_ObjectToWorldEXT * vec4(hit_pos, 1);

    vec3 hit_normal =
        a.normal * full_bary_coord.x
        + b.normal * full_bary_coord.y
        + c.normal * full_bary_coord.z;
    hit_normal = normalize(gl_ObjectToWorldEXT * vec4(hit_normal, 0));

    vec3 edge1 = b.position - a.position;
    vec3 edge2 = c.position - a.position;
    vec3 face_normal = normalize(cross(edge1, edge2));
    face_normal = normalize(gl_ObjectToWorldEXT * vec4(face_normal, 0));

    bool is_backface = dot(gl_WorldRayDirectionEXT, face_normal) > 0.0;
    if (is_backface) {
        hit_normal = -hit_normal;
        face_normal = -face_normal;
    }

    sample_emitter(hit_pos, hit_normal);
    sample_brdf(hit_normal);

    ray_info.hit_pos = hit_pos;
    ray_info.hit_normal = hit_normal;
    ray_info.hit_geo_normal = hit_normal;
    ray_info.is_hit = true;
    ray_info.is_emitter = false;
    ray_info.is_specular = true;
}
