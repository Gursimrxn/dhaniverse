shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// The player's materials, physically based and lit by the valley's sun / moon, sky, lamps and haze like
// everything else. Each material carries its own fine detail, drawn procedurally in the mesh's own space (so
// it moves with the cloth) and faded out where it would get finer than a pixel (so it never shimmers):
//   0 skin   - fine mottling and pores, light that wraps round and comes out warm (a cheap subsurface)
//   1 linen  - a plain weave, the threads catching the light; a soft sheen at grazing angles
//   2 denim  - a diagonal twill, indigo warp over pale weft
//   3 leather- a pebbled grain, a satin highlight
//   4 hair   - strands running down the hair, a highlight that streaks along them
//   5 rubber - the sneakers' soles and toe caps, matte with a faint tread
//   6 eye    - the white of the eye, moist and glossy
//   7 iris   - dark brown, a darker ring and pupil, a bright catchlight from the sky
//   8 canvas - a coarse weave for the bag
//   9 metal  - the watch case and buckles
//  10 wool   - a dense fibre nap for the robe, trousers and hat, with a soft sheen at the edges
uniform vec3 albedo : source_color = vec3(0.8);
uniform int kind = 1;
uniform float detail = 1.0;        // scale of the weave / grain (1: the default for the material)

varying vec3 wpos;
varying vec3 wn;
varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// A pattern's fade with distance: 1 while a cell spans many pixels, 0 once it is under about two.
float keep(vec3 p, float cell) {
	float w = length(fwidth(p));
	return 1.0 - smoothstep(cell * 0.25, cell * 0.8, w);
}

// Bump the world normal along the screen-space slope of a height field (surface gradient, as in building.gdshader).
vec3 bump(vec3 n, float h) {
	vec3 dpx = dFdx(wpos), dpy = dFdy(wpos);
	vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 sg = (dFdx(h) * r1 + dFdy(h) * r2) / (abs(det) > 1e-12 ? det : 1e-12);
	return normalize(n - sg / max(1.0, length(sg) / 0.8));
}

varying float wrap_k;       // how far the light wraps round (skin, cloth)
varying vec3 scatter_tint;  // colour of the light that wraps (skin: warm)
varying float sheen_k;      // cloth's grazing sheen

void fragment() {
	vec3 col = vh_lin(albedo);
	vec3 n = normalize(wn);
	float rough = 0.85;
	float spec_f0 = 0.04;
	float h = 0.0;
	float ao = 1.0;
	wrap_k = 0.0;
	scatter_tint = vec3(1.0);
	sheen_k = 0.0;
	vec3 p = lpos * detail;
	if (kind == 0) {             // skin
		float k = keep(p, 0.004);
		float pores = (vh_vnoise(p.xy * 260.0 + p.z * 90.0) - 0.5) * k;
		float mottle = vh_vnoise(p.xz * 40.0 + p.y * 13.0) - 0.5;
		col *= 1.0 + mottle * 0.07 + pores * 0.05;
		h = pores * 0.00025;
		rough = 0.52 + pores * 0.08;
		wrap_k = 0.45;
		scatter_tint = vec3(1.0, 0.55, 0.42);
		spec_f0 = 0.028;
	} else if (kind == 1) {      // linen
		float k = keep(p, 0.003);
		vec2 q = vec2(p.x + p.z, p.y) * 380.0;
		float weave = (sin(q.x) * sin(q.y) * 0.5 + 0.5);
		float slub = vh_vnoise(vec2(p.y * 60.0, (p.x + p.z) * 7.0)) - 0.5;
		col *= 1.0 + ((weave - 0.5) * 0.08 + slub * 0.06) * k;
		h = (weave - 0.5) * 0.0004 * k;
		rough = 0.86;
		wrap_k = 0.25;
		sheen_k = 0.35;
	} else if (kind == 2) {      // denim twill
		float k = keep(p, 0.003);
		float tw = fract((p.y * 1.0 + (p.x + p.z) * 0.6) * 260.0);
		float ridge = smoothstep(0.0, 0.5, tw) * (1.0 - smoothstep(0.5, 1.0, tw));
		float weft = step(0.82, vh_vnoise((p.xy + p.z) * 520.0));
		float fade = vh_vnoise(p.xy * 5.0 + p.z * 3.0);
		col = mix(col, col * 1.6 + vec3(0.03, 0.035, 0.05), weft * 0.35 * k);
		col *= 0.92 + ridge * 0.14 * k + (fade - 0.5) * 0.12;
		h = ridge * 0.0005 * k;
		rough = 0.9;
		wrap_k = 0.15;
		sheen_k = 0.2;
	} else if (kind == 3) {      // leather
		float k = keep(p, 0.002);
		float grain = vh_vnoise(p.xy * 420.0 + p.z * 211.0) * 0.6 + vh_vnoise(p.yz * 900.0) * 0.4;
		col *= 0.94 + grain * 0.12 * k;
		h = grain * 0.0003 * k;
		rough = 0.48 + grain * 0.12;
	} else if (kind == 4) {      // hair: strands along the local y (down the hair), across in x/z
		float k = keep(p, 0.0015);
		float strands = vh_vnoise(vec2((p.x + p.z) * 900.0, p.y * 18.0)) - 0.5;
		float clump = vh_vnoise(vec2((p.x - p.z) * 70.0, p.y * 4.0)) - 0.5;
		col *= 1.0 + strands * 0.35 * k + clump * 0.25;
		h = strands * 0.0006 * k;
		rough = 0.42;
		spec_f0 = 0.046;
		wrap_k = 0.2;
	} else if (kind == 5) {      // rubber
		float tread = step(0.5, fract(p.z * 90.0)) * keep(p, 0.006);
		col *= 0.95 + tread * 0.06;
		h = tread * 0.0004;
		rough = 0.8;
	} else if (kind == 6) {      // eye white: moist
		col *= 1.0 - 0.18 * smoothstep(0.004, 0.012, length(lpos.xy));
		rough = 0.12;
		spec_f0 = 0.035;
		wrap_k = 0.3;
		scatter_tint = vec3(1.0, 0.8, 0.75);
	} else if (kind == 7) {      // iris and pupil
		float r = length(lpos.xy) / 0.0085;
		vec3 iris = mix(col * 1.35, col * 0.55, smoothstep(0.55, 1.0, r));
		col = mix(vec3(0.012), iris, smoothstep(0.32, 0.4, r));
		rough = 0.08;
		spec_f0 = 0.04;
	} else if (kind == 8) {      // canvas
		float k = keep(p, 0.004);
		vec2 q = vec2(p.x + p.z, p.y) * 220.0;
		float weave = sin(q.x) * sin(q.y) * 0.5 + 0.5;
		col *= 0.92 + weave * 0.14 * k;
		h = weave * 0.0006 * k;
		rough = 0.9;
		sheen_k = 0.15;
	} else if (kind == 10) {     // wool: a dense fibre nap, soft and matte, a fuzzy sheen where it turns away from the light
		float k = keep(p, 0.002);
		float nap = vh_vnoise(p.xy * 640.0 + p.z * 310.0) * 0.6 + vh_vnoise(p.yz * 1400.0) * 0.4;
		float weave = sin((p.x + p.z) * 900.0) * sin(p.y * 900.0) * 0.5 + 0.5;
		col *= 0.9 + nap * 0.16 * k + weave * 0.04 * k;
		h = (nap - 0.5) * 0.0004 * k;
		rough = 0.93;
		wrap_k = 0.3;
		sheen_k = 0.8;
	} else if (kind == 9) {      // metal
		rough = 0.3;
		spec_f0 = 0.6;
	}
	// contact shade: where a part tucks in underneath (armpits, under the chin, inside the cuffs)
	ao = mix(0.72, 1.0, smoothstep(-0.8, 0.4, n.y));
	vec3 nb = (h != 0.0) ? bump(n, h) : n;
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	vec3 f0 = mix(vec3(spec_f0), col, kind == 9 ? 0.85 : 0.0);
	vec3 em = col * vh_indirect(nb) * ao;
	em += vh_ibl_spec(NORMAL, VIEW, rough, f0, INV_VIEW_MATRIX) * ao;
	em += vh_lamps(wpos, nb, CAMERA_POSITION_WORLD, rough, col, wrap_k);
	if (kind == 7) {
		// the catchlight: the bright sky caught on the cornea, high on the iris
		float cl = 1.0 - smoothstep(0.0015, 0.0026, length(lpos.xy - vec2(0.0028, 0.003)));
		em += vec3(1.0) * cl * (0.6 + 0.6 * dot(vh_indirect(vec3(0.0, 1.0, 0.0)), vec3(0.33)));
	}
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	float att = LIGHT_IS_DIRECTIONAL ? vh_sun_att(wpos, ATTENUATION) : ATTENUATION;
	float ndl = dot(NORMAL, LIGHT);
	// wrapped diffuse: the light rounds the terminator; on skin the wrapped part comes out warm
	float lam = max(ndl, 0.0);
	float wr = max((ndl + wrap_k) / (1.0 + wrap_k), 0.0);
	vec3 diff = LIGHT_COLOR * att / PI * (lam + (wr - lam) * scatter_tint);
	// cloth sheen at grazing view and light
	float vdn = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	diff += LIGHT_COLOR * att / PI * sheen_k * pow(vdn, 4.0) * max(ndl + 0.3, 0.0);
	vec3 d = vec3(0.0), s = vec3(0.0);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(diff, s, vh_alb, SPECULAR_LIGHT);
}
