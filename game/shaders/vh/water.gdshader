shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// River water, after water.ts, made physical. Ripples: flow-mapped dual-phase normals plus two drifting detail
// layers, calmer with distance so the far reaches lie glassy. What you see through the surface is the real
// river bed (screen texture, bent by the ripples), dimmed and tinted by the water it passes through (Beer-
// Lambert absorption over the true path length from the depth buffer) and veiled by light scattered in the
// water. What it reflects is traced in screen space along the reflected ray (banks, trees, buildings, the far
// hills), with the sky beyond; Fresnel (F0 0.02) mixes the two. Sun glint, spray foam under the falls.
uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D t_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform bool sky_only = true;                                     // (kept for the scene files; reflections are traced now)
uniform vec3 absorb = vec3(0.5, 0.36, 0.4);                       // extinction per metre: silt clouds it, reds go a little first
uniform vec3 scatter : source_color = vec3(0.17, 0.2, 0.14);      // in-scattering albedo of the silty body (sRGB): olive
uniform float ripple = 1.0;
global uniform vec3 vh_sun_spec;                                  // sun (or moon) glint colour
uniform vec2 foam_center = vec2(0.0, -10000.0);

varying vec3 wpos;
varying vec2 flow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = UV2;
}

vec3 view_at(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	return v.xyz / v.w;
}

// Screen-space trace of the reflected ray from view-space p along r; rgb = what it meets, a = confidence.
vec4 trace(vec3 p, vec3 r, mat4 proj, mat4 inv_proj, float jitter) {
	float len = 450.0;
	if (p.z + r.z * len > -0.2) len = (-0.2 - p.z) / r.z;      // keep the end in front of the camera
	vec4 h0 = proj * vec4(p, 1.0);
	vec4 h1 = proj * vec4(p + r * len, 1.0);
	float k0 = 1.0 / h0.w, k1 = 1.0 / h1.w;
	vec2 s0 = h0.xy * k0, s1 = h1.xy * k1;
	float z0 = p.z * k0, z1 = (p.z + r.z * len) * k1;
	const int STEPS = 28;
	float prev = 0.0;
	for (int i = 1; i <= STEPS; i++) {
		float t = pow((float(i) - 1.0 + jitter) / float(STEPS), 1.7);
		vec2 uv = mix(s0, s1, t) * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;
		float rz = mix(z0, z1, t) / mix(k0, k1, t);
		vec3 sp = view_at(uv, inv_proj);
		float behind = sp.z - rz;                                 // > 0: the ray has gone behind the scene there
		if (behind > 0.0 && sp.z > -5000.0) {
			if (behind < max(1.2, -sp.z * 0.06)) {
				// home in between the last step in front and this one
				float a = prev, b = t;
				for (int j = 0; j < 4; j++) {
					float m = (a + b) * 0.5;
					vec2 mu = mix(s0, s1, m) * 0.5 + 0.5;
					float mz = mix(z0, z1, m) / mix(k0, k1, m);
					if (view_at(mu, inv_proj).z - mz > 0.0) b = m; else a = m;
				}
				uv = mix(s0, s1, b) * 0.5 + 0.5;
				vec2 edge = smoothstep(vec2(0.0), vec2(0.08), uv) * (1.0 - smoothstep(vec2(0.92), vec2(1.0), uv));
				return vec4(texture(screen_tex, uv).rgb, edge.x * edge.y * (1.0 - smoothstep(0.75, 1.0, b)));
			}
		}
		prev = t;
	}
	return vec4(0.0);
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = distance(wpos, CAMERA_POSITION_WORLD);
	float ph0 = fract(TIME * 0.2), ph1 = fract(TIME * 0.2 + 0.5);
	float wB = abs(ph0 - 0.5) * 2.0;
	vec2 fl = flow * 2.4;
	vec2 nA = texture(t_normal, p * 0.11 - fl * ph0).xy * 2.0 - 1.0;
	vec2 nB = texture(t_normal, p * 0.11 - fl * ph1 + 0.5).xy * 2.0 - 1.0;
	vec2 n1 = mix(nA, nB, wB);
	vec2 n2 = texture(t_normal, p * 0.43 + TIME * vec2(0.021, -0.013)).xy * 2.0 - 1.0;
	vec2 n3 = texture(t_normal, p * 0.29 - TIME * vec2(0.012, 0.024)).xy * 2.0 - 1.0;
	vec2 n4 = texture(t_normal, p * 1.37 - fl * ph0 * 1.6 + TIME * vec2(0.05, 0.03)).xy * 2.0 - 1.0;
	float agit = 1.0 - smoothstep(2.5, 15.0, distance(p, foam_center));
	float calm = mix(1.0, 0.3, smoothstep(25.0, 260.0, dist));
	vec2 slope = (n1 * 0.55 + (n2 + n3) * 0.22 + n4 * 0.12 * (1.0 - smoothstep(6.0, 30.0, dist))) * (0.16 + agit * 0.8) * calm * ripple;
	vec3 N = normalize(vec3(slope.x, 1.0, slope.y));
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float nv = max(dot(N, V), 0.0);
	float F = 0.02 + 0.98 * pow(1.0 - nv, 5.0);

	// --- what lies under the surface: the bed, through the water between
	vec3 vp = VERTEX;
	vec3 bedv = view_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	float path = max(length(bedv) - length(vp), 0.0);
	vec2 ruv = SCREEN_UV + slope * 0.05 * clamp(path * 0.6, 0.0, 1.0) / max(1.0, -vp.z * 0.08);
	vec3 bedr = view_at(ruv, INV_PROJECTION_MATRIX);
	if (length(bedr) < length(vp)) ruv = SCREEN_UV;             // bent onto something in front of the water: don't
	else path = max(length(bedr) - length(vp), 0.0);
	vec3 bed = texture(screen_tex, ruv).rgb;
	vec3 L = normalize(vh_light);
	vec3 trans = exp(-absorb * path * 1.15);
	// light scattered back out of the body: the water's own olive green, lit by the sun and the sky's brightness
	// (the sky's blue reaches the eye by reflection, below, not through the water)
	float sky_l = dot(vh_indirect(vec3(0.0, 1.0, 0.0)), vec3(0.2126, 0.7152, 0.0722));
	vec3 inscatter = vh_lin(scatter) * (vh_sun_light * (max(L.y, 0.0) * 0.32 / PI) * vh_cloud_sh(wpos) + sky_l);
	vec3 body = bed * trans + inscatter * (1.0 - trans);

	// --- what it reflects: traced along the ray, the sky beyond (dark ground below the horizon, as the env pass)
	vec3 R = reflect(-V, N);
	vec3 Rs = R;
	Rs.y = max(Rs.y, 0.015);
	vec3 refl = vh_sky(Rs) * 0.94;
	vec3 Rv = normalize((VIEW_MATRIX * vec4(R, 0.0)).xyz);
	vec4 hit = trace(vp, Rv, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, vh_ign(FRAGCOORD.xy));
	refl = mix(refl, hit.rgb, hit.a);

	vec3 col = mix(body, refl, F);
	// the sun on the ripples: a hard glint and a soft sheen, both behind the cloud shade
	vec3 H = normalize(L + V);
	float nh = max(dot(N, H), 0.0);
	col += vh_sun_spec * (pow(nh, 900.0) * 4.0 + pow(nh, 120.0) * 0.06) * vh_cloud_sh(wpos) * (1.0 - hit.a * 0.85);
	// spray foam where the falls churn the pool
	float fn = vh_vnoise(p * 1.6 - flow * TIME * 2.0) * 0.6 + vh_vnoise(p * 4.1 - TIME * 0.35) * 0.4;
	float foam = clamp(smoothstep(0.5, 0.82, fn) * agit * 0.9 + pow(agit, 3.0) * 0.35, 0.0, 1.0);
	col = mix(col, vec3(0.86, 0.86, 0.86) * (vh_sun_light * (max(L.y, 0.0) / PI) + vh_indirect(vec3(0.0, 1.0, 0.0))), foam);
	ALBEDO = vh_fogged(col, wpos, CAMERA_POSITION_WORLD, 0.0);
	ALPHA = 1.0 - vh_outside(wpos) * 0.85;
}
