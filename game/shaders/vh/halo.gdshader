shader_type spatial;
// The glow of a street lamp in the night air: a camera-facing soft sprite on each lamp head, pulled a
// little towards the camera so the lantern does not cut it. INSTANCE_CUSTOM = (lamp head xyz, size).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

uniform sampler2D t_glow : filter_linear, repeat_disable;
uniform vec3 color : source_color = vec3(1.0, 0.8, 0.55);
uniform float energy = 0.9;

varying vec3 wpos;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - c.xyz);
	wpos = c.xyz + to_cam * 0.45 + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * c.w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}

void fragment() {
	float fog = vh_fog(wpos, CAMERA_POSITION_WORLD).a;
	float g = texture(t_glow, UV).a;
	ALBEDO = vh_raw(vh_lin(color) * energy * (g * g * 0.6 + g * 0.4) * vh_glow.w * (1.0 - fog) * (1.0 - vh_outside(wpos)));
}
