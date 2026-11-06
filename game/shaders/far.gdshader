shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

// Distant hills ring: forest-covered slopes read as soft dappled silhouettes; fog does the depth.
uniform vec3 low_col : source_color = vec3(0.2, 0.36, 0.2);
uniform vec3 high_col : source_color = vec3(0.24, 0.36, 0.33);
uniform vec3 meadow_col : source_color = vec3(0.4, 0.55, 0.2);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float canopy = smoothstep(0.35, 0.65, fbm2(wpos.xz * 0.02));
	vec3 col = mix(meadow_col, low_col, canopy * smoothstep(-2.0, 12.0, wpos.y));
	col = mix(col, high_col, smoothstep(30.0, 160.0, wpos.y));
	col *= 0.85 + vnoise(wpos.xz * 0.15) * 0.25 * canopy;
	ALBEDO = apply_focus(col, wpos);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
