// Rocks in the foliage's painted look: faceted stone through the three-band ramp, a soft lavender grey
// matching the ground's rock, a little lighter on top-facing faces and cooler at the waterline. No texture,
// no moss. Replaces shaders/vh/rock.gdshader (vertex COLOR.r: the mesh's own AO, kept).
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 base : source_color = vec3(0.725, 0.702, 0.792);   // #b9b3ca
uniform vec3 top : source_color = vec3(0.835, 0.82, 0.871);     // #d5d1de

varying vec3 v_wp;
varying vec3 v_n;
varying vec3 v_c;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float water = textureLod(field_tex, (v_wp.xz - map_rect.xy) / map_rect.zw, 0.0).b;
	vec3 c = mix(fol_lin(base), fol_lin(top), step(0.75, v_n.y));
	c *= mix(0.8, 1.0, COLOR.r);
	v_c = mix(c * vec3(0.7, 0.8, 0.86), c, step(water + 0.15, v_wp.y));
}

void fragment() {
	vh_clip(v_wp, CAMERA_POSITION_WORLD);
	ALBEDO = vec3(1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 n = normalize(v_n);
		vec3 lit = fol_lit(n, max(dot(NORMAL, LIGHT), 0.0), ATTENUATION);
		DIFFUSE_LIGHT += fol_emit(fol_cel(lit, v_c * 0.6, v_c, v_c * 1.12, 0.497, 0.955), v_wp, INV_VIEW_MATRIX[3].xyz);
	}
}
