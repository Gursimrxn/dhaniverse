shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// Bakes a tree into its impostor atlas (scripts/vh/vh_impostor.gd): unlit, one pass for the albedo (sRGB
// encoded, the vertex AO and the bark's furrow shade in it) and one for the normal in the tree's own frame
// (n * 0.5 + 0.5), with every leaf turned its own way by the leaf normal map as in leaf.gdshader. The
// atlas is cleared to transparent black, so both come out premultiplied by coverage.
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ntex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform int pass = 0;              // 0 albedo, 1 normal
uniform bool is_leaf = true;
uniform float normal_k = 0.6;      // leaves: per-leaf normal strength (0: no map)
uniform float relief = 0.0;        // bark: furrow shade from the normal map's alpha
uniform float alpha_test = 0.42;

varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

vec3 srgb_enc(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void fragment() {
	vec4 t = texture(tex, UV);
	vec4 m = texture(ntex, UV);
	if (is_leaf && t.a < alpha_test) discard;
	vec3 alb = vh_lin(t.rgb) * COLOR.rgb;
	vec3 n = normalize(lnrm);
	vec3 mn = m.xyz * 2.0 - 1.0;
	if (is_leaf) {
		mn.xy *= normal_k;
	} else {
		mn.xy *= 1.2;
		if (relief > 0.0) alb *= mix(0.6, 1.06, m.a);
	}
	if (!is_leaf || normal_k > 0.0) {
		vec3 q0 = dFdx(lpos), q1 = dFdy(lpos);
		vec2 st0 = dFdx(UV), st1 = dFdy(UV);
		vec3 q1perp = cross(q1, n), q0perp = cross(n, q0);
		vec3 T = q1perp * st0.x + q0perp * st1.x;
		vec3 B = q1perp * st0.y + q0perp * st1.y;
		float det = max(dot(T, T), dot(B, B));
		float sc = det == 0.0 ? 0.0 : inversesqrt(det);
		n = normalize(T * (mn.x * sc) + B * (mn.y * sc) + n * mn.z);
	}
	ALBEDO = vh_raw(pass == 0 ? srgb_enc(alb) : n * 0.5 + 0.5);
}
