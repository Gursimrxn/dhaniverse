shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// water.ts spray mist: camera-facing glow puffs rising and growing from the falls' foot.
// INSTANCE_CUSTOM: xyz = spawn point (world), w = phase.
uniform sampler2D t_glow : filter_linear, repeat_disable;
varying float va;
varying vec3 wpos;

void vertex() {
	vec4 m = INSTANCE_CUSTOM;
	float t = fract(TIME * 0.04 + m.w);
	vec3 c = m.xyz + vec3(sin(m.w * 23.0 + TIME * 0.2) * 0.7, t * 3.4, t * 1.6);
	float size = 2.6 + t * 4.5;
	vec3 camR = INV_VIEW_MATRIX[0].xyz;
	vec3 camU = INV_VIEW_MATRIX[1].xyz;
	wpos = c + (camR * VERTEX.x + camU * VERTEX.y) * size;
	va = sin(t * 3.14159);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}

void fragment() {
	ALBEDO = vh_fogged(vec3(0.95, 0.9, 0.95) * vh_unlit, wpos, CAMERA_POSITION_WORLD, 0.0);
	ALPHA = texture(t_glow, UV).a * va * 0.2;
	ALPHA *= 1.0 - vh_outside(wpos) * 0.85;
}
