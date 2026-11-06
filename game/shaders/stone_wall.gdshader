shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

// Dry-stacked river-stone retaining wall in world space (no textures).
// UV.x = metres along the wall, UV.y = metres up from the wall base.
uniform vec3 stone_a : source_color = vec3(0.66, 0.66, 0.63);
uniform vec3 stone_b : source_color = vec3(0.5, 0.52, 0.53);
uniform vec3 mortar : source_color = vec3(0.3, 0.31, 0.32);
uniform vec3 moss : source_color = vec3(0.33, 0.52, 0.27);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = UV * vec2(1.6, 2.6);
	float row = floor(p.y);
	p.x += hash12(vec2(row, 3.0)) * 0.7 + row * 0.37;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float id = hash12(cell + row * 17.0);
	// rounded stone with jittered size
	vec2 e = min(f, 1.0 - f);
	float edge = min(e.x * (0.8 + id * 0.4), e.y * 1.4);
	float stone = smoothstep(0.02, 0.09, edge);
	vec3 col = mix(stone_b, stone_a, id) * (0.9 + vnoise(UV * 6.0) * 0.18);
	col = mix(mortar, col, stone);
	// coping on top faces + moss creeping from the top and in shade
	float top = smoothstep(0.6, 0.9, wnorm.y);
	col = mix(col, stone_a * 1.05, top);
	float m = smoothstep(0.45, 0.8, vnoise(wpos.xz * 0.6 + wpos.y)) * (top * 0.8 + smoothstep(0.6, 1.0, fract(UV.y * 0.3)) * 0.3);
	col = mix(col, moss, m * 0.55);
	col *= 1.0 - cloud_shadow(wpos) * 0.15;
	ALBEDO = apply_focus(col, wpos);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
