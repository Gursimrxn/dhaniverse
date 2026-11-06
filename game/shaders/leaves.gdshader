shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_prepass_alpha;
#include "res://shaders/common.gdshaderinc"

// Mesh: every card is 4 verts sharing one clump centre (VERTEX). UV = corner.
// NORMAL = direction from crown centre (rounded crown lighting).
// COLOR: r = depth in crown (0 inner, 1 outer), g = random, b = card size, a = species tint mix
uniform vec3 shade_col : source_color = vec3(0.16, 0.31, 0.35);
uniform vec3 mid_col : source_color = vec3(0.38, 0.62, 0.32);
uniform vec3 light_col : source_color = vec3(0.86, 0.9, 0.42);
uniform vec3 alt_col : source_color = vec3(0.96, 0.6, 0.69);
uniform float card_size = 1.0;
uniform float leaf_count = 5.0;
uniform int mode = 0;                 // 0 = petal leaf clusters (original leaf_alpha), 1 = fir sprays
uniform sampler2D alpha_tex : filter_linear;
uniform float light_steps = 5.0;

varying vec3 wpos;
varying float depth_c;
varying float rnd;
varying vec3 crown_n;

void vertex() {
	depth_c = COLOR.r;
	rnd = COLOR.g;
	crown_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 centre_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// sway: whole crown + per-card flutter
	float gust = fbm2(centre_w.xz * 0.05 + TIME * 0.18);
	centre_w.xz += vec2(1.0, 0.35) * (gust - 0.4) * 0.25 * wind_strength * (0.4 + COLOR.r);
	centre_w.y += sin(TIME * 2.0 + rnd * 40.0) * 0.03;
	// low foliage (bushes, low limbs) parts around characters
	vec3 root_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float low = 1.0 - smoothstep(0.6, 2.6, centre_w.y - root_w.y);
	centre_w += actor_push(centre_w, 1.5) * 0.45 * low;

	// expand into a camera-facing card, slightly rotated per card
	float scale = length(MODEL_MATRIX[0].xyz);
	vec2 corner = (UV - 0.5) * card_size * COLOR.b * scale * 2.0;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float a = rnd * 6.28;
	if (mode == 2) {
		a = 3.14159 + (rnd - 0.5) * 0.35;   // weeping strands hang straight down
	}
	if (mode == 1) {
		vec3 o = centre_w - root_w;
		o.y -= length(o.xz) * 0.35 + 0.15;
		a = atan(-dot(o, right), dot(o, up)) + (rnd - 0.5) * 0.5;
	}
	corner = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * corner;
	wpos = centre_w + right * corner.x + up * corner.y + crown_n * 0.15;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(crown_n, 0.0)).xyz;
}

// fir spray: central rib with slanted needle teeth, shorter towards the tip
float sprig(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float y = p.y * 0.5 + 0.5;
	float len = (1.0 - y * 0.75) * 0.95;
	float tooth = len * (1.0 - fract(y * 8.0 - abs(p.x) * 1.6));
	float needles = step(abs(p.x), tooth) * step(0.02, y) * step(y, 0.98);
	float rib = 1.0 - step(0.07, abs(p.x));
	return max(needles, rib);
}

void fragment() {
	float a = mode >= 1 ? sprig(UV) : texture(alpha_tex, UV).r;
	if (a < 0.5) discard;
	ALPHA = 1.0;

	float sunward = dot(crown_n, normalize(sun_dir)) * 0.5 + 0.5;
	float t = clamp(depth_c * 0.45 + sunward * 0.45, 0.0, 1.0);
	vec3 col = mix(shade_col, mid_col, smoothstep(0.1, 0.55, t));
	col = mix(col, light_col, smoothstep(0.6, 1.0, t));
	col = mix(col, alt_col * mix(0.88, 1.0, t), COLOR.a);
	col *= 0.92 + hash12(vec2(rnd * 31.0, 2.0)) * 0.16;
	col *= 1.0 - cloud_shadow(wpos) * 0.2;
	ALBEDO = apply_focus(col, wpos);
	float back = pow(clamp(dot(-VIEW, (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz), 0.0, 1.0), 4.0);
	EMISSION = vec3(0.9, 0.85, 0.35) * back * depth_c * 0.25 * (1.0 - focus_amount);
	ROUGHNESS = 1.0;
}

void light() {
	// the original tree look: stepped cel light plus a stepped rim
	float l = clamp(dot(NORMAL, LIGHT) * 0.75 + 0.25, 0.0, 1.0);
	l = ceil(l * light_steps) / light_steps;
	DIFFUSE_LIGHT += l * (LIGHT_COLOR / PI) * ATTENUATION;
	float rim = (1.0 - dot(NORMAL, VIEW)) * l;
	rim = round(rim * light_steps) / light_steps;
	DIFFUSE_LIGHT += rim * rim * ATTENUATION * LIGHT_COLOR / PI * 0.6;
}
