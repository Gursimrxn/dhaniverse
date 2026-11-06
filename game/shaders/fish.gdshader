shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_lambert, specular_disabled, shadows_disabled;
#include "res://shaders/common.gdshaderinc"

// Whole school animated on the GPU. Mesh: fish along +X (nose at +x), ~1 unit long.
// INSTANCE_CUSTOM = (path radius 0..1, angular speed (signed), phase, depth below the node).
uniform float radius = 3.0;
uniform float fish_len = 0.5;
uniform vec3 back_col : source_color = vec3(0.06, 0.1, 0.13);
uniform vec3 belly_col : source_color = vec3(0.2, 0.27, 0.3);
uniform vec3 water_tint : source_color = vec3(0.05, 0.42, 0.45);
uniform float opacity = 0.7;

varying vec3 wpos;
varying float belly;

vec3 path(float t, vec4 c) {
	float a = c.z + t * c.y;
	float r = radius * c.x * (0.55 + 0.45 * sin(a * 0.63 + c.z * 2.0));
	vec2 wob = vec2(sin(t * 0.37 + c.z * 5.0), cos(t * 0.29 + c.z * 3.0)) * 0.25 * radius * c.x;
	return vec3(cos(a) * r + wob.x, -c.w, sin(a) * r * 0.85 + wob.y);
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	vec3 p = path(TIME, c);
	vec3 d = path(TIME + 0.05, c) - p;
	vec2 h = normalize(d.xz + vec2(1e-4, 0.0));

	vec3 v = VERTEX;
	belly = smoothstep(0.02, -0.05, v.y);
	// tail wiggle grows towards the back, faster when swimming faster
	float sw = 7.0 + abs(c.y) * 10.0;
	float tail = smoothstep(0.15, -0.5, v.x);
	v.z += sin(TIME * sw - v.x * 7.0 + c.z * 9.0) * 0.12 * (0.25 + tail);
	v *= fish_len;

	// yaw the fish onto its heading
	VERTEX = vec3(v.x * h.x - v.z * h.y, v.y, v.x * h.y + v.z * h.x) + p;
	NORMAL = vec3(NORMAL.x * h.x - NORMAL.z * h.y, NORMAL.y, NORMAL.x * h.y + NORMAL.z * h.x);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = apply_focus(mix(mix(back_col, belly_col, belly), water_tint, 0.3), wpos);
	ALPHA = opacity;
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
