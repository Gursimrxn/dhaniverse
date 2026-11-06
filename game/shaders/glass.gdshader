shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.4, 0.62, 0.7);
uniform bool focused = false;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (focused && wpos.y > cut_height) discard;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// warm interior glow + sky reflection streak
	vec3 col = mix(tint * 0.5, vec3(0.95, 0.98, 1.0), 0.18);
	col += vec3(1.0, 0.9, 0.8) * fres * 0.5;
	ALBEDO = focused ? col : apply_focus(col, wpos);
	ALPHA = focused ? 0.25 : 0.6 + fres * 0.3;
	ROUGHNESS = 0.05;
	EMISSION = vec3(1.0, 0.85, 0.6) * 0.05 * (1.0 - focus_amount);
}
