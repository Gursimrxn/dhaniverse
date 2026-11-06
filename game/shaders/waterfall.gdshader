shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
#include "res://shaders/common.gdshaderinc"

// Falling water ribbon. UV.x across the fall (0..1), UV.y down the fall (0 = lip, 1 = impact).
// UV2.x = ribbon length in metres (keeps streak density even across steps).
uniform vec3 water_col : source_color = vec3(0.45, 0.85, 0.85);
uniform vec3 deep_col : source_color = vec3(0.12, 0.55, 0.6);
uniform vec3 foam_col : source_color = vec3(1.0, 1.0, 0.98);
uniform float speed = 1.6;
uniform float seed = 0.0;
uniform float opacity = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// slight shimmer outwards, growing towards the bottom
	VERTEX += NORMAL * sin(UV.x * 23.0 + TIME * 6.0 + seed) * 0.03 * UV.y;
}

void fragment() {
	float len = max(UV2.x, 0.5);
	vec2 p = vec2(UV.x * 18.0 + seed * 3.1, UV.y * len * 1.4 - TIME * speed * 1.4);
	// long vertical streaks: stretched noise
	float s1 = vnoise(vec2(p.x, p.y * 0.35));
	float s2 = vnoise(vec2(p.x * 2.3 + 5.0, p.y * 0.6 - TIME * 0.6));
	float streak = smoothstep(0.45, 0.85, s1 * 0.6 + s2 * 0.5);

	vec3 col = mix(deep_col, water_col, 0.45 + s2 * 0.4);
	// white edges + foamy lip + boiling impact
	float edge = 1.0 - smoothstep(0.0, 0.14, min(UV.x, 1.0 - UV.x));
	float lip = 1.0 - smoothstep(0.0, 0.18, UV.y);
	float base = smoothstep(0.6, 1.0, UV.y);
	float foam = clamp(streak * 0.8 + edge * 0.7 + lip * 0.65 + base * (0.5 + s1 * 0.6), 0.0, 1.0);
	col = mix(col, foam_col, foam);

	// ragged sides and a broken bottom edge
	float side = smoothstep(0.0, 0.05 + s2 * 0.05, min(UV.x, 1.0 - UV.x));
	float bottom = 1.0 - smoothstep(0.88 + s1 * 0.06, 1.0, UV.y);
	float a = (0.62 + foam * 0.38) * side * bottom;

	ALBEDO = apply_focus(col * mix(1.0, 0.85, cloud_shadow(wpos)), wpos);
	ALPHA = a * opacity;
}
