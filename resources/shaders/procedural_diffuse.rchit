#version 460

#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_ray_tracing : enable

#include "ray_common.glsl"
#include "hit_common.glsl"
#include "random.glsl"
#include "sampling.glsl"
#include "emitter_sampling.glsl"

layout(location = 0) rayPayloadInEXT RayPayload ray_info;

hitAttributeEXT vec3 hit_normal;

vec3 albedo = vec3(0.8, 0.3, 0.3);

vec2 eval_brdf(vec3 wi, vec3 normal) {
    float cos_theta = max(0.0, dot(wi, normal));
    float pdf = cos_theta / PI;
    return vec2(rgb_to_spectrum(albedo, ray_info.wavelength), pdf);
}

void sample_brdf(vec3 normal) {
    vec4 cos_sample = sample_cosine_hemisphere(rnd(ray_info.seed), rnd(ray_info.seed));
    ray_info.brdf_val = rgb_to_spectrum(albedo, ray_info.wavelength);
    ray_info.brdf_pdf = cos_sample.w;
    ray_info.brdf_d = frame_sample(cos_sample.xyz, normal);
}

void sample_emitter(vec3 pos, vec3 normal) {
    EmitterSample light = sample_light(pos, ray_info.seed, ray_info.wavelength);
    vec2 brdf_eval = eval_brdf(light.direction, normal);

    ray_info.emitter_o = light.position;
    ray_info.emitter_pdf = light.pdf;
    ray_info.emitter_brdf_val = brdf_eval[0];
    ray_info.emitter_brdf_pdf = brdf_eval[1];
    ray_info.emitter_normal = light.normal;
    ray_info.rad = light.radiance;
}

void main() {
    vec3 world_normal = normalize(mat3(gl_ObjectToWorldEXT) * hit_normal);
    vec3 hit_pos = gl_WorldRayOriginEXT + gl_HitTEXT * gl_WorldRayDirectionEXT;

    bool is_backface = dot(gl_WorldRayDirectionEXT, world_normal) > 0.0;
    if (is_backface) {
        world_normal = -world_normal;
    }

    sample_emitter(hit_pos, world_normal);
    sample_brdf(world_normal);

    ray_info.hit_pos = hit_pos;
    ray_info.hit_normal = world_normal;
    ray_info.hit_geo_normal = world_normal;
    ray_info.is_hit = true;
    ray_info.is_emitter = false;
    ray_info.is_specular = false;
}
