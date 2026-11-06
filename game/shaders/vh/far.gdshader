shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// Far hills beyond the playable valley: the terrain material's grass / dry grass / rock blend at
// landscape scale (no splat map out here), same light and aerial perspective.
uniform sampler2D t_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.275, 0.353, 0.133);
uniform vec3 grass_b : source_color = vec3(0.384, 0.455, 0.173);
uniform vec3 grass_dry : source_color = vec3(0.522, 0.478, 0.275);
uniform vec3 rock_tint : source_color = vec3(0.886, 0.863, 0.831);

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = normalize(wn);
	vec4 nz = texture(t_noise, wpos.xz * 0.004);
	vec4 nz2 = texture(t_noise, wpos.xz * 0.017 + vec2(0.37, 0.11));
	vec3 g = mix(vh_lin(grass_a), vh_lin(grass_b), smoothstep(0.3, 0.72, nz.r));
	g = mix(g, vh_lin(grass_dry), smoothstep(0.55, 0.82, nz2.g) * 0.5);
	vec3 b = vh_tri_w(n);
	vec3 r = vh_lin(vh_tri_albedo(t_rock, wpos * 0.05, b, 0.16)) * vh_lin(rock_tint);
	vec3 col = mix(g, r, smoothstep(0.2, 0.4, 1.0 - n.y));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	vec3 em = col * vh_indirect(n);
	em += vh_ibl_spec(NORMAL, VIEW, 0.95, vec3(0.04), INV_VIEW_MATRIX);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d, s, vh_alb, SPECULAR_LIGHT);
}
