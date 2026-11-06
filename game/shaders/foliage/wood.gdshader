// Tree wood (TreeWood): smooth-shaded tubes through the three-band bark ramp, swaying with the wind.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;

#include "res://shaders/foliage/foliage.gdshaderinc"

uniform vec3 shadow_col : source_color = vec3(0.514, 0.447, 0.510);   // spring: #837282
uniform vec3 mid_col : source_color = vec3(0.541, 0.475, 0.416);      // #8a796a
uniform vec3 light_col : source_color = vec3(0.706, 0.627, 0.533);    // #b4a088

varying vec3 v_nw;
varying vec3 v_wp;

uniform float near_cut = 0.0;       // a far copy, drawn in one batch with the rest: a tree nearer than this has its close copy instead

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += fol_to_model(MODEL_MATRIX, fol_sway(w, CUSTOM0.z, CUSTOM0.x, CUSTOM0.y));
	v_nw = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// a far copy of a tree the close copy stands in for: folded to a point, so it costs no pixels at all (not drawn, then thrown away)
	if (near_cut > 0.0 && distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD) < near_cut) VERTEX = vec3(0.0);
}

void fragment() {
	if (fol_occludes(v_wp, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	ALBEDO = vec3(1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lit = fol_lit(normalize(v_nw), max(dot(NORMAL, LIGHT), 0.0), ATTENUATION);
		DIFFUSE_LIGHT += fol_emit(fol_cel(lit, fol_lin(shadow_col), fol_lin(mid_col), fol_lin(light_col), 0.497, 1.0), v_wp, INV_VIEW_MATRIX[3].xyz);
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * fol_lin(mid_col) * 0.25;
	}
}
