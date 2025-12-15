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

float period = 740;
float height = 110;
vec3 albedo_back = vec3(0.4, 0.1, 0.1);

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

void sample_brdf_front(vec3 normal) {
    ray_info.brdf_val = 1;
    ray_info.brdf_pdf = 1;

    // get direction of diffraction grating
    vec3 hit_pos = gl_WorldRayOriginEXT + gl_HitTEXT * gl_WorldRayDirectionEXT;
    vec3 towards = normalize(gl_ObjectToWorldEXT * vec4(0, 0, 0, 1) - hit_pos);
    vec3 towards_along_normal = dot(towards, normal) * normal;
    vec3 towards_perp_normal = towards - towards_along_normal;
    if (length(towards_perp_normal) == 0.0) {
        ray_info.brdf_val = 0;
        return;
    }
    vec3 across_grating = normalize(towards_perp_normal);
    vec3 along_grating = cross(normal, across_grating);

    float wavelength = ray_info.wavelength;
    float x = 4 * PI * height / wavelength;

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
    if (magnitude_across > 0) {
        float cos_i = dot(-normalize(wi_across), normal);
        float sin_i = sqrt(1 - cos_i * cos_i);
        float sin_o = sin_i - lobe * wavelength / period;
        float cos_o = sqrt(1 - sin_o * sin_o);
        if (isnan(cos_o)) {
            ray_info.brdf_val = 0;
            return;
        }
        ray_info.brdf_d = across_grating * sin_o + normal * cos_o + wi_along;
    } else {
        ray_info.brdf_d = reflect(gl_WorldRayDirectionEXT, normal);
    }
}

void sample_brdf_diffuse(vec3 normal, vec3 albedo) {
    vec4 cos_sample = sample_cosine_hemisphere(rnd(ray_info.seed), rnd(ray_info.seed));
    ray_info.brdf_val = rgb_to_spectrum(albedo, ray_info.wavelength);
    ray_info.brdf_pdf = cos_sample.w;
    ray_info.brdf_d = frame_sample(cos_sample.xyz, normal);
}

void sample_brdf_dielectric(vec3 hit_normal) {
    ray_info.brdf_val = 1;
    ray_info.brdf_pdf = 1;

    const float b[3] = float[3](1.4182, 0.0, 0.0);
    const float c[3] = float[3](0.021304, 0.0, 0.0);

    float wavelength = ray_info.wavelength;
    float lambda_squared = pow(wavelength / 1000, 2);
    float eta_squared = 1;
    for (int i = 0; i < 3; i++) {
        eta_squared += b[i] * lambda_squared / (lambda_squared - c[i]);
    }
    float eta = 1 / sqrt(eta_squared);

    if (dot(hit_normal, -gl_WorldRayDirectionEXT) < 0.0) {
        hit_normal = -hit_normal;
        eta = 1 / eta;
    }

    vec3 reflected = reflect(gl_WorldRayDirectionEXT, hit_normal);
    float f = fresnel(abs(dot(reflected, hit_normal)), eta);

    float r = rnd(ray_info.seed);
    if (r < f) {
        ray_info.brdf_d = normalize(reflected);
    } else {
        ray_info.brdf_d = normalize(refract(gl_WorldRayDirectionEXT, hit_normal, eta));
    }
}

vec2 eval_brdf_diffuse(vec3 wi, vec3 normal, vec3 albedo) {
    float cos_theta = max(0.0, dot(wi, normal));
    float pdf = cos_theta / PI;
    return vec2(rgb_to_spectrum(albedo, ray_info.wavelength), pdf);
}

void sample_emitter(vec3 pos, vec3 normal) {
    ray_info.rad = vec3(0);
    ray_info.emitter_brdf_pdf = 1.0;
    ray_info.emitter_pdf = 1.0;
}

void sample_emitter_diffuse(vec3 pos, vec3 normal, vec3 albedo) {
    EmitterSample light = sample_light(pos, ray_info.seed, ray_info.wavelength);
    vec2 brdf_eval = eval_brdf_diffuse(light.direction, normal, albedo);

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

    vec3 hit_pos_obj = gl_ObjectRayOriginEXT + gl_HitTEXT * gl_ObjectRayDirectionEXT;
    float dist_from_center = length(hit_pos_obj.xy);

    bool is_backface = dot(gl_WorldRayDirectionEXT, world_normal) > 0.0;
    if (is_backface) {
        world_normal = -world_normal;
    }
    if (dist_from_center >= 0.35 && dist_from_center < 0.4 && !is_backface) {
        sample_brdf_diffuse(world_normal, vec3(0));
        sample_emitter_diffuse(hit_pos, world_normal, vec3(0));
        ray_info.is_specular = false;
    } else if (dist_from_center >= 0.33 && dist_from_center < 0.35) {
        sample_brdf_diffuse(world_normal, vec3(0.8));
        sample_emitter_diffuse(hit_pos, world_normal, vec3(0.8));
        ray_info.is_specular = false;
    } else if (dist_from_center >= 0.22 && dist_from_center < 0.33) {
        sample_brdf_diffuse(world_normal, vec3(0.6));
        sample_emitter_diffuse(hit_pos, world_normal, vec3(0.6));
        ray_info.is_specular = false;
    } else if (dist_from_center < 0.35) {
        sample_brdf_dielectric(world_normal);
        sample_emitter(hit_pos, world_normal);
        ray_info.is_specular = true;
    } else {
        if (is_backface) {
            sample_brdf_diffuse(world_normal, albedo_back);
            sample_emitter_diffuse(hit_pos, world_normal, albedo_back);
            ray_info.is_specular = false;
        } else {
            sample_brdf_front(world_normal);
            sample_emitter(hit_pos, world_normal);
            ray_info.is_specular = true;
        }
    }


    ray_info.hit_pos = hit_pos;
    ray_info.hit_normal = world_normal;
    ray_info.hit_geo_normal = world_normal;
    ray_info.is_hit = true;
    ray_info.is_emitter = false;
}
