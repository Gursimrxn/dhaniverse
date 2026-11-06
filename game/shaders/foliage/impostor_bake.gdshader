// Bakes a cel-shaded tree (scripts/foliage) into its impostor atlas (scripts/vh/vh_impostor.gd): pass 0 the
// palette's mid colour times each card's clump tint and AO (linear / 1.5, sRGB encoded), pass 1 the clump's
// normal in the tree's own frame (n * 0.5 + 0.5). shaders/foliage/impostor.gdshader lights them.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform sampler2D leaf_tex : filter_linear_mipmap, repeat_disable;
uniform int pass = 0;
uniform bool is_leaf = true;
uniform bool cutout = false;          // leaves cut out of leaf_tex (the geometric blades need none)
uniform vec3 mid_col : source_color;

varying vec3 lnrm;
varying vec4 vcol;

void vertex() {
	lnrm = NORMAL;
	vcol = COLOR;
}

void fragment() {
	if (cutout && texture(leaf_tex, UV).r < 0.5) discard;
	vec3 c = fol_lin(mid_col);
	if (is_leaf) c *= vcol.rgb * mix(1.0, min(pow(vcol.a, 2.7) * 7.6, 1.0) * 1.45, 0.54);
	c = clamp(c / 1.5, 0.0, 1.0);
	c = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
	ALBEDO = vh_raw(pass == 0 ? c : normalize(lnrm) * 0.5 + 0.5);
}
