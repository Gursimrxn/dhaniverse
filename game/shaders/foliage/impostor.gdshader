// Far cel-shaded trees (scripts/foliage): one camera-facing card per tree showing its octahedral atlas
// (scripts/vh/vh_impostor.gd, baked by impostor_bake.gdshader) from the nearest four of 8 x 8 directions,
// lit through the same leaf ramp as the meshes with the baked clump normals. Fades in past `near` metres,
// where the meshes end. In the shadow passes the card turns to the light and casts the tree's silhouette.
// The frame blending and shadow handling follow shaders/vh/impostor.gdshader.
shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform sampler2D albedo_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform float frame_px = 128.0;
uniform float radius = 4.0;
uniform float center_y = 3.0;
uniform float near = 120.0;          // the meshes end here; the card fades in over the next 8 m
uniform float shadow_far = 115.0;
uniform vec3 shadow_col : source_color;
uniform vec3 mid_col : source_color;
uniform vec3 light_col : source_color;
uniform vec3 turned_shadow : source_color;
uniform vec3 turned_mid : source_color;
uniform vec3 turned_light : source_color;

varying vec3 wpos;
varying vec4 fr;
varying float fade;
varying vec3 ax;
varying vec3 az;
varying float shadow_pass;

void vertex() {
	vec3 P = MODEL_MATRIX[3].xyz;
	mat3 B = mat3(MODEL_MATRIX);
	float s = length(B[1]);
	mat3 R = B / s;
	vec3 C = P + vec3(0.0, center_y * s, 0.0);
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	vec3 v = ortho ? normalize(INV_VIEW_MATRIX[2].xyz) : normalize(CAMERA_POSITION_WORLD - C);
	vec3 right = cross(vec3(0.0, 1.0, 0.0), v);
	float rl = length(right);
	right = rl > 1e-4 ? right / rl : vec3(1.0, 0.0, 0.0);
	vec3 up = cross(v, right);
	vec3 d = transpose(R) * v;
	d.y = max(d.y, 0.0);
	d = normalize(d + vec3(0.0, 1e-4, 0.0));
	vec2 g = vh_hemioct(d) * (frames - 1.0);
	vec2 g0 = min(floor(g), vec2(frames - 2.0));
	fr = vec4(g0, g - g0);
	float dist = distance(P, vh_eye);
	fade = smoothstep(near, near + 8.0, dist);
	shadow_pass = ortho ? 1.0 : 0.0;
	if (ortho) fade = dist > shadow_far ? 0.0 : 1.0;
	ax = R[0];
	az = R[2];
	vec2 c = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	vec3 wp = C + (right * c.x + up * c.y) * (radius * s);
	VERTEX = fade > 0.0 ? wp : P;
	wpos = VERTEX;
}

void fragment() {
	if (vh_ign(FRAGCOORD.xy) >= fade) discard;
	bool sh = shadow_pass > 0.5;
	vec2 q = UV;
	vec2 px = q * frame_px;
	float lod = clamp(0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))), 0.0, 4.0);
	vec2 f = fr.zw;
	vec4 w = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	vec2 u0 = (fr.xy + q) / frames;
	vec2 du = vec2(1.0 / frames, 0.0);
	vec4 A;
	float a;
	if (sh) {
		A = textureLod(albedo_atlas, (floor(fr.xy + f + 0.5) + q) / frames, 1.5);
		a = A.a * 1.25;
	} else {
		A = textureLod(albedo_atlas, u0, lod) * w.x + textureLod(albedo_atlas, u0 + du.xy, lod) * w.y
			+ textureLod(albedo_atlas, u0 + du.yx, lod) * w.z + textureLod(albedo_atlas, u0 + du.xx, lod) * w.w;
		a = A.a * (1.0 + lod * 0.22);
	}
	// bare in winter: the leaves dropped, the card thins away
	a *= 1.0 - smoothstep(0.66, 0.95, fol_season);
	if (a < 0.5) discard;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 outc = vec3(0.0);
	if (!sh) {
		float nlod = max(lod - 1.0, 0.0);
		vec4 Nm = textureLod(normal_atlas, u0, nlod) * w.x + textureLod(normal_atlas, u0 + du.xy, nlod) * w.y
			+ textureLod(normal_atlas, u0 + du.yx, nlod) * w.z + textureLod(normal_atlas, u0 + du.xx, nlod) * w.w;
		vec3 nl = clamp(Nm.rgb / max(Nm.a, 1e-3), 0.0, 1.0) * 2.0 - 1.0;
		vec3 n = normalize(ax * nl.x + vec3(0.0, nl.y, 0.0) + az * nl.z);
		// the baked colour over the palette's mid is each card's own tint and AO; the band comes from the light
		vec3 alb = vh_lin(clamp(A.rgb / max(A.a, 1e-3), 0.0, 1.0)) * 1.5;
		vec3 mid = fol_lin(mid_col);
		float tf = smoothstep(0.45, 0.75, fol_season);
		vec3 c0 = mix(fol_lin(shadow_col), fol_lin(turned_shadow), tf);
		vec3 c1 = mix(mid, fol_lin(turned_mid), tf);
		vec3 c2 = mix(fol_lin(light_col), fol_lin(turned_light), tf);
		vec3 lit = fol_lit(n, max(dot(n, fol_sun_dir), 0.0), 1.0);
		vec3 col = alb / max(mid, vec3(1e-3)) * fol_cel(lit, c0, c1, c2, 0.49773, 0.95455) * FOL_WORLD_GAIN;
		outc = vh_fogged(col, wpos, CAMERA_POSITION_WORLD, 0.0);
	}
	ALBEDO = outc;
}
