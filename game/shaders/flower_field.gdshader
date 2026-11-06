shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/field.gdshaderinc"
// GPU-placed field variant (see field.gdshaderinc); per-instance data comes from lattice hashes.

// Wildflower: COLOR.r = 1 on the head quad, 0 on stem/leaf quads.
// INSTANCE_CUSTOM: r = species (daisy/buttercup/pink/lavender), g = size, b = phase
uniform vec3 stem_col : source_color = vec3(0.24, 0.5, 0.22);

varying vec3 wpos;
varying float is_head;
varying float species;

void vertex() {
	vec3 hs;
	vec4 fp = field_place(MODEL_MATRIX[3].xyz, NODE_POSITION_WORLD, hs);
	VERTEX = field_yaw(hs.x * 6.2832) * VERTEX * fp.w;
	is_head = COLOR.r;
	species = hs.y;
	vec3 root_w = fp.xyz;
	float h = clamp(VERTEX.y / 0.35, 0.0, 1.0);
	vec2 wind_dir = normalize(vec2(1.0, 0.35));
	float gust = fbm2(root_w.xz * 0.08 - wind_dir * TIME * 0.4);
	float bob = sin(TIME * 3.0 + hs.z * 6.28) * 0.04;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * ((gust - 0.3) * 0.12 * wind_strength + bob) * h;
	vec3 pv = actor_push(root_w, 1.0);
	off += pv * 0.3 * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	VERTEX += fp.xyz - MODEL_MATRIX[3].xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 petal_col(float s) {
	if (s < 0.64) return vec3(0.99, 0.98, 0.95);   // daisy
	if (s < 0.72) return vec3(1.0, 0.82, 0.25);    // buttercup
	if (s < 0.9) return vec3(0.97, 0.62, 0.74);    // pink campion
	return vec3(0.62, 0.52, 0.9);                 // lavender-blue
}

void fragment() {
	vec3 col = stem_col;
	if (is_head > 0.5) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float a = atan(q.y, q.x);
		float petals = species < 0.64 ? 11.0 : 5.0;
		float edge = 0.62 + 0.38 * abs(cos(a * petals * 0.5));
		if (r > edge) discard;
		col = petal_col(species);
		col *= 0.88 + 0.12 * (1.0 - r);
		float centre = 1.0 - smoothstep(0.18, 0.24, r);
		col = mix(col, vec3(0.98, 0.72, 0.12), centre * (species < 0.6 ? 1.0 : 0.6));
	} else {
		float x = abs(UV.x - 0.5) * 2.0;
		if (x > 0.25 + (1.0 - UV.y) * 0.5 * step(UV.y, 0.5)) discard;
	}
	ALBEDO = apply_focus(col, wpos);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT) * 0.5 + 0.5, ATTENUATION, LIGHT_COLOR);
}
