// vegetation.ts grass + wildflowers on the GPU field lattice: three-blade clumps (or a 7-petal flower),
// per-instance height / width / colour / dryness from the same noises as the reference, wind bend,
// player push, distance widening, and the reference's distance density LOD (full to 16 m, then
// (16/d)^1.8, faded out at max_dist). PBR with back-lit translucency.
// blade_detail = 1 (the valley's fields, whose clumps carry UV across / up each blade and the blade's own
// random in COLOR): every blade takes its own shade - now and then a dried-out straw one - a paler midrib,
// a V fold that splits it into a lit and a shaded half, a waxy sheen, and a deeper green where the sun
// shines through it.
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"
#include "res://shaders/field.gdshaderinc"

global uniform vec3 player_pos;
uniform float target_density = 14.0;     // clumps per m2 next to the camera
uniform float near_full = 16.0;
uniform float max_dist = 70.0;
uniform float grass_transl = 0.6;
uniform vec3 g_deep : source_color = vec3(0.184, 0.29, 0.09);   // #2f4a17
uniform vec3 g_mid : source_color = vec3(0.357, 0.455, 0.141);  // #5b7424
uniform vec3 g_tip : source_color = vec3(0.663, 0.706, 0.322);  // #a9b452
uniform vec3 g_dry : source_color = vec3(0.561, 0.541, 0.29);   // #8f8a4a
uniform float blade_detail = 0.0;

varying vec4 vg;
varying vec3 wpos;
varying vec3 wn;
varying vec3 blade_x;   // across the blade (world)
varying vec3 g_glow;    // colour of the light through the blade, relative to its albedo
varying vec4 fogv;      // aerial perspective, per vertex
#ifdef FLOWER
varying vec3 petal;
#endif

float sn(vec2 p) { return vh_vnoise(p) * 2.0 - 1.0; }

void vertex() {
	vec4 par;
	float keep;
	vec2 x;
	float root_y;
	float camD;
	float c0 = 1.0, s0 = 0.0;
	float gT = clamp(VERTEX.y, 0.0, 1.0);
#ifdef INSTANCED
	// instance = translate(aOffset.xyz) * rotY(-aOffset.w); custom = aParams; distance LOD on the CPU
	x = MODEL_MATRIX[3].xz;
	root_y = MODEL_MATRIX[3].y;
	camD = distance(CAMERA_POSITION_WORLD.xz, x);
	par = INSTANCE_CUSTOM;
	keep = 1.0;
#ifdef FLOWER
	petal = par.yzw;
	float widen = 1.0 + camD * 0.012;
#else
	float widen = 1.0 + camD * 0.03;
#endif
#else
	vec3 hs;
	vec4 fp = field_place(MODEL_MATRIX[3].xyz, NODE_POSITION_WORLD, hs);
	vec4 h2 = fract(hs.xyzx * vec4(97.13, 61.71, 43.37, 29.93) + hs.yzxy * 7.31);
	camD = distance(CAMERA_POSITION_WORLD.xz, fp.xz);
	float f = camD < near_full ? 1.0 : pow(near_full / camD, 1.8);
	float fade = 1.0 - smoothstep(max_dist * 0.75, max_dist, camD);
	keep = fp.w * step(h2.w, target_density * f * fade * spacing * spacing);
	vec2 muv = (fp.xz - map_rect.xy) / map_rect.zw;
	float above = fp.y - textureLod(height_tex, muv, 0.0).b;
	x = fp.xz;
	root_y = fp.y;
	float rot = hs.x * TAU;
	c0 = cos(rot);
	s0 = sin(rot);
#ifdef FLOWER
	keep *= step(h2.x, smoothstep(0.35, 0.65, sn(x * 0.11 + vec2(40.0, -12.0))));
	float ci = sn(x * 0.02 + vec2(-5.0, 8.0)) > 0.35 ? 2.0 + floor(h2.y * 2.999) : floor(h2.y * 1.999);
	petal = ci < 0.5 ? vec3(0.95, 0.95, 0.92) : ci < 1.5 ? vec3(0.97, 0.96, 0.9) : ci < 2.5 ? vec3(0.95, 0.84, 0.3) : ci < 3.5 ? vec3(0.72, 0.6, 0.92) : vec3(0.98, 0.78, 0.84);
	par = vec4(0.2 + h2.z * 0.18, petal);
	float widen = 1.0 + camD * 0.012;
#else
	float tall = clamp(smoothstep(-0.35, 0.55, sn(x * 0.045 + vec2(7.0, 0.0))) + (1.0 - smoothstep(0.3, 2.5, above)) * 0.35, 0.0, 1.0);
	par = vec4(mix(0.12, 0.4, tall) * (0.75 + h2.x * 0.5), 0.85 + h2.y * 0.45,
		clamp(sn(x * 0.03) * 0.5 + 0.5 + (h2.z - 0.5) * 0.35, 0.0, 1.0),
		clamp(smoothstep(0.25, 0.75, sn(x * 0.06 + vec2(3.0, -9.0)) * 0.5 + 0.5) * 0.55 + fract(h2.w * 13.7) * 0.15 - (1.0 - smoothstep(0.3, 2.0, above)) * 0.4, 0.0, 0.8));
	float widen = 1.0 + camD * 0.03;
#endif
#endif
	vec3 bx = vec3(c0 * NORMAL.z + s0 * NORMAL.x, 0.0, s0 * NORMAL.z - c0 * NORMAL.x);
#ifdef INSTANCED
	bx = mat3(MODEL_MATRIX) * bx;
#endif
	blade_x = normalize(bx + vec3(1e-5, 0.0, 0.0));
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + 0.3 * vec3(c0 * NORMAL.x - s0 * NORMAL.z, 0.0, s0 * NORMAL.x + c0 * NORMAL.z));
	vec3 t = VERTEX;
	t.xz *= par.y * widen;
	t.y *= par.x;
	t.xz = vec2(c0 * t.x - s0 * t.z, s0 * t.x + c0 * t.z);
	float wv = sin(TIME * 1.6 + dot(x, vec2(0.31, 0.23))) * 0.55 + sin(TIME * 2.7 + x.x * 0.9 + x.y * 0.6) * 0.2;
	float gust = 0.5 + 0.5 * sin(TIME * 0.45 + x.x * 0.05 + x.y * 0.035);
	vec2 bend = vh_wind * (0.06 + 0.15 * gust) * (0.6 + wv) * gT * gT * par.x;
	vec2 toP = x - player_pos.xz;
	float dP = length(toP);
	float push = (1.0 - smoothstep(0.2, 0.95, dP)) * (1.0 - smoothstep(0.4, 1.4, abs(root_y - player_pos.y)));
	bend += (toP / max(dP, 0.001)) * push * 0.6 * gT * par.x;
#ifdef INSTANCED
	t.xz += (transpose(mat3(MODEL_MATRIX)) * vec3(bend.x, 0.0, bend.y)).xz;
	t.y -= dot(bend, bend) * 0.5 / max(par.x, 0.05);
	VERTEX = t;
#else
	t.xz += bend;
	t.y -= dot(bend, bend) * 0.5 / max(par.x, 0.05);
	VERTEX = t * keep + (vec3(x.x, root_y - 0.03, x.y) - MODEL_MATRIX[3].xyz);
#endif
	vg = vec4(gT, par.z, par.w, par.y);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = NORMAL;
	fogv = vh_fog(wpos, CAMERA_POSITION_WORLD);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 nb = normalize(wn);
#ifdef FLOWER
	float is_petal = step(0.9, COLOR.r * COLOR.g * COLOR.b);
	ALBEDO = mix(COLOR.rgb, petal, is_petal);
	ROUGHNESS = 0.6;
#else
	vec3 gb = mix(vh_lin(g_deep), vh_lin(g_mid), vg.y);
	gb = mix(gb, vh_lin(g_dry), vg.z * (blade_detail > 0.0 ? 0.6 : 1.0));
	g_glow = vec3(1.0);
	if (blade_detail > 0.0) {
		// the blade's own shade, a yellower or a bluer green; one in twelve or so dried to straw
		gb *= mix(vec3(0.9, 1.0, 1.05), vec3(1.03, 1.03, 0.9), COLOR.r) * (0.86 + 0.28 * fract(COLOR.r * 13.7));
		gb = mix(gb, vh_lin(vec3(0.6, 0.57, 0.34)) * (0.85 + 0.3 * COLOR.r), COLOR.g * 0.6);
	}
	vec3 gtip = blade_detail > 0.0 ? mix(gb * 1.15, vh_lin(g_tip), 0.06 + 0.18 * vg.z) : mix(gb * 1.4, vh_lin(g_tip), 0.35 + 0.35 * vg.z);
	vec3 gcol = mix(gb * 0.38, gb, smoothstep(0.0, 0.42, vg.x));
	ALBEDO = mix(gcol, gtip, smoothstep(0.45, 1.0, vg.x));
	ROUGHNESS = 0.72;
	if (blade_detail > 0.0) {
		float side = UV.x * 2.0 - 1.0;
		ALBEDO *= 1.0 + 0.08 * (1.0 - smoothstep(0.0, 0.2, abs(side))) - 0.1 * smoothstep(0.7, 1.0, abs(side));
		nb = normalize(nb + blade_x * side * 0.35);
		NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
		ROUGHNESS = 0.62;
		g_glow = mix(vec3(1.0), clamp(ALBEDO / max(dot(ALBEDO, vec3(0.3333)), 1e-4), vec3(0.0), vec3(2.5)) * vec3(1.05, 1.0, 0.7), 0.6);
	}
#endif
	vec3 em = ALBEDO * vh_indirect(nb);
	em += vh_ibl_spec(NORMAL, VIEW, ROUGHNESS, vec3(0.04), INV_VIEW_MATRIX);
	em += vh_lamps(wpos, nb, CAMERA_POSITION_WORLD, ROUGHNESS, ALBEDO, 0.6);
	vh_fog_a = vh_finish_v(fogv, wpos, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
#ifdef FLOWER
	d += vh_transl(VIEW, LIGHT, LIGHT_COLOR, att, 0.4);
#else
	d += vh_transl(VIEW, LIGHT, LIGHT_COLOR, att, grass_transl) * g_glow;
#endif
	vh_out(d, s, vh_alb, SPECULAR_LIGHT);
}
