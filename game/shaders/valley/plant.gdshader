shader_type spatial;
// Small plants drawn by the thousand (scripts/valley/port_dressing.gd): reeds, long grass, flowers, lily pads. The colour is the mesh's own;
// lit by the valley's sun and sky and fogged with it, as everything else. UV.y is how far up the plant a vertex is: that's how far it sways.
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

uniform float sway = 0.06;          // m at the tip
uniform float rough = 0.85;
uniform float flap = 0.0;           // m, up and down at the tip: wings

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.4 + at.x * 0.31 + at.z * 0.23;
	VERTEX.xz += vec2(sin(t), cos(t * 0.8)) * sway * UV.y * UV.y;
	VERTEX.y += sin(TIME * 5.0 + at.x) * flap * UV.x;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 col = vh_lin(COLOR.rgb);
	vec3 n = normalize(wn);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	vec3 em = col * vh_indirect(n);
	em += vh_lamps(wpos, n, CAMERA_POSITION_WORLD, rough, col, 0.0);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0);
	vec3 s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d, s, vh_alb, SPECULAR_LIGHT);
}
