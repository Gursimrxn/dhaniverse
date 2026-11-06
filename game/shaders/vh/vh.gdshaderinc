// Verdant Horizon look, ported from the three.js reference (atmosphere.ts, shaderlib.ts, water.ts):
// sky gradient + aerial perspective/valley mist, hierarchical wind, back-lit translucency,
// three.js GGX direct light, hemisphere fill, triplanar helpers and the planar-reflection clip.
#include "res://shaders/vh/vh_sky.gdshaderinc"

global uniform vec4 vh_fog_k;      // x aerial density /m, y valley mist density, z mist height falloff, w thinning up high
global uniform vec3 vh_hemi_sky;   // hemisphere fill, linear colour x intensity (evening: #b9b3dc x 0.25)
global uniform vec3 vh_hemi_ground;
global uniform vec4 vh_cloud_shadow;  // x strength, y noise scale /m, z coverage threshold, w drift m/s
global uniform sampler2D cloud_noise;

// aerial perspective + analytically integrated exponential height mist -> FOG = vec4(colour, amount)
vec4 vh_fog(vec3 wp, vec3 cam) {
	vec3 ray = wp - cam;
	float dist = length(ray);
	vec3 rd = ray / max(dist, 1e-4);
	float camY = abs(cam.y - vh_water_y);
	float od = dist * vh_fog_k.x;
	float B = vh_fog_k.z;
	float a = vh_fog_k.y * exp(-B * camY);
	float k = rd.y * B;
	float hf = abs(k) > 1e-4 ? a * (1.0 - exp(-dist * k)) / k : a * dist;
	od += max(hf, 0.0) * smoothstep(30.0, 230.0, dist);
	// the reference only ever looks from eye level; from the overview cameras the mist (dense at water level)
	// and the sun-side haze would white out the whole valley, so both thin as the camera climbs
	od *= 1.0 - vh_fog_k.w * smoothstep(15.0, 120.0, camY);
	float f = min(1.0 - exp(-od), 0.982);
	return vec4(vh_sky(vec3(rd.x, max(rd.y, 0.0) * 0.85, rd.z)), f);
}

// 1 where the outside world is swallowed by the interior blackout (walking into a building)
float vh_outside(vec3 wp) {
	vec2 q = abs(wp.xz - focus_box.xy) - focus_box.zw;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	return focus_amount * smoothstep(-0.5, 1.5, d);
}

// Shared tail of every lit surface: interior blackout + aerial perspective. The fog is mixed in here, in
// linear light (Godot mixes FOG inside its sRGB round trip, which washes the haze out), and the emission
// is prepared for that round trip (vh_raw). FOG is left clear; the fog amount is returned for vh_fog_a,
// so light() fades the sun the same way.
float vh_finish(vec3 wp, vec3 cam, inout vec3 albedo, inout vec3 emission, out vec4 fog) {
	float of = vh_outside(wp);
	albedo = mix(albedo, vec3(0.02, 0.035, 0.05), of);
	vec4 f = vh_fog(wp, cam);
	f.a *= 1.0 - of;
	emission = vh_raw(mix(emission * (1.0 - of), f.rgb, f.a));
	fog = vec4(0.0);
	return f.a;
}

// vh_finish with the fog worked out per vertex (vh_fog in vertex(), passed on): for the foliage, grass and
// terrain, whose fog is smooth across a vertex or two and whose fragments are drawn several deep.
float vh_finish_v(vec4 f, vec3 wp, inout vec3 albedo, inout vec3 emission, out vec4 fog) {
	float of = vh_outside(wp);
	albedo = mix(albedo, vec3(0.02, 0.035, 0.05), of);
	f.a *= 1.0 - of;
	emission = vh_raw(mix(emission * (1.0 - of), f.rgb, f.a));
	fog = vec4(0.0);
	return f.a;
}

// The same for unshaded colours: fog mixed in linear light, ready for Godot's round trip.
vec3 vh_fogged(vec3 c, vec3 wp, vec3 cam, float extra) {
	vec4 f = vh_fog(wp, cam);
	return vh_raw(mix(c, f.rgb, max(f.a, extra)));
}

void vh_clip(vec3 wp, vec3 cam) {
	if (cam.y < vh_refl_y && wp.y < vh_refl_y) discard;
}

// hierarchical sway (trunk -> branches) plus leaf flutter; weight in aw.x, phase in aw.y
vec3 vh_wind_offset(mat4 wM, vec3 pos, vec2 aw, bool flutter) {
	vec3 tPos = wM[3].xyz;
	float tph = dot(tPos.xz, vec2(0.13, 0.17));
	float sway = sin(TIME * 0.9 + tph) * 0.6 + sin(TIME * 1.73 + tph * 1.3) * 0.25;
	float gust = 0.55 + 0.45 * sin(TIME * 0.31 + tPos.x * 0.021 + tPos.z * 0.013);
	vec3 wDirL = normalize(transpose(mat3(wM)) * vec3(vh_wind.x, 0.0, vh_wind.y));
	float ww = aw.x;
	vec3 woff = wDirL * (sway * 0.6 + gust) * ww * ww * 0.15 * length(vh_wind);
	if (flutter) {
		float fl = sin(TIME * 5.3 + aw.y * 6.2831 + pos.y * 1.7) * 0.028 * ww;
		woff += vec3(fl, fl * 0.7, -fl * 0.8);
	}
	return woff;
}

// three.js direct light: Lambert diffuse, GGX specular (F_Schlick, V_GGX_SmithCorrelated, D_GGX).
// LIGHT_COLOR already equals three's directLight.color (light energy = intensity / PI).
void vh_direct(vec3 N, vec3 V, vec3 L, vec3 lc, float att, float rough, inout vec3 diffuse, inout vec3 spec) {
	float nl = clamp(dot(N, L), 0.0, 1.0);
	vec3 irr = lc * att * nl;
	diffuse += irr / PI;
	vec3 H = normalize(L + V);
	float nv = clamp(abs(dot(N, V)), 1e-4, 1.0);
	float nh = clamp(dot(N, H), 0.0, 1.0);
	float vh = clamp(dot(V, H), 0.0, 1.0);
	float r = max(rough, 0.0525);
	float a2 = r * r * r * r;
	float fres = exp2((-5.55473 * vh - 6.98316) * vh);
	float F = 0.04 * (1.0 - fres) + fres;
	float gv = nl * sqrt(a2 + (1.0 - a2) * nv * nv);
	float gl = nv * sqrt(a2 + (1.0 - a2) * nl * nl);
	float vis = 0.5 / max(gv + gl, 1e-6);
	float den = nh * nh * (a2 - 1.0) + 1.0;
	spec += irr * F * vis * a2 / (PI * den * den);
}

// back-lit translucency for leaves and grass (inside the light loop, so it respects shadows)
// Godot Compatibility draws shadowed lights (our sun) in an additive pass that sRGB-encodes its result:
// additive = linear_to_srgb((DIFFUSE_LIGHT * ALBEDO + SPECULAR_LIGHT) * (1 - FOG.a)), with the approximation
// 1.055 x^(1/2.4) - 0.055 (the base pass goes through the same round trip, see vh_raw).
// So light() works out the whole linear contribution, faded by the fragment's own fog (FOG.a is left 0),
// and hands it over pre-decoded via SPECULAR_LIGHT.
// The fragment's fog amount and final albedo reach light() through vh_fog_a / vh_alb (set both right after
// vh_finish): ALBEDO read inside light() does not hold the fragment's value in this renderer.
varying float vh_fog_a;
varying vec3 vh_alb;

void vh_out(vec3 diffuse, vec3 spec, vec3 albedo, inout vec3 specular_light) {
	vec3 x = max(diffuse * albedo + spec, vec3(0.0)) * (1.0 - vh_fog_a);
	specular_light += pow((x + 0.055) / 1.055, vec3(2.4));
}

vec3 vh_transl(vec3 V, vec3 L, vec3 lc, float att, float strength) {
	return lc * att * strength * (0.25 + pow(clamp(dot(V, -L), 0.0, 1.0), 3.0) * 1.6);
}

// Indirect diffuse, to be multiplied by albedo: the sky's cosine-convolved radiance (L2 SH from
// VHSky, three.js env intensity 0.9) plus the hemisphere fill (evening #b9b3dc / #4d4a33 x 0.25, / PI).
vec3 vh_sky_sh(vec3 n) {
	return max(vh_sh0 * 0.282095 + vh_sh1 * (0.488603 * n.y) + vh_sh2 * (0.488603 * n.z) + vh_sh3 * (0.488603 * n.x)
		+ vh_sh4 * (1.092548 * n.x * n.y) + vh_sh5 * (1.092548 * n.y * n.z) + vh_sh6 * (0.315392 * (3.0 * n.z * n.z - 1.0))
		+ vh_sh7 * (1.092548 * n.x * n.z) + vh_sh8 * (0.546274 * (n.x * n.x - n.y * n.y)), vec3(0.0));
}

vec3 vh_indirect(vec3 n) {
	vec3 sky = vh_sky_sh(n);
	vec3 hemi = mix(vh_hemi_ground, vh_hemi_sky, n.y * 0.5 + 0.5) * (1.0 / PI);
	return sky * 0.9 + hemi;
}

// Specular sky light (three.js IBL: env radiance x DFGApprox, env intensity 0.9). Godot's own radiance
// reflections run far hotter on rough surfaces, so the environment's reflections are off and this is
// added as emission. Below the horizon the reference's env pass shows a dark ground.
vec3 vh_ibl_spec(vec3 n_view, vec3 v_view, float rough, vec3 f0, mat4 inv_view) {
	vec3 N = normalize((inv_view * vec4(n_view, 0.0)).xyz);
	vec3 V = normalize((inv_view * vec4(v_view, 0.0)).xyz);
	vec3 R = reflect(-V, N);
	vec3 env = vh_sky_sh(R);
	float blur = smoothstep(0.15, 0.6, rough);
	if (blur < 0.999) {   // the sharp sky only matters on glossy surfaces (the branch is per material)
		vec3 sharp = R.y >= 0.0 ? vh_sky(R) : mix(vh_sky(vec3(R.x, 0.0, R.z)) * 0.55, vh_sky_ground, smoothstep(0.0, 0.3, -R.y));
		env = mix(sharp, env, blur);
	}
	float dotNV = clamp(dot(N, V), 0.0, 1.0);
	vec4 r = rough * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
	float a004 = min(r.x * r.x, exp2(-9.28 * dotNV)) * r.x + r.y;
	vec2 fab = vec2(-1.04, 1.04) * a004 + r.zw;
	return env * (f0 * fab.x + fab.y) * 0.9;
}

// Shade of drifting fair-weather clouds on the sunlight. The noise is read where the light ray from
// this point meets a cloud deck 600 m up, so the shapes slide over hills, roofs and treetops alike.
float vh_cloud_sh(vec3 wp) {
	if (vh_cloud_shadow.x <= 0.0) return 1.0;
	vec3 L = normalize(vh_light);
	vec2 p = wp.xz + L.xz * ((600.0 - wp.y) / max(L.y, 0.15)) + vh_wind * (TIME * vh_cloud_shadow.w);
	float n = texture(cloud_noise, p * vh_cloud_shadow.y).r * 0.72 + texture(cloud_noise, p * (vh_cloud_shadow.y * 2.9) + 0.37).r * 0.28;
	return 1.0 - smoothstep(vh_cloud_shadow.z, vh_cloud_shadow.z + 0.14, n) * vh_cloud_shadow.x;
}

// The sun's attenuation for light(): its shadow map times the cloud shade.
float vh_sun_att(vec3 wp, float att) { return att * vh_cloud_sh(wp); }

// Lamps: street lights, trail bollards and lit doorways in view around the player, filled in by
// world.gd (16 slots; p = position + range, c = linear colour x intensity). They are shaded here and
// added to EMISSION rather than drawn as Godot lights: this renderer sRGB-encodes what its own lights
// add, together with EMISSION, which would bend the sky light of every surface a lamp touches.
// Lamps fade out between vh_lamp_fade.x and .y metres from vh_focus (the player); beyond that the
// ground glow decals (pool.gdshader) stand in for them, yielding by vh_lamp_fade.z inside.
global uniform vec3 vh_focus;
global uniform vec4 vh_lamp_fade;
global uniform int vh_lamp_n;
global uniform vec4 vh_lamp_p0;
global uniform vec4 vh_lamp_p1;
global uniform vec4 vh_lamp_p2;
global uniform vec4 vh_lamp_p3;
global uniform vec4 vh_lamp_p4;
global uniform vec4 vh_lamp_p5;
global uniform vec4 vh_lamp_p6;
global uniform vec4 vh_lamp_p7;
global uniform vec4 vh_lamp_p8;
global uniform vec4 vh_lamp_p9;
global uniform vec4 vh_lamp_p10;
global uniform vec4 vh_lamp_p11;
global uniform vec4 vh_lamp_p12;
global uniform vec4 vh_lamp_p13;
global uniform vec4 vh_lamp_p14;
global uniform vec4 vh_lamp_p15;
global uniform vec4 vh_lamp_c0;
global uniform vec4 vh_lamp_c1;
global uniform vec4 vh_lamp_c2;
global uniform vec4 vh_lamp_c3;
global uniform vec4 vh_lamp_c4;
global uniform vec4 vh_lamp_c5;
global uniform vec4 vh_lamp_c6;
global uniform vec4 vh_lamp_c7;
global uniform vec4 vh_lamp_c8;
global uniform vec4 vh_lamp_c9;
global uniform vec4 vh_lamp_c10;
global uniform vec4 vh_lamp_c11;
global uniform vec4 vh_lamp_c12;
global uniform vec4 vh_lamp_c13;
global uniform vec4 vh_lamp_c14;
global uniform vec4 vh_lamp_c15;

// One lamp: wrapped Lambert (wrap > 0 for foliage lit through its blades) and a GGX highlight, falling
// off with the inverse square inside a smooth range window; the +1 m2 stands in for the bulb's size.
void vh_lamp(vec4 p, vec4 c, vec3 wp, vec3 n, vec3 v, float rough, float wrap, inout vec3 dif, inout vec3 spe) {
	vec3 dl = p.xyz - wp;
	float d2 = dot(dl, dl);
	float r2 = p.w * p.w;
	if (d2 >= r2) return;
	vec3 l = dl * inversesqrt(max(d2, 1e-6));
	float w = 1.0 - d2 / r2;
	vec3 e = c.rgb * (w * w / (d2 + 1.0));
	float nl = dot(n, l);
	dif += e * max((nl + wrap) / (1.0 + wrap), 0.0);
	float a = max(rough * rough, 0.03);
	float a2 = a * a;
	float nh = max(dot(n, normalize(l + v)), 0.0);
	float den = nh * nh * (a2 - 1.0) + 1.0;
	spe += e * (max(nl, 0.0) * 0.01 * a2 / (PI * den * den));
}

// Radiance the lamps add to a surface (world-space normal); add it to EMISSION before vh_finish.
vec3 vh_lamps(vec3 wp, vec3 n, vec3 cam, float rough, vec3 albedo, float wrap) {
	if (vh_lamp_n <= 0) return vec3(0.0);
	vec3 v = normalize(cam - wp);
	vec3 d = vec3(0.0), s = vec3(0.0);
	vh_lamp(vh_lamp_p0, vh_lamp_c0, wp, n, v, rough, wrap, d, s);
	vh_lamp(vh_lamp_p1, vh_lamp_c1, wp, n, v, rough, wrap, d, s);
	vh_lamp(vh_lamp_p2, vh_lamp_c2, wp, n, v, rough, wrap, d, s);
	vh_lamp(vh_lamp_p3, vh_lamp_c3, wp, n, v, rough, wrap, d, s);
	if (vh_lamp_n > 4) {
		vh_lamp(vh_lamp_p4, vh_lamp_c4, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p5, vh_lamp_c5, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p6, vh_lamp_c6, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p7, vh_lamp_c7, wp, n, v, rough, wrap, d, s);
	}
	if (vh_lamp_n > 8) {
		vh_lamp(vh_lamp_p8, vh_lamp_c8, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p9, vh_lamp_c9, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p10, vh_lamp_c10, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p11, vh_lamp_c11, wp, n, v, rough, wrap, d, s);
	}
	if (vh_lamp_n > 12) {
		vh_lamp(vh_lamp_p12, vh_lamp_c12, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p13, vh_lamp_c13, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p14, vh_lamp_c14, wp, n, v, rough, wrap, d, s);
		vh_lamp(vh_lamp_p15, vh_lamp_c15, wp, n, v, rough, wrap, d, s);
	}
	return d * albedo * (1.0 / PI) + s;
}

// --- tree impostors (scripts/vh/vh_impostor.gd) ---------------------------------------------------------------
// Upper-hemisphere octahedral map: a direction (y >= 0) to 0..1 square and back. The horizon is the square's
// border, straight up its centre.
vec2 vh_hemioct(vec3 d) {
	vec2 a = d.xz / (abs(d.x) + abs(d.y) + abs(d.z));
	return vec2(a.x + a.y, a.x - a.y) * 0.5 + 0.5;
}

// Interleaved gradient noise: a stable per-pixel threshold for dithered cross-fades.
float vh_ign(vec2 frag) { return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715)))); }

// How far a tree at `origin` has handed over from its mesh to its impostor (0 mesh .. 1 impostor). It hands
// over where one texel of its impostor (texel_m metres, per instance) would cover vh_tree_lod.w screen pixels
// (vh_tree_lod.z: pixels per metre at 1 m for the main camera), kept between vh_tree_lod.x and .y metres;
// measured from the main camera so the shadow passes switch together with the view.
float vh_tree_fade(vec3 origin, float texel_m) {
	float d = clamp(vh_tree_lod.z * texel_m / vh_tree_lod.w, vh_tree_lod.x, vh_tree_lod.y);
	return smoothstep(d - 0.8, d + 0.8, distance(origin, vh_eye));
}

vec3 vh_tri_w(vec3 n) { vec3 b = pow(abs(n), vec3(4.0)); return b / (b.x + b.y + b.z); }
vec3 vh_tri_albedo(sampler2D t, vec3 p, vec3 b, float s) {
	return texture(t, p.zy * s).rgb * b.x + texture(t, p.xz * s).rgb * b.y + texture(t, p.xy * s).rgb * b.z;
}
vec3 vh_tri_normal(sampler2D t, vec3 p, vec3 n, vec3 b, float s, float k) {
	vec3 nX = texture(t, p.zy * s).xyz * 2.0 - 1.0;
	vec3 nY = texture(t, p.xz * s).xyz * 2.0 - 1.0;
	vec3 nZ = texture(t, p.xy * s).xyz * 2.0 - 1.0;
	nX.xy *= k; nY.xy *= k; nZ.xy *= k;
	nX = vec3(nX.xy + n.zy, abs(nX.z) * n.x);
	nY = vec3(nY.xy + n.xz, abs(nY.z) * n.y);
	nZ = vec3(nZ.xy + n.xy, abs(nZ.z) * n.z);
	return normalize(nX.zyx * b.x + nY.xzy * b.y + nZ.xyz * b.z);
}
