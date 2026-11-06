shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/vh/vh.gdshaderinc"

// MeshBasicMaterial(colour x intensity): HDR emitters for the bloom (LED tubes, rails, lamp glass, city
// glow). With the lights off (vh_glow.x = 0, daytime) they show as pale frosted glass; day_on keeps an
// emitter lit regardless (the capital's rings and strips).
uniform vec3 color : source_color = vec3(1.0, 0.835, 0.635);   // #ffd5a2
uniform float energy = 7.0;
uniform float day_on = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 c = vh_lin(color);
	ALBEDO = vh_fogged(mix(c * 0.6 * vh_unlit, c * energy, max(vh_glow.x, day_on)), wpos, CAMERA_POSITION_WORLD, vh_outside(wpos));
}
