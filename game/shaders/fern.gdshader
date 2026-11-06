shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

// Fern rosette: each frond is a curved strip. UV.x across (0..1), UV.y base->tip.
// INSTANCE_CUSTOM: r = colour var, g = size, b = phase
uniform vec3 base_col : source_color = vec3(0.12, 0.33, 0.2);
uniform vec3 tip_col : source_color = vec3(0.55, 0.78, 0.3);
uniform float leaflets = 15.0;

varying vec3 wpos;
varying float along;
varying float var;

void vertex() {
	along = UV.y;
	var = INSTANCE_CUSTOM.r;
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 wind_dir = normalize(vec2(1.0, 0.35));
	float gust = fbm2(root_w.xz * 0.08 - wind_dir * TIME * 0.4);
	float flutter = sin(TIME * 2.6 + INSTANCE_CUSTOM.b * 6.28 + VERTEX.x * 3.0) * 0.06;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (gust - 0.35) * 0.18 * wind_strength * along * along;
	off.y += flutter * along;
	vec3 pv = actor_push(root_w, 1.3);
	off += pv * 0.55 * along;
	off.y -= length(pv) * 0.35 * along;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// pinnate leaflets: tapered teeth either side of a midrib
	float x = abs(UV.x - 0.5) * 2.0;
	float seg = fract(UV.y * leaflets);
	float width = (1.0 - UV.y * 0.8) * (1.0 - smoothstep(0.0, 0.15, -UV.y + 0.05));
	float tooth = width * (1.0 - pow(abs(seg - 0.45) * 2.0, 1.4));
	float slant = x - (seg - 0.5) * 0.3;
	bool leaf = slant < tooth * 0.95 || x < 0.07;
	if (!leaf) discard;
	vec3 col = mix(base_col, tip_col, smoothstep(0.1, 0.95, UV.y));
	col *= 0.85 + var * 0.3;
	col *= 0.9 + 0.1 * (1.0 - x);
	col *= 1.0 - cloud_shadow(wpos) * 0.2;
	ALBEDO = apply_focus(col, wpos);
	float back = pow(clamp(dot(-VIEW, (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.6, 0.9, 0.3) * back * UV.y * 0.2 * (1.0 - focus_amount);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT) * 0.5 + 0.5, ATTENUATION, LIGHT_COLOR);
}
