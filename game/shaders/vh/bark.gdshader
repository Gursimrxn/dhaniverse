shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// shaderlib.ts createBarkMaterial: furrowed bark map x vertex AO tint, normal map (scale 1.2) applied
// with three.js's derivative tangent frame (perturbNormal2Arb), trunk-to-branch wind sway.
// The generated bark (tools/gen_foliage.py, relief = 1) carries its height in the normal map's alpha:
// the furrows sink into shade, and moss creeps up the foot of the trunk on the side the sun never
// reaches, into the furrows first.
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.2;
uniform float relief = 0.0;
uniform bool lod_tree = false;    // a tree's trunk: hands over to its impostor past vh_tree_lod
uniform float lod_texel = 0.05;   // its impostor's texel size (m) at scale 1
uniform vec2 lod_band = vec2(0.0, 100000.0);   // and is drawn only this far from the eye (detailed / plain trunk)

const vec2 SHADED_SIDE = vec2(-0.64, -0.77);   // away from the midday sun (world.json day: azimuth 140)

varying vec3 wpos;
varying vec3 wn;
varying float foot;               // height up the trunk from its foot (model space)
varying float lod_f;

void vertex() {
	foot = VERTEX.y + 0.3;
	lod_f = lod_tree ? vh_tree_fade(MODEL_MATRIX[3].xyz, lod_texel * length(MODEL_MATRIX[1].xyz)) : 0.0;
	float de = distance(MODEL_MATRIX[3].xyz, vh_eye);
	if (lod_f >= 1.0 || (lod_tree && (de < lod_band.x || de >= lod_band.y))) VERTEX = vec3(0.0);   // not this trunk
	else VERTEX += vh_wind_offset(MODEL_MATRIX, VERTEX, UV2, false);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	if (lod_f > 0.0 && vh_ign(FRAGCOORD.xy) < lod_f) discard;
	vec4 bn = texture(bark_n, UV);
	ALBEDO = vh_lin(texture(bark_tex, UV).rgb) * COLOR.rgb;
	vec3 mapN = bn.xyz * 2.0 - 1.0;
	mapN.xy *= normal_scale;
	float rough = 0.92;
	if (relief > 0.0) {
		ALBEDO *= mix(0.6, 1.06, bn.a);
		vec3 n0 = normalize(wn);
		float side = smoothstep(-0.1, 0.7, dot(normalize(n0.xz + vec2(1e-4)), SHADED_SIDE)) * 0.75 + 0.25 * smoothstep(0.3, 0.9, n0.y);
		float patchy = vh_vnoise(UV * vec2(5.0, 2.5) + 3.7) * 0.7 + vh_vnoise(UV * vec2(17.0, 9.0)) * 0.3;
		float moss = smoothstep(0.25, 0.6, (1.0 - smoothstep(0.2, 2.2, foot)) * side * (1.25 - bn.a) * (0.5 + patchy));
		ALBEDO = mix(ALBEDO, vec3(0.075, 0.13, 0.025) * (0.75 + 0.5 * patchy), moss * 0.75);
		mapN.xy *= 1.0 - 0.6 * moss;      // moss fills the furrows
		rough = mix(0.92, 0.98, moss);
	}
	vec3 q0 = dFdx(VERTEX), q1 = dFdy(VERTEX);
	vec2 st0 = dFdx(UV), st1 = dFdy(UV);
	vec3 N = normalize(NORMAL);
	vec3 q1perp = cross(q1, N), q0perp = cross(N, q0);
	vec3 T = q1perp * st0.x + q0perp * st1.x;
	vec3 B = q1perp * st0.y + q0perp * st1.y;
	float det = max(dot(T, T), dot(B, B));
	float sc = det == 0.0 ? 0.0 : inversesqrt(det);
	NORMAL = normalize(T * (mapN.x * sc) + B * (mapN.y * sc) + mapN.z * N);
	ROUGHNESS = rough;
	vec3 em = ALBEDO * vh_indirect(wn) * (relief > 0.0 ? mix(0.75, 1.0, bn.a) : 1.0);
	em += vh_ibl_spec(NORMAL, VIEW, rough, vec3(0.04), INV_VIEW_MATRIX);
	em += vh_lamps(wpos, wn, CAMERA_POSITION_WORLD, rough, ALBEDO, 0.0);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d, s, vh_alb, SPECULAR_LIGHT);
}
