shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/common.gdshaderinc"

// A soft light shaft on a quad strip. UV.y 0 = top (sky), 1 = ground.
uniform vec3 ray_col : source_color = vec3(1.0, 0.97, 0.85);
uniform float strength = 0.075;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float across = exp(-x * x * 4.0);
	float along = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	// slow breathing + streaks + dust motes
	float streak = 0.6 + 0.4 * vnoise(vec2(UV.x * 7.0 + TIME * 0.05, 0.0));
	float breathe = 0.75 + 0.25 * sin(TIME * 0.4 + wpos.x * 0.1);
	float motes = step(0.985, hash12(floor(vec2(UV.x * 40.0, UV.y * 60.0 - TIME * 0.6)))) * 0.8;
	// fade when the camera is inside or very close to the shaft
	float cam_d = length(wpos - CAMERA_POSITION_WORLD);
	float near = smoothstep(2.0, 9.0, cam_d);
	// a shaft seen face-on from above reads as a plank: fade it
	float side_on = 1.0 - pow(abs(dot(normalize(NORMAL), VIEW)), 2.0) * 0.75;
	float a = across * along * streak * breathe * near * side_on * strength * (1.0 - focus_amount);
	ALBEDO = ray_col * (a + motes * a * 2.0);
}
