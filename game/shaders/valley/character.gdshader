shader_type spatial;
// The player character's materials as authored (tools/blender/cozy_boy.py): colour x optional texture (the flannel
// plaid), roughness, metalness; lit by the valley's sun and sky and fogged with it, as shaders/vh/pbr.gdshader.
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rough = 0.7;
uniform float metal = 0.0;
uniform vec3 trail = vec3(0.0);     // how far this part hangs behind him (model units): a jacket's hem, hair
uniform float trail_from = 0.0;     // the model height it starts to swing from, and where it's swinging fully
uniform float trail_to = 0.0;
uniform bool colour_in_vertices = false;   // a townsperson's parts drawn as one: each part's colour (sRGB) is in its vertices

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	if (trail_from != trail_to) VERTEX += trail * smoothstep(trail_from, trail_to, VERTEX.y);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 col = colour_in_vertices ? vh_lin(COLOR.rgb) : vh_lin(albedo) * vh_lin(texture(albedo_tex, UV).rgb) * COLOR.rgb;     // vertex colour: the hard parts' colours and baked occlusion (linear)
	vec3 n = normalize(wn);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	vec3 em = col * vh_indirect(n) * (1.0 - metal);
	em += vh_ibl_spec(NORMAL, VIEW, rough, mix(vec3(0.04), col, metal), INV_VIEW_MATRIX);
	em += vh_lamps(wpos, n, CAMERA_POSITION_WORLD, rough, col * (1.0 - metal), 0.0);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0);
	vec3 s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d * (1.0 - metal), s * mix(vec3(1.0), vh_alb / 0.04, metal), vh_alb, SPECULAR_LIGHT);
}
