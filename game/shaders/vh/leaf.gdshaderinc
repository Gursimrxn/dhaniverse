// shaderlib.ts createLeafMaterial: alpha-tested canvas leaf atlas x vertex AO tint, wind sway + flutter,
// back-lit translucency, authored (spherical) normals kept on back faces, three.js GGX direct light.
// With the realistic atlases (tools/gen_foliage.py, normal_k > 0) every leaf on a card also turns its own
// way in a normal map, so the sun picks leaves out one by one and glints off the waxy ones; light through
// the blade follows the leaf's own thinness (normal map alpha) and comes out a deeper, warmer green; and
// every tree takes a slightly different green (tint_var).
// With FIELD defined the instances come from the GPU field lattice (ferns on the forest floor).
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"
#ifdef FIELD
#include "res://shaders/field.gdshaderinc"
#endif

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_k = 0.0;     // strength of the per-leaf normals (0: the reference's atlases, no map)
uniform float tint_var = 0.0;     // tree-to-tree colour variation
uniform float transl = 0.6;
uniform float rough = 0.68;
uniform float alpha_test = 0.42;
uniform bool lod_tree = false;    // a tree's mesh: hands over to its impostor past vh_tree_lod
uniform float lod_texel = 0.05;   // its impostor's texel size (m) at scale 1 (not instance data: the
                                  // Compatibility light pass does not read MultiMesh custom data)

varying vec3 wpos;
varying vec3 wn;
varying float tree_h;             // the tree's own hash (0..1)
varying float leaf_tr;            // translucency here (light through the blade)
varying vec3 leaf_glow;           // colour of that light, relative to the albedo
varying float lod_f;              // how far this tree has handed over to its impostor
varying vec4 fogv;                // aerial perspective, per vertex

void vertex() {
#ifdef FIELD
	vec3 hs;
	vec4 fp = field_place(MODEL_MATRIX[3].xyz, NODE_POSITION_WORLD, hs);
	mat3 rot = field_yaw(hs.x * TAU);
	VERTEX = rot * VERTEX * fp.w;
	NORMAL = rot * NORMAL;
	mat4 wm = MODEL_MATRIX;
	wm[3] = vec4(fp.xyz, 1.0);
	VERTEX += vh_wind_offset(wm, VERTEX, UV2, true) * fp.w;
	VERTEX += fp.xyz - MODEL_MATRIX[3].xyz;
	tree_h = hs.y;
	lod_f = 0.0;
#else
	lod_f = lod_tree ? vh_tree_fade(MODEL_MATRIX[3].xyz, lod_texel * length(MODEL_MATRIX[1].xyz)) : 0.0;
	if (lod_f >= 1.0) VERTEX = vec3(0.0);       // handed over to the impostor: collapse, skip the rest
	else VERTEX += vh_wind_offset(MODEL_MATRIX, VERTEX, UV2, true);
	tree_h = vh_hash12(floor(MODEL_MATRIX[3].xz * 0.73) + 0.5);
#endif
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fogv = vh_fog(wpos, CAMERA_POSITION_WORLD);
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	if (lod_f > 0.0 && vh_ign(FRAGCOORD.xy) < lod_f) discard;
	vec4 t = texture(leaf_tex, UV);
	vec3 alb = vh_lin(t.rgb) * COLOR.rgb;
	// tree to tree: a fresher yellow-green or a deeper green, a little lighter or darker
	vec3 tint = mix(vec3(1.08, 1.05, 0.8), vec3(0.9, 0.98, 0.93), tree_h) * (0.9 + 0.2 * fract(tree_h * 7.31));
	alb *= mix(vec3(1.0), tint, tint_var);
	ALBEDO = alb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_test;
	ALPHA_ANTIALIASING_EDGE = alpha_test;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_tex, 0));
	ROUGHNESS = rough;
	vec3 n = normalize(wn);
	leaf_tr = transl;
	if (normal_k > 0.0) {
		// each leaf's own normal, in the card's frame (three.js perturbNormal2Arb, from the derivatives)
		vec4 m = texture(leaf_n, UV);
		vec3 mn = m.xyz * 2.0 - 1.0;
		mn.xy *= normal_k;
		vec3 q0 = dFdx(wpos), q1 = dFdy(wpos);
		vec2 st0 = dFdx(UV), st1 = dFdy(UV);
		vec3 q1perp = cross(q1, n), q0perp = cross(n, q0);
		vec3 T = q1perp * st0.x + q0perp * st1.x;
		vec3 B = q1perp * st0.y + q0perp * st1.y;
		float det = max(dot(T, T), dot(B, B));
		float sc = det == 0.0 ? 0.0 : inversesqrt(det);
		n = normalize(T * (mn.x * sc) + B * (mn.y * sc) + n * mn.z);
		// the sun's side of a card shows the leaf as authored, the far side its mirror image
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz) * (FRONT_FACING ? 1.0 : -1.0);
		leaf_tr = transl * (0.35 + 0.9 * m.a);
	}
	// light through a leaf comes out a deeper, warmer green than the leaf seen from the lit side
	leaf_glow = mix(vec3(1.0), clamp(alb / max(dot(alb, vec3(0.3333)), 1e-4), vec3(0.0), vec3(2.5)) * vec3(1.05, 1.0, 0.7), 0.65);
	vec3 em = ALBEDO * vh_indirect(n);
	em += vh_ibl_spec(NORMAL, VIEW, rough, vec3(0.04), INV_VIEW_MATRIX);
	em += vh_lamps(wpos, n, CAMERA_POSITION_WORLD, rough, ALBEDO, 0.5);
	vh_fog_a = vh_finish_v(fogv, wpos, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d + vh_transl(VIEW, LIGHT, LIGHT_COLOR, att, leaf_tr) * leaf_glow, s, vh_alb, SPECULAR_LIGHT);
}
