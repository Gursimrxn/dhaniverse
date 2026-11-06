shader_type spatial;
// Leaves and petals drifting down from the tree crowns (the prototype's ReferenceCity._animate_falling,
// moved to the GPU). One instance per leaf: origin = trunk base, custom = (phase, cycle offset, start
// height, crown radius), colour = leaf tint. Each leaf spirals down from the crown on a loop, swinging
// like a pendulum and tumbling, drifts downwind, and is lit like the canopy (GGX + back-lit translucency).
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

uniform float transl = 0.6;

varying vec3 wpos;
varying vec3 wn;

mat3 rot(vec3 a) {
	vec3 s = sin(a), c = cos(a);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c.x, s.x), vec3(0.0, -s.x, c.x));
	mat3 ry = mat3(vec3(c.y, 0.0, -s.y), vec3(0.0, 1.0, 0.0), vec3(s.y, 0.0, c.y));
	mat3 rz = mat3(vec3(c.z, s.z, 0.0), vec3(-s.z, c.z, 0.0), vec3(0.0, 0.0, 1.0));
	return ry * rx * rz;
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float ph = c.x * TAU;
	float speed = 0.32 + fract(c.x * 13.7) * 0.3;               // m/s descent
	float prog = fract(c.y + TIME * speed / c.z);
	float ang = ph + TIME * 0.19;
	float swing = sin(TIME * 1.7 + ph * 3.0);
	float r = c.w * (0.35 + 0.65 * fract(c.x * 7.31));
	vec3 p = vec3(cos(ang) * r, c.z * (1.0 - prog), sin(ang) * r);
	p.xz += vec2(-sin(ang), cos(ang)) * swing * 0.35 + vh_wind * prog * c.z * 0.45;
	float s = smoothstep(0.0, 0.05, prog) * (1.0 - smoothstep(0.88, 1.0, prog)) * (0.75 + fract(c.x * 31.1) * 0.5);
	mat3 m = rot(vec3(ph + TIME * 1.2 + swing * 0.6, ang * 2.0, swing * 0.8));
	VERTEX = m * VERTEX * s + p;
	NORMAL = m * NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	// leaf outline: pointed ellipse with a midrib, no texture
	vec2 q = UV * 2.0 - 1.0;
	float w = 0.6 * pow(max(1.0 - q.y * q.y, 0.0), 0.7) * (1.0 + 0.2 * q.y);
	if (abs(q.x) > w) discard;
	float rib = 1.0 - smoothstep(0.03, 0.08, abs(q.x));
	ALBEDO = vh_lin(COLOR.rgb) * (0.8 + 0.2 * abs(q.x) / max(w, 1e-3)) * (1.0 - rib * 0.22);
	ROUGHNESS = 0.68;
	vec3 em = ALBEDO * vh_indirect(wn);
	em += vh_ibl_spec(NORMAL, VIEW, ROUGHNESS, vec3(0.04), INV_VIEW_MATRIX);
	em += vh_lamps(wpos, wn, CAMERA_POSITION_WORLD, ROUGHNESS, ALBEDO, 0.5);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d + vh_transl(VIEW, LIGHT, LIGHT_COLOR, att, transl), s, vh_alb, SPECULAR_LIGHT);
}
