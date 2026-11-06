shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// water.ts waterfall sheet: streaky falling water, bright at the foot, soft edges.
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x, v = UV.y;
	float s1 = vh_vnoise(vec2(u * 46.0, v * 5.0 - TIME * 3.4));
	float s2 = vh_vnoise(vec2(u * 110.0 + 7.0, v * 9.0 - TIME * 5.2));
	float streak = s1 * 0.6 + s2 * 0.4;
	float edge = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u);
	float a = (0.45 + 0.55 * smoothstep(0.35, 0.75, streak)) * edge * smoothstep(0.0, 0.07, v);
	vec3 c = mix(vec3(0.3, 0.33, 0.34), vec3(0.9, 0.88, 0.92), smoothstep(0.3, 0.8, streak));
	c = mix(c, vec3(1.0, 0.97, 0.98), smoothstep(0.7, 1.0, v) * 0.7);
	ALBEDO = vh_fogged(c * 0.8 * vh_unlit, wpos, CAMERA_POSITION_WORLD, 0.0);
	ALPHA = a * 0.88;
	ALPHA *= 1.0 - vh_outside(wpos) * 0.85;
}
