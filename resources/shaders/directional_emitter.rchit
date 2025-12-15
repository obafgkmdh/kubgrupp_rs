#version 460

#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_ray_tracing : enable

#include "ray_common.glsl"
#include "hit_common.glsl"
#include "color_spaces.glsl"

layout(location = 0) rayPayloadInEXT RayPayload ray_info;

hitAttributeEXT vec3 hit_normal;

void main() {
    uint light_index = gl_InstanceCustomIndexEXT;
    Light light = lights.lights[light_index];

    vec3 world_normal = normalize(mat3(gl_ObjectToWorldEXT) * hit_normal);
    vec3 hit_pos = gl_WorldRayOriginEXT + gl_HitTEXT * gl_WorldRayDirectionEXT;

    bool is_front_face = dot(gl_WorldRayDirectionEXT, world_normal) < 0.0;

    vec3 scale = vec3(
        length(gl_ObjectToWorldEXT[0].xyz),
        length(gl_ObjectToWorldEXT[1].xyz),
        length(gl_ObjectToWorldEXT[2].xyz)
    );
    float radius = (scale.x + scale.y) * 0.5;
    float area = PI * radius * radius;

    vec3 to_center = light.position - gl_WorldRayOriginEXT;
    vec3 along_beam = dot(to_center, world_normal) * world_normal;
    float dist = length(to_center - along_beam);

    ray_info.is_hit = true;
    ray_info.hit_pos = hit_pos;
    ray_info.emitter_pdf = 1.0 / float(lights.num_lights) / area;

    if (is_front_face && dist < radius) {
        ray_info.is_emitter = true;
        ray_info.rad = vec3(rgb_to_spectrum(light.color, ray_info.wavelength));
        ray_info.hit_normal = world_normal;
        ray_info.emitter_type = 1.0;
    } else {
        ray_info.is_emitter = true;
        ray_info.rad = vec3(0);
        ray_info.hit_normal = -world_normal;
        ray_info.emitter_type = -1.0;
    }
}
