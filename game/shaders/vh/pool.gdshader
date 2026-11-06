shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// structures.ts light pools: terrain-conforming additive warm discs under the bollards (and, at night,
// under the street lamps). Near the player the real lamp light (vh_lamps) takes over from them.
uniform vec3 color : source_color = vec3(1.0, 0.722, 0.467);   // #ffb877
uniform float energy = 0.55;
uniform int drive = 0;            // 0: lit with the LEDs (bollards), 1: night only (street lamps)
uniform sampler2D t_glow : filter_linear, repeat_disable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 f = vh_fog(wpos, CAMERA_POSITION_WORLD);
	float k = drive == 0 ? vh_glow.x : vh_glow.w;
	float real = 1.0 - smoothstep(vh_lamp_fade.x, vh_lamp_fade.y, distance(wpos.xz, vh_focus.xz));
	k *= 1.0 - real * vh_lamp_fade.z;
	ALBEDO = vh_raw(vh_lin(color) * energy * k * texture(t_glow, UV).a * (1.0 - f.a) * (1.0 - vh_outside(wpos)));
}
