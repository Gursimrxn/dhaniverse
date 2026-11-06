// People in the foliage's painted look: the same cel bands, blue-tinted shade and haze as the trees and the
// buildings, a soft rim of sky light so a figure stands off the ground behind it, and (next pass,
// character_ink.gdshader) an ink outline. One flat colour per surface: skin, hair, clothes, set per person.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.8);
uniform float rim = 0.35;            // how much sky light catches the edges

varying vec3 v_wp;
varying vec3 v_nw;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nw = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(v_wp, CAMERA_POSITION_WORLD);
	ALBEDO = vec3(1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 c = fol_lin(albedo);
		vec3 n = normalize(v_nw);
		vec3 lit = fol_lit(n, max(dot(NORMAL, LIGHT), 0.0), ATTENUATION);
		vec3 col = fol_cel(lit, c * 0.6, c, c * 1.08, 0.497, 0.955);
		// a rim of sky on the silhouette, strongest on the shaded side
		float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		col += fol_sky * c * rim * edge * (1.2 - ATTENUATION * 0.6);
		DIFFUSE_LIGHT += fol_emit(col, v_wp, INV_VIEW_MATRIX[3].xyz);
	}
}
