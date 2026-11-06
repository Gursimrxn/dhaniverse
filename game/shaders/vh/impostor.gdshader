shader_type spatial;
// Tree impostors (scripts/vh/vh_impostor.gd): every tree past vh_tree_lod is a single camera-facing card
// that shows the tree's real high-detail mesh as baked from the nearest four of 8 x 8 directions over the
// upper hemisphere (octahedral atlas), blended by how close the view is to each. The baked normals carry
// every leaf's own tilt, so the card is lit like the mesh: sun with back-lit translucency, the cloud
// shade, the sky light, aerial perspective. Unshaded (lit here) so it costs one pass, not two.
// In the shadow passes the card turns to the light and its silhouette is the tree as the sun sees it.
// Hands over from the mesh with a dithered cross-fade (vh_tree_fade, the same in leaf / bark shaders), each tree
// where its atlas texels (INSTANCE_CUSTOM.x metres) get as big as a couple of screen pixels.
render_mode unshaded, cull_disabled, world_vertex_coords;
#include "res://shaders/vh/vh.gdshaderinc"

uniform sampler2D albedo_atlas : filter_linear_mipmap, repeat_disable;   // sRGB, premultiplied by coverage
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;   // tree-space normal, premultiplied (half size)
uniform float frames = 8.0;
uniform float frame_px = 128.0;
uniform float radius = 4.0;          // the tree's bounding sphere (m, at scale 1)
uniform float center_y = 3.0;        // its centre above the tree's foot
uniform float far_cut = 100000.0;    // gone beyond this (m), faded over the last 15 %
uniform float transl = 0.6;
uniform float tint_var = 1.0;
uniform float shadow_far = 115.0;   // cards past this cast no shadow (the sun's shadows end before it)
uniform float sun_k = 0.8;           // the crown's own shade on the sunlight (the meshes get it from the shadow map)

varying vec3 wpos;
varying vec4 fr;                     // nearest frame below (i, j) and the blend towards the next ones
varying float fade;
varying float tree_h;
varying vec3 ax;                     // the tree's own x and z axes (world), for its normals
varying vec3 az;
varying vec4 fogv;                   // aerial perspective, per corner
varying float shadow_pass;           // 1 while drawn into the sun's shadow map

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
	// the view in the tree's frame picks the frames (below the crown's middle: the horizon ring)
	vec3 d = transpose(R) * v;
	d.y = max(d.y, 0.0);
	d = normalize(d + vec3(0.0, 1e-4, 0.0));
	vec2 g = vh_hemioct(d) * (frames - 1.0);
	vec2 g0 = min(floor(g), vec2(frames - 2.0));
	fr = vec4(g0, g - g0);
	float dist = distance(P, vh_eye);
	fade = vh_tree_fade(P, INSTANCE_CUSTOM.x) * (1.0 - smoothstep(far_cut * 0.85, far_cut, dist));
	shadow_pass = ortho ? 1.0 : 0.0;
	if (ortho && dist > shadow_far) fade = 0.0;
	tree_h = vh_hash12(floor(P.xz * 0.73) + 0.5);
	ax = R[0];
	az = R[2];
	vec2 c = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	// the crown sways a little with the wind, the foot stays put
	float ph = dot(P.xz, vec2(0.13, 0.17));
	float sway = (sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 1.73 + ph * 1.3) * 0.25) * 0.012 * radius * s;
	vec3 wind = vec3(vh_wind.x, 0.0, vh_wind.y) * sway * max(c.y + 0.4, 0.0);
	vec3 wp = C + (right * c.x + up * c.y) * (radius * s) + wind;
	VERTEX = fade > 0.0 ? wp : P;
	wpos = VERTEX;
	fogv = vh_fog(wpos, CAMERA_POSITION_WORLD);
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
		// the shadow map: the silhouette from the nearest view, one coarse read
		A = textureLod(albedo_atlas, (floor(fr.xy + f + 0.5) + q) / frames, 1.5);
		a = A.a * 1.25;
	} else {
		// the same spot on the four nearest frames; mips kept from mixing in the neighbouring frames
		A = textureLod(albedo_atlas, u0, lod) * w.x + textureLod(albedo_atlas, u0 + du.xy, lod) * w.y
			+ textureLod(albedo_atlas, u0 + du.yx, lod) * w.z + textureLod(albedo_atlas, u0 + du.xx, lod) * w.w;
		// coverage thins out down the mips (holes average in): give it back so far crowns stay full
		a = A.a * (1.0 + lod * 0.22);
	}
	if (a < 0.5) discard;          // most of the card: out before the normals are read
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 outc = vec3(0.0);
	if (!sh) {
		float nlod = max(lod - 1.0, 0.0);
		vec4 Nm = textureLod(normal_atlas, u0, nlod) * w.x + textureLod(normal_atlas, u0 + du.xy, nlod) * w.y
			+ textureLod(normal_atlas, u0 + du.yx, nlod) * w.z + textureLod(normal_atlas, u0 + du.xx, nlod) * w.w;
		vec3 alb = vh_lin(clamp(A.rgb / max(A.a, 1e-3), 0.0, 1.0));
		vec3 tint = mix(vec3(1.08, 1.05, 0.8), vec3(0.9, 0.98, 0.93), tree_h) * (0.9 + 0.2 * fract(tree_h * 7.31));
		alb *= mix(vec3(1.0), tint, tint_var);
		vec3 nl = clamp(Nm.rgb / max(Nm.a, 1e-3), 0.0, 1.0) * 2.0 - 1.0;
		vec3 n = normalize(ax * nl.x + vec3(0.0, nl.y, 0.0) + az * nl.z);
		vec3 L = normalize(vh_light);
		vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
		// the crown's own shade, which the meshes get from the shadow map: leaves turned from the sun are in it
		float ndl = dot(n, L);
		float att = vh_cloud_sh(wpos) * sun_k * smoothstep(-0.15, 0.55, ndl);
		vec3 glow = mix(vec3(1.0), clamp(alb / max(dot(alb, vec3(0.3333)), 1e-4), vec3(0.0), vec3(2.5)) * vec3(1.05, 1.0, 0.7), 0.65);
		vec3 light = vh_sun_light * (att * max(ndl, 0.0) / PI) + vh_transl(V, L, vh_sun_light, att, transl) * glow;
		vec3 col = alb * (light + vh_indirect(n));
		float of = vh_outside(wpos);
		outc = vh_raw(mix(mix(col, vec3(0.003, 0.004, 0.006), of), fogv.rgb, fogv.a * (1.0 - of)));
	}
	ALBEDO = outc;
}
