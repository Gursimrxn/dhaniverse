shader_type sky;

global uniform float focus_amount;
uniform vec3 top : source_color = vec3(0.24, 0.5, 0.82);
uniform vec3 mid : source_color = vec3(0.5, 0.74, 0.92);
uniform vec3 horizon : source_color = vec3(0.88, 0.94, 0.95);
uniform vec3 ground : source_color = vec3(0.78, 0.86, 0.85);
uniform vec3 cloud_col : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.72, 0.8, 0.9);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.92, 0.78);

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y);
}

void sky() {
	float y = EYEDIR.y;
	vec3 col = mix(horizon, mid, smoothstep(0.0, 0.25, y));
	col = mix(col, top, smoothstep(0.25, 0.85, y));
	col = mix(col, ground, smoothstep(0.0, -0.15, y));

	// sun: soft core + wide honey halo
	float sd = dot(EYEDIR, LIGHT0_DIRECTION);
	// wide low-sun glow that warms the horizon around the sun, then the tight halo
	col = mix(col, sun_glow, pow(max(sd, 0.0), 5.0) * 0.55 * (1.0 - smoothstep(0.0, 0.5, y)));
	col += sun_glow * pow(max(sd, 0.0), 24.0) * 0.45;
	col += vec3(1.0, 0.95, 0.85) * smoothstep(0.9985, 0.9995, sd);

	// puffy painted clouds on a flattened dome
	if (y > 0.02) {
		vec2 p = EYEDIR.xz / (y + 0.18) * 1.6 + vec2(TIME * 0.006, 0.0);
		float c = n(p) * 0.6 + n(p * 2.3) * 0.3 + n(p * 5.1) * 0.1;
		float cov = smoothstep(0.5, 0.72, c) * smoothstep(0.02, 0.2, y);
		vec3 cc = mix(cloud_shade, cloud_col, smoothstep(0.5, 0.85, c) + max(sd, 0.0) * 0.3);
		col = mix(col, cc, cov * 0.85);
	}
	COLOR = mix(col, vec3(0.03, 0.025, 0.05), focus_amount * 0.92);
}
