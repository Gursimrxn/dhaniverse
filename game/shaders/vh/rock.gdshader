shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// rocks.ts createRockMaterial: triplanar stone x vertex AO, moss on top faces, wet + darker at the
// waterline, triplanar normal (scale 1.2).
uniform sampler2D t_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rock_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 base : source_color = vec3(0.812, 0.788, 0.753);   // #cfc9c0
uniform vec3 moss : source_color = vec3(0.294, 0.369, 0.141);   // #4b5e24

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 rn = normalize(wn);
	vec3 rb = vh_tri_w(rn);
	vec3 col = vh_lin(base) * COLOR.rgb * vh_lin(vh_tri_albedo(t_rock, wpos, rb, 0.42)) * 2.2;
	float mn = texture(t_noise, wpos.xz * 0.11).b * 0.6 + texture(t_noise, wpos.xz * 0.37 + wpos.y * 0.1).a * 0.4;
	float mo = smoothstep(0.35, 0.8, rn.y + (mn - 0.5) * 0.9) * smoothstep(0.25, 0.6, mn);
	col = mix(col, vh_lin(moss) * (0.75 + mn * 0.5), mo * 0.85);
	float lvl = texture(field_tex, (wpos.xz - map_rect.xy) / map_rect.zw).b;
	float wet = 1.0 - smoothstep(0.0, 0.3, wpos.y - lvl);
	col *= mix(1.0, 0.45, wet);
	col *= mix(1.0, 0.55, smoothstep(0.0, 0.8, lvl - wpos.y));
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.9, 0.35, wet), 1.0, mo);
	vec3 nW = vh_tri_normal(t_rock_n, wpos, rn, rb, 0.42, 1.2);
	NORMAL = normalize((VIEW_MATRIX * vec4(nW, 0.0)).xyz);
	vec3 em = col * vh_indirect(nW);
	em += vh_ibl_spec(NORMAL, VIEW, ROUGHNESS, vec3(0.04), INV_VIEW_MATRIX);
	em += vh_lamps(wpos, nW, CAMERA_POSITION_WORLD, ROUGHNESS, col, 0.0);
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
