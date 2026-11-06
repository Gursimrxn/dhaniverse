shader_type spatial;
// just-a-simple-tree's leaf cards (foliage.js, wind.js), as the page moves and ages them:
//   wind     each card rides its branch's sway (wind.js sway(): the noise field drifting downwind, turbulence,
//            the branch's own swing) and rocks round its own centre (flutter(): two angles out of phase, harder
//            in a gust);
//   the year each card unfolds small and pale close in on its clump, grows out to its place, turns to the
//            autumn colours and drops, each in its own order (cardLife()); the tree's own season is the
//            year's (fol_season) moved on by season_spread x a random of the tree's, so with season_spread 1
//            every tree stands at its own time of year;
//   light    the clump's normals through the three-band ramp, the crown darker away from the sun (as the
//            page's shading), lit and fogged as the rest of the foliage (shaders/foliage/foliage.gdshaderinc).
// Vertex data: ValleyTrees._cards (CUSTOM0 centre + order, CUSTOM1 clump centre + packed swing, COLOR crown side + height).
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

#include "res://shaders/foliage/foliage.gdshaderinc"

uniform vec3 shadow_col : source_color = vec3(0.184, 0.459, 0.349);   // #2f7559
uniform vec3 mid_col : source_color = vec3(0.31, 0.62, 0.322);        // #4f9e52
uniform vec3 light_col : source_color = vec3(0.643, 0.82, 0.376);     // #a4d160
uniform vec3 turned_shadow : source_color = vec3(0.816, 0.388, 0.180); // #d0632e
uniform vec3 turned_mid : source_color = vec3(0.949, 0.635, 0.227);    // #f2a23a
uniform vec3 turned_light : source_color = vec3(0.969, 0.839, 0.416);  // #f7d66a
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float shadow_side = 0.435;    // how much the crown darkens away from the sun
uniform float flutter = 0.25;         // how far each card rocks, radians (wind.js)
uniform float season_spread = 1.0;    // 0: every tree at the year's season; 1: each at its own

// foliage.js
const float S1 = 0.49773;
const float S2 = 0.95455;
const float FLUSH = 0.25;
const float CHANGE = 0.05;
const float YOUNG_SIZE = 0.4;
const float YOUNG_REACH = 0.3;
const float YOUNG_PALE = 0.55;
const float PALE_LIGHT = 0.3;
const float TURN_FROM = 0.45;
const float TURN_SPAN = 0.3;
const float DROP_AFTER = 0.19;

varying vec3 v_b0;
varying vec3 v_b1;
varying vec3 v_b2;
varying float v_mul;
varying vec3 v_nw;
varying vec3 v_nv;
varying vec3 v_wp;

vec3 rot(vec3 v, vec3 axis, float a) {
	return v * cos(a) + cross(axis, v) * sin(a) + axis * dot(axis, v) * (1.0 - cos(a));
}

uniform float near_cut = 0.0;       // a far copy, drawn in one batch with the rest: a tree nearer than this has its close copy instead

void vertex() {
	vec3 centre = CUSTOM0.xyz;
	float order = CUSTOM0.w;
	vec3 clump = CUSTOM1.xyz;
	float whole = floor(CUSTOM1.w / 1024.0);
	float flex = whole / 1023.0;
	float phase = (CUSTOM1.w - whole * 1024.0) / 1023.0 * TAU;
	// the tree's own time of year
	float age = fract(fol_season + season_spread * fol_hash(floor(MODEL_MATRIX[3].xyz * 0.37) + 0.5));
	float unfold_at = order * (FLUSH - CHANGE);
	float turn_at = TURN_FROM + order * TURN_SPAN;
	float unfolded = smoothstep(unfold_at, unfold_at + CHANGE, age);
	float turned = smoothstep(turn_at, turn_at + CHANGE, age);
	float dropped = smoothstep(turn_at + DROP_AFTER, turn_at + DROP_AFTER + CHANGE, age);
	float size = mix(YOUNG_SIZE, 1.0, unfolded) * (1.0 - dropped);
	float out_k = mix(YOUNG_REACH, 1.0, unfolded);
	// flutter: the card rocks round its own centre, about two axes in its plane
	vec3 wc = (MODEL_MATRIX * vec4(centre, 1.0)).xyz;
	float t = TIME * fol_wind.z * 6.0 + fol_hash(centre * 13.7) * TAU;
	float gust = fol_noise(wc * fol_wind.w - fol_downwind() * TIME * fol_wind.z) + 1.0;
	float k = flutter * gust * (1.0 + fol_wind_extra.y);
	vec3 n = NORMAL;
	vec3 a1 = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 a2 = cross(n, a1);
	vec3 off = rot(rot(VERTEX - centre, a1, sin(t) * k), a2, sin(t * 1.3 + 1.7) * k);
	// placed: close in on its clump while young, out at its place grown; and the sway of its branch
	VERTEX = clump + (mix(clump, centre, out_k) - clump) + off * size + fol_to_model(MODEL_MATRIX, fol_sway(wc, COLOR.a, flex, phase));
	// drawn into the sun's shadow map: pushed a little away from the sun so a card does not shadow itself in stripes
	if (PROJECTION_MATRIX[3][3] > 0.5) VERTEX += fol_to_model(MODEL_MATRIX, -fol_sun_dir * 0.18);
	// young cards are paler; turning ones take the turned colours
	vec3 sc = fol_lin(shadow_col), mc = fol_lin(mid_col), lc = fol_lin(light_col);
	vec3 pale = mix(lc, vec3(1.0), PALE_LIGHT);
	v_b0 = mix(mix(mix(sc, pale, YOUNG_PALE), sc, unfolded), fol_lin(turned_shadow), turned);
	v_b1 = mix(mix(mix(mc, pale, YOUNG_PALE), mc, unfolded), fol_lin(turned_mid), turned);
	v_b2 = mix(mix(mix(lc, pale, YOUNG_PALE), lc, unfolded), fol_lin(turned_light), turned);
	// the crown's side away from the sun falls dark
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 side = mat3(MODEL_MATRIX) * (COLOR.rgb * 2.0 - 1.0) / scale;
	v_mul = mix(1.0, smoothstep(0.0, 1.0, (clamp(dot(side, fol_sun_dir), -1.0, 1.0) + 1.0) * 0.75), shadow_side);
	v_nw = normalize(mat3(MODEL_MATRIX) * n);
	v_nv = normalize((VIEW_MATRIX * vec4(v_nw, 0.0)).xyz);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// a far copy of a tree the close copy stands in for: folded to a point, so it costs no pixels at all (not drawn, then thrown away)
	if (near_cut > 0.0 && distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD) < near_cut) VERTEX = vec3(0.0);
}

void fragment() {
	if (fol_occludes(v_wp, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	ALPHA = texture(atlas, UV).r;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = v_nv;          // the clump's, the same on both faces of a card
	ALBEDO = vec3(1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float ndl = max(dot(NORMAL, LIGHT), 0.0);
		vec3 c = fol_cel(fol_lit(v_nw, ndl, ATTENUATION), v_b0, v_b1, v_b2, S1, S2) * v_mul * fol_dim;
		DIFFUSE_LIGHT += fol_emit(c, v_wp, INV_VIEW_MATRIX[3].xyz);
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * v_b1 * v_mul * 0.25;
	}
}
