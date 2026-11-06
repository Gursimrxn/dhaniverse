shader_type spatial;
// Glazing as the town master's Blender material has it ("... | material | glazing"): the vertex colour, alpha =
// the vertex alpha x 0.28, roughness 0.19, mostly see-through (transmission 0.72). Here: blended over what is
// behind, the sky and sun reflected off it (stronger at grazing angles, as glass does), lit and fogged as the
// valley's other surfaces are (shaders/vh/pbr.gdshader).
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

uniform float alpha_scale = 0.28;
uniform bool use_vcol = true;         // the town master's glazing: its colour and alpha in the vertex colours
uniform vec3 tint : source_color = vec3(0.43, 0.53, 0.56);   // otherwise this colour (sRGB) at alpha 0.35
uniform float rough = 0.19;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 col = use_vcol ? COLOR.rgb : vh_lin(tint);
	float a0 = use_vcol ? COLOR.a * alpha_scale : 0.35;
	vec3 n = normalize(wn) * (FRONT_FACING ? 1.0 : -1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = col;
	ROUGHNESS = rough;
	ALPHA = clamp(a0 + fres * 0.6, 0.0, 1.0);
	vec3 em = col * vh_indirect(n) * 0.5;
	em += vh_ibl_spec(NORMAL, VIEW, rough, vec3(0.04), INV_VIEW_MATRIX) / max(ALPHA, 0.05);
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
