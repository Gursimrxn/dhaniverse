// Leaves (TreeFoliage): star clusters of folded diamond blades, real geometry, no texture. Three references
// meet here:
//   just-a-simple-tree (foliage.js; MIT, Mike Fernandez): lit with the clump's normal through the
//     three-band ramp, the crown darkened on its far side from the sun and by each cluster's AO, each clump
//     tinted a little off its neighbours; the season unfolds them small and pale, turns them, drops them.
//   the Blender bank trees (dhaniverse-v2 foliage_library.blend): crisp blades in two tones per cluster.
//     Each blade's fold facet bends the clump's normal a little (facet), so every leaf reads as a shape
//     inside the soft volume.
//   Dylearn's toon trees: a stepped rim of light on the sunlit silhouette; here also a stepped glow where
//     the sun shines through the crown towards the eye.
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;

#include "res://shaders/foliage/foliage.gdshaderinc"

uniform vec3 shadow_col : source_color = vec3(0.184, 0.459, 0.349);   // #2f7559
uniform vec3 mid_col : source_color = vec3(0.31, 0.62, 0.322);        // #4f9e52
uniform vec3 light_col : source_color = vec3(0.643, 0.82, 0.376);     // #a4d160
uniform vec3 turned_shadow : source_color = vec3(0.816, 0.388, 0.180); // #d0632e
uniform vec3 turned_mid : source_color = vec3(0.949, 0.635, 0.227);    // #f2a23a
uniform vec3 turned_light : source_color = vec3(0.969, 0.839, 0.416);  // #f7d66a
uniform float shadow_side = 0.435;    // how much the crown darkens away from the sun
uniform float ao = 0.54;              // how much each cluster's AO darkens it
uniform float flutter = 0.25;         // how far each cluster rocks, radians
uniform float facet = 0.38;           // how far a blade's own facet bends the clump's normal
uniform float rim = 0.55;             // the sunlit silhouette's rim of light
uniform float glow = 0.6;             // the sun shining through the crown
uniform vec3 flower_a : source_color = vec3(0.878, 0.259, 0.561);    // a flowering shrub's blooms (CUSTOM3.w 1): bougainvillea
uniform vec3 flower_b : source_color = vec3(1.0, 0.965, 0.91);        // and its fewer second ones (CUSTOM3.w 2)

const float S1 = 0.49773;
const float S2 = 0.84;      // the reference's 0.955, lowered: the blades' facets spread the light band
// the season (fol_season): when clusters unfold, turn and drop, each on its own order
const float FLUSH = 0.25;
const float YOUNG_SIZE = 0.4;
const float YOUNG_REACH = 0.3;
const float YOUNG_PALE = 0.55;
const float PALE_LIGHT = 0.3;
const float TURN_FROM = 0.45;
const float TURN_SPAN = 0.3;
const float DROP_AFTER = 0.19;
const float CHANGE = 0.05;

varying vec3 v_b0;
varying vec3 v_b1;
varying vec3 v_b2;
varying vec3 v_mul;         // gradient x AO x tint and tone
varying vec3 v_nw;          // the lighting normal: the clump's, bent by the blade's facet (world)
varying vec3 v_wp;
varying vec3 v_nv;          // and in view space

vec3 rot(vec3 v, vec3 axis, float a) {
	return v * cos(a) + cross(axis, v) * sin(a) + axis * dot(axis, v) * (1.0 - cos(a));
}

void vertex() {
	float order = CUSTOM0.w;
	float unfold_at = order * (FLUSH - CHANGE);
	float turn_at = TURN_FROM + order * TURN_SPAN;
	float unfolded = smoothstep(unfold_at, unfold_at + CHANGE, fol_season);
	float turned = smoothstep(turn_at, turn_at + CHANGE, fol_season);
	float dropped = smoothstep(turn_at + DROP_AFTER, turn_at + DROP_AFTER + CHANGE, fol_season);
	float size = mix(YOUNG_SIZE, 1.0, unfolded) * (1.0 - dropped);
	float out_k = mix(YOUNG_REACH, 1.0, unfolded);

	vec3 centre = CUSTOM0.xyz;
	vec3 hang = CUSTOM1.xyz;
	vec3 wc = (MODEL_MATRIX * vec4(centre, 1.0)).xyz;
	// the cluster rocks round its own centre, harder in a gust
	float t = TIME * fol_wind.z * 6.0 + fol_hash(centre * 13.7) * TAU;
	float gust = fol_noise(wc * fol_wind.w - fol_downwind() * TIME * fol_wind.z) + 1.0;
	float k = flutter * gust * (1.0 + fol_wind_extra.y);
	vec3 n = NORMAL;
	vec3 a1 = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
	vec3 a2 = cross(n, a1);
	float r1 = sin(t) * k;
	float r2 = sin(t * 1.3 + 1.7) * k;
	vec3 off = rot(rot(VERTEX - centre, a1, r1), a2, r2);
	vec3 fn = rot(rot(CUSTOM3.xyz, a1, r1), a2, r2);
	// sits close on its twig while young, moving out as it unfolds; shrinks to nothing as it drops
	float whole = floor(CUSTOM2.w / 1024.0);
	float flex = whole / 1023.0;
	float phase = (CUSTOM2.w - whole * 1024.0) / 1023.0 * TAU;
	VERTEX = mix(hang, centre, out_k) + off * size
		+ fol_to_model(MODEL_MATRIX, fol_sway(wc, CUSTOM1.w, flex, phase));
	// drawn into the sun's shadow map (its projection is orthographic): pushed a little away from the sun, so a
	// blade never shadows itself in stripes (acne) where it lies almost along the light
	if (PROJECTION_MATRIX[3][3] > 0.5) VERTEX += fol_to_model(MODEL_MATRIX, -fol_sun_dir * 0.18);

	// young clusters are paler; turning ones take the turned colours
	vec3 sc = fol_lin(shadow_col), mc = fol_lin(mid_col), lc = fol_lin(light_col);
	vec3 pale = mix(lc, vec3(1.0), PALE_LIGHT);
	v_b0 = mix(mix(mix(sc, pale, YOUNG_PALE), sc, unfolded), fol_lin(turned_shadow), turned);
	v_b1 = mix(mix(mix(mc, pale, YOUNG_PALE), mc, unfolded), fol_lin(turned_mid), turned);
	v_b2 = mix(mix(mix(lc, pale, YOUNG_PALE), lc, unfolded), fol_lin(turned_light), turned);
	// a bloom: a ramp of its own from the flower colour, deeper and cooler in shadow, paler in the light
	if (CUSTOM3.w > 0.5) {
		vec3 fc = fol_lin(CUSTOM3.w > 1.5 ? flower_b : flower_a);
		v_b0 = mix(fc * vec3(0.55, 0.45, 0.62), fol_lin(turned_shadow), turned);
		v_b1 = mix(fc, fol_lin(turned_mid), turned);
		v_b2 = mix(mix(fc, vec3(1.0), 0.35), fol_lin(turned_light), turned);
	}

	// the crown's side away from the sun falls dark; buried clusters darker, open ones brighter
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 side = mat3(MODEL_MATRIX) * CUSTOM2.xyz / scale;
	float gradient = smoothstep(0.0, 1.0, (clamp(dot(side, fol_sun_dir), -1.0, 1.0) + 1.0) * 0.75);
	float ao_term = min(pow(COLOR.a, 2.7) * 7.6, 1.0) * 1.45;
	v_mul = COLOR.rgb * mix(1.0, gradient, shadow_side) * mix(1.0, ao_term, ao);
	v_nw = normalize(mat3(MODEL_MATRIX) * normalize(mix(n, fn, facet)));
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nv = normalize((VIEW_MATRIX * vec4(v_nw, 0.0)).xyz);
}

void fragment() {
	if (fol_occludes(v_wp, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	NORMAL = v_nv;          // the same on both faces of a blade
	ALBEDO = vec3(1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float ndl = max(dot(NORMAL, LIGHT), 0.0);
		vec3 c = fol_cel(fol_lit(v_nw, ndl, ATTENUATION), v_b0, v_b1, v_b2, S1, S2) * v_mul;
		// the sunlit silhouette catches a rim of the light colour, in one hard step
		float edge = 1.0 - max(dot(NORMAL, VIEW), 0.0);
		float r = step(0.6, edge) * step(0.3, ndl) * ATTENUATION;
		c = mix(c, v_b2 * 1.12, r * rim);
		// looking towards the sun through the crown: the leaves glow, warm, in one hard step
		float through = step(0.6, pow(max(dot(-VIEW, LIGHT), 0.0), 2.0)) * (1.0 - step(0.45, ndl));
		c = mix(c, v_b2 * vec3(1.1, 1.12, 0.82), through * glow);
		DIFFUSE_LIGHT += fol_emit(c, v_wp, INV_VIEW_MATRIX[3].xyz);
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * v_b1 * v_mul * 0.25;
	}
}
