#version 460

#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_ray_tracing : enable

#include "raycommon.glsl"

layout(location = 0) rayPayloadInEXT RayPayload ray_info;

layout(set = 1, binding = 0) uniform Fields {
    vec3 color;
} instance_info[];

void main() {
    ray_info.rad = instance_info[nonuniformEXT(gl_InstanceID)].color;
}
