shader_type canvas_item;
// Cinematic finishing pass over the 3D frame (browser-safe: screen texture only).
// sun shafts · split-tone grade · tilt-shift · vignette · grain · fringing · letterbox

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec2 sun_uv = vec2(0.8, 0.1);      // sun position on screen (set from script)
uniform float sun_visible = 1.0;           // 0 when the sun is behind the camera
uniform float shaft_strength = 0.18;
uniform float tilt_shift = 0.35;            // blur amount at the top/bottom bands
uniform float tilt_center = 0.55;          // in-focus band centre (0 top, 1 bottom)
uniform float tilt_band = 0.3;
uniform float letterbox = 0.0;             // 0..1 animated bars
uniform float grain = 0.02;
uniform float fringe = 0.0006;
uniform float interior = 0.0;              // 1 while inside a building: calmer grade
uniform vec3 shadow_tint : source_color = vec3(0.16, 0.36, 0.42);
uniform vec3 highlight_tint : source_color = vec3(1.0, 0.86, 0.66);

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 tap(vec2 uv) {
	// tiny chromatic fringing towards the edges
	vec2 d = (uv - 0.5) * fringe * length(uv - 0.5) * 4.0;
	return vec3(texture(screen, uv + d).r, texture(screen, uv).g, texture(screen, uv - d).b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 col = tap(uv);

	// tilt-shift: 12-tap disc blur outside the focus band
	float band = smoothstep(tilt_band, tilt_band + 0.3, abs(uv.y - tilt_center)) * tilt_shift * (1.0 - interior);
	if (band > 0.01) {
		vec3 acc = col;
		float r = band * 7.0;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 2.39996;
			float rr = r * sqrt((float(i) + 0.5) / 12.0);
			acc += texture(screen, uv + vec2(cos(a), sin(a)) * rr * px).rgb;
		}
		col = acc / 13.0;
	}

	// screen-space sun shafts: march towards the sun gathering bright pixels
	if (sun_visible > 0.01 && shaft_strength > 0.0) {
		vec2 dir = (sun_uv - uv) / 24.0;
		vec2 s = uv;
		float decay = 1.0;
		vec3 shafts = vec3(0.0);
		for (int i = 0; i < 24; i++) {
			s += dir;
			vec3 c = texture(screen, clamp(s, vec2(0.001), vec2(0.999))).rgb;
			float b = max(luma(c) - 0.72, 0.0);
			shafts += c * b * decay;
			decay *= 0.94;
		}
		float falloff = 1.0 - smoothstep(0.0, 0.9, distance(uv, sun_uv));
		col += shafts * highlight_tint * shaft_strength * sun_visible * (0.35 + falloff) / 6.0 * (1.0 - interior);
	}

	// grade: gentle S-curve, teal shadows, warm highlights, vibrance
	float l = luma(col);
	col = mix(col, col * shadow_tint * 2.2, (1.0 - smoothstep(0.0, 0.45, l)) * 0.1);
	col = mix(col, col * highlight_tint * 1.06, smoothstep(0.5, 1.0, l) * 0.15);
	col = col * col * (3.0 - 2.0 * col) * 0.35 + col * 0.65;
	float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
	col = mix(vec3(luma(col)), col, 1.0 + 0.06 * (1.0 - sat));

	// vignette + grain
	vec2 v = uv - 0.5;
	col *= 1.0 - smoothstep(0.45, 0.95, length(v * vec2(1.1, 1.0))) * 0.32;
	col += (rnd(uv * 512.0 + fract(TIME) * 37.0) - 0.5) * grain;

	// letterbox bars for cinematic moments
	float bar = 0.11 * letterbox;
	if (uv.y < bar || uv.y > 1.0 - bar) col = vec3(0.0);

	COLOR = vec4(col, 1.0);
}
