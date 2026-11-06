shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

// Mesh: one curved tapered blade, UV.y 0 root -> 1 tip.
// INSTANCE_CUSTOM: r = colour variation, g = height scale, b = lean phase, a = flower tint
uniform vec3 root_col : source_color = vec3(0.1, 0.22, 0.07);
uniform vec3 mid_col : source_color = vec3(0.24, 0.42, 0.13);
uniform vec3 tip_col : source_color = vec3(0.55, 0.7, 0.25);
uniform vec3 dry_tip : source_color = vec3(0.72, 0.74, 0.36);
uniform float sway = 0.22;
uniform float push_radius = 1.1;

varying vec3 wpos;
varying float tip;
varying float var;

void vertex() {
	tip = UV.y;
	var = INSTANCE_CUSTOM.r;
	VERTEX.y *= INSTANCE_CUSTOM.g;
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// gusts travel across the meadow in world space
	vec2 wind_dir = normalize(vec2(1.0, 0.35));
	float gust = fbm2(root_w.xz * 0.07 - wind_dir * TIME * 0.35);
	float flutter = sin(TIME * 2.3 + INSTANCE_CUSTOM.b * 6.28 + root_w.x * 0.4) * 0.25;
	float bend = (gust * 1.4 - 0.25 + flutter) * sway * wind_strength * tip * tip;
	vec3 offset_w = vec3(wind_dir.x, 0.0, wind_dir.y) * bend;

	// part around the player and every nearby character
	vec3 pushv = actor_push(root_w, push_radius);
	float push = length(pushv);
	offset_w += pushv * 0.45 * tip;
	offset_w.y -= push * 0.25 * tip;

	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset_w, 0.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float patch = fbm2(wpos.xz * 0.09);
	vec3 col = mix(root_col, mid_col, smoothstep(0.0, 0.55, tip));
	vec3 t = mix(tip_col, dry_tip, smoothstep(0.62, 0.9, patch) * 0.55);
	col = mix(col, t, smoothstep(0.45, 1.0, tip));
	col *= 0.88 + var * 0.24;
	col *= 1.0 - cloud_shadow(wpos) * 0.2;
	ALBEDO = apply_focus(col, wpos);
	// warm translucency when looking towards the sun
	float back = pow(clamp(dot(-VIEW, (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz), 0.0, 1.0), 3.0);
	EMISSION = apply_focus(vec3(0.75, 0.95, 0.4) * back * tip * 0.25, wpos) * (1.0 - focus_amount);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT) * 0.6 + 0.4, ATTENUATION, LIGHT_COLOR);
}
