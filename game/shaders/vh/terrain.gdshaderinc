render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// terrain.ts createTerrainMaterial on GPU-displaced tiles: splat (grass / dirt / rock / riverbed sand)
// from slope, height above water and noise; triplanar rock, ground detail, wet banks, underwater
// caustics + absorption. Our lanes and trails use the reference's paving (triplanar concrete).
uniform sampler2D field_tex : filter_linear, repeat_disable;   // r height, g water sd, b water level
uniform sampler2D paved_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paved_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 texel = vec2(0.0025, 0.0025);
uniform float cell = 2.0;

uniform sampler2D t_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rock_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_ground : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_ground_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D t_concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_concrete_n : filter_linear_mipmap_anisotropic, repeat_enable;
// lawn seen from above (tools/gen_foliage.py turf_*), laid over the grass at two scales; turf_on = 0 without it
uniform sampler2D t_turf : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_turf_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float turf_on = 0.0;
uniform vec3 turf_mean = vec3(0.0817, 0.1379, 0.0241);   // its average linear colour

uniform vec3 grass_a : source_color = vec3(0.275, 0.353, 0.133);   // #465a22
uniform vec3 grass_b : source_color = vec3(0.384, 0.455, 0.173);   // #62742c
uniform vec3 grass_dry : source_color = vec3(0.522, 0.478, 0.275); // #857a46
uniform vec3 dirt : source_color = vec3(0.361, 0.29, 0.22);        // #5c4a38
uniform vec3 sand : source_color = vec3(0.424, 0.376, 0.306);      // #6c604e
uniform vec3 rock_tint : source_color = vec3(0.886, 0.863, 0.831); // #e2dcd4
uniform vec3 paving : source_color = vec3(0.639, 0.62, 0.584);     // #a39e95

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 splat;
varying float level;
varying vec4 fogv;      // aerial perspective, per vertex (2 m apart near, 8 m on the far tiles)

float hgt(vec2 uv) { return textureLod(field_tex, uv, 0.0).r; }
float snoise(vec2 p) { return vh_vnoise(p) * 2.0 - 1.0; }

void vertex() {
#ifdef CPU_MESH
	// heights, normals and splat come with the mesh (terrain.ts buildMeshes)
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	splat = COLOR;
	vec2 cuv = clamp((wpos.xz - map_rect.xy) / map_rect.zw, vec2(0.0), vec2(1.0));
	level = textureLod(field_tex, cuv, 0.0).b;
#else
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (w.xz - map_rect.xy) / map_rect.zw;
	vec4 f = textureLod(field_tex, uv, 0.0);
	float hl = hgt(uv - vec2(texel.x, 0.0)), hr = hgt(uv + vec2(texel.x, 0.0));
	float hu = hgt(uv - vec2(0.0, texel.y)), hd = hgt(uv + vec2(0.0, texel.y));
	VERTEX.y = f.r - UV2.y * 2.5;
	wnrm = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	NORMAL = wnrm;
	wpos = vec3(w.x, f.r, w.z);
	level = f.b;
	// computeSplat: grass, dirt, rock, sand/riverbed
	float slope = 1.0 - wnrm.y;
	float above = f.r - f.b;
	float n1 = snoise(w.xz * 0.07 + vec2(5.2, -1.3));
	float rock = smoothstep(0.17, 0.32, slope + n1 * 0.05);
	float sandw = 1.0 - smoothstep(0.08, 0.7 + n1 * 0.2, above);
	float dirtw = smoothstep(0.45, 0.8, snoise(w.xz * 0.045 + vec2(11.0, -4.0)) * 0.5 + 0.5) * 0.5;
	dirtw = max(dirtw, smoothstep(0.1, 0.18, slope) * 0.65);
	splat = vec4((1.0 - rock) * (1.0 - sandw) * (1.0 - dirtw), (1.0 - rock) * (1.0 - sandw) * dirtw, rock, (1.0 - rock) * sandw);
#endif
	fogv = vh_fog(wpos, CAMERA_POSITION_WORLD);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 tw = wpos;
	vec3 tn = normalize(wnrm);
	vec3 tb = vh_tri_w(tn);
	const float RS = 0.16;
	vec3 rA = vh_lin(vh_tri_albedo(t_rock, tw, tb, RS));
	vec4 gD = texture(t_ground, tw.xz * 0.33);
	vec4 nz = texture(t_noise, tw.xz * 0.011);
	vec4 nz2 = texture(t_noise, tw.xz * 0.043 + vec2(0.37, 0.11));
	vec4 sp = splat;
	float rh = dot(rA, vec3(0.333));
	sp.z = clamp(sp.z * (0.6 + rh * 3.0) - 0.08, 0.0, 1.0);
	sp /= max(sp.x + sp.y + sp.z + sp.w, 1e-3);
	vec3 gcol = mix(vh_lin(grass_a), vh_lin(grass_b), smoothstep(0.3, 0.72, nz.r));
	gcol = mix(gcol, vh_lin(grass_dry), smoothstep(0.55, 0.82, nz2.g) * 0.5);
	vec2 tq = tw.xz * 0.55;
	vec2 tq2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * tw.xz * 0.19 + 0.37;
	vec3 turf = mix(vh_lin(texture(t_turf, tq).rgb), vh_lin(texture(t_turf, tq2).rgb), 0.35);
	gcol *= mix(vec3(0.68 + 0.64 * gD.g), clamp(turf / turf_mean, vec3(0.35), vec3(2.2)), turf_on);
	vec3 dcol = vh_lin(dirt) * (0.6 + 0.8 * gD.r);
	vec3 scol = vh_lin(sand) * (0.65 + 0.7 * gD.b);
	vec3 rcol = rA * vh_lin(rock_tint) * (0.85 + 0.3 * nz2.r);
	rcol = mix(rcol, vh_lin(grass_a) * 0.75, smoothstep(0.72, 0.93, tn.y) * smoothstep(0.35, 0.7, nz2.b) * 0.65);
	vec3 tcol = gcol * sp.x + dcol * sp.y + rcol * sp.z + scol * sp.w;
	// paving (lanes, trails): the reference's triplanar concrete paving
	float pv = texture(paved_tex, (tw.xz - paved_rect.xy) / paved_rect.zw).r;
	float pav = smoothstep(0.3, 0.6, pv + (nz2.a - 0.5) * 0.25);
	vec3 pcol = vh_lin(paving) * vh_lin(vh_tri_albedo(t_concrete, tw, tb, 0.32)) * 1.9;
	tcol = mix(tcol, pcol, pav);
	float above = tw.y - level;
	float tWet = (1.0 - smoothstep(0.02, 0.4, above)) * (1.0 - pav);
	tcol *= mix(1.0, 0.52, tWet);
	float under = clamp(-above, 0.0, 4.0);
	float caus = abs(texture(t_noise, tw.xz * 0.21 + TIME * vec2(0.012, 0.02)).a - texture(t_noise, tw.xz * 0.27 - TIME * vec2(0.018, 0.01)).a);
	tcol += vec3(0.55, 0.5, 0.36) * pow(1.0 - smoothstep(0.0, 0.07, caus), 2.0) * 0.05 * smoothstep(0.02, 0.15, under) * (1.0 - smoothstep(0.3, 1.4, under));
	// the bed is lit by sunlight that came down through the water (water.gdshader takes the way back up)
	tcol *= exp(-under * vec3(0.5, 0.36, 0.4) * (1.0 + 1.0 / max(normalize(vh_light).y, 0.3)) * 0.5);
	// normals: triplanar rock + ground detail, flattened where wet; concrete on paving
	vec3 rockN = vh_tri_normal(t_rock_n, tw, tn, tb, RS, 1.0);
	vec3 gn = texture(t_ground_n, tw.xz * 0.33).xyz * 2.0 - 1.0;
	vec3 groundN = normalize(vec3(gn.x * 0.55 + tn.x, tn.y, gn.y * 0.55 + tn.z));
	vec3 tf = texture(t_turf_n, tq).xyz * 2.0 - 1.0;
	vec3 turfN = normalize(vec3(tf.x * 0.45 + tn.x, tn.y, tf.y * 0.45 + tn.z));
	groundN = normalize(mix(groundN, turfN, sp.x * turf_on));   // the lawn's blades, not the pebbles
	vec3 nW = normalize(mix(groundN, rockN, clamp(sp.z * 1.3, 0.0, 1.0)));
	nW = normalize(mix(nW, tn, tWet * 0.6));
	nW = normalize(mix(nW, vh_tri_normal(t_concrete_n, tw, tn, tb, 0.32, 0.6), pav));
	NORMAL = normalize((VIEW_MATRIX * vec4(nW, 0.0)).xyz);
	ALBEDO = tcol;
	ROUGHNESS = mix(mix(0.95, 0.8, pav), 0.3, tWet * 0.9);
	SPECULAR = 0.5;
	vec3 em = tcol * vh_indirect(nW);
	em += vh_ibl_spec(NORMAL, VIEW, ROUGHNESS, vec3(0.04), INV_VIEW_MATRIX);
	em += vh_lamps(tw, nW, CAMERA_POSITION_WORLD, ROUGHNESS, tcol, 0.0);
	vh_fog_a = vh_finish_v(fogv, tw, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	vh_out(d, s, vh_alb, SPECULAR_LIGHT);
}
