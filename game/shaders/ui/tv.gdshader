shader_type canvas_item;
// The ATM's TV filter (the board's .tv): over what is already drawn under it, curved glass, colour fringes, a soft glow, the
// blue's light falling off to the edges, a glare, scanlines, RGB stripes, a band rolling down and a faint flicker. One rect, seven
// reads of the screen, drawn only while the ATM is up.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float height_rem = 36.8;   // the screen's height in board rem: the lines are spaced in rem
uniform float radius_rem = 2.4;
uniform float power = 1.0;         // 0 off, 1 on: the switch-on squeeze
uniform float bend = 0.035;        // how curved the glass is
uniform vec4 bezel : source_color = vec4(0.078, 0.082, 0.082, 1.0);

void fragment() {
	vec2 size = abs(1.0 / vec2(dFdx(UV.x), dFdy(UV.y)));     // the rect in screen pixels
	vec2 to_screen = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	float rem = size.y / height_rem;
	// switching on: a bright line that opens out (the board's @keyframes power)
	float a = clamp(power / 0.45, 0.0, 1.0);
	float b = clamp((power - 0.45) / 0.55, 0.0, 1.0);
	vec2 squeeze = power < 0.45 ? vec2(mix(0.7, 1.0, a), mix(0.008, 0.02, a)) : vec2(1.0, mix(0.02, 1.0, b));
	float bright = power < 0.45 ? 4.0 : mix(4.0, 1.0, b);
	vec2 c = (UV - 0.5) / squeeze * 2.0;
	c *= 1.0 + bend * c.yx * c.yx;
	vec2 uv = c * 0.5 + 0.5;
	vec2 p = (uv - 0.5) * size;
	float r = radius_rem * rem;
	vec2 q = abs(p) - (size * 0.5 - r);
	if (length(max(q, 0.0)) - r > 0.0) {
		COLOR = bezel;
	} else {
		vec2 at = SCREEN_UV + (uv - UV) * to_screen;
		vec2 fringe = vec2(0.12 * rem * SCREEN_PIXEL_SIZE.x, 0.0);
		vec3 col = vec3(texture(screen_tex, at - fringe).r, texture(screen_tex, at).g, texture(screen_tex, at + fringe).b);
		vec2 g = 0.5 * rem * SCREEN_PIXEL_SIZE;
		vec3 glow = (texture(screen_tex, at + g).rgb + texture(screen_tex, at - g).rgb + texture(screen_tex, at + vec2(g.x, -g.y)).rgb + texture(screen_tex, at + vec2(-g.x, g.y)).rgb) * 0.25;
		col = max(col, mix(col, glow, 0.45));      // light spreads, dark doesn't
		// radial-gradient(ellipse at 50% 30%, #2433ff 0%, #0011FF 55%, #000db8 100%)
		float t = length((uv - vec2(0.5, 0.3)) / vec2(0.5, 0.7)) * 0.7071;
		col += vec3(0.141, 0.133, 0.0) * clamp(1.0 - t / 0.55, 0.0, 1.0);
		col *= mix(1.0, 0.72, clamp((t - 0.55) / 0.45, 0.0, 1.0));
		// .roll: a 30% band, top -30% to 100% in 5.5 s
		float k = (uv.y - (fract(TIME / 5.5) * 1.3 - 0.3)) / 0.3;
		if (k > 0.0 && k < 1.0) col = mix(col, vec3(1.0), 0.09 * (1.0 - abs(k * 2.0 - 1.0)));
		// :before: the vignette, then the glare at 115deg
		float v = length((uv - 0.5) * 2.0) * 0.7071;
		col = mix(col, vec3(0.0, 0.0, 0.118), 0.6 * clamp((v - 0.58) / 0.42, 0.0, 1.0));
		float along = dot(p, vec2(0.906, 0.423)) / (size.x * 0.906 + size.y * 0.423) + 0.5;
		col = mix(col, vec3(1.0), 0.14 * clamp(1.0 - along / 0.28, 0.0, 1.0));
		// :after: scanlines every .4rem, and the RGB stripes
		if (fract(uv.y * size.y / rem / 0.4) < 0.375) col *= 0.8;
		float s = fract(uv.x * size.x / rem / 0.4);
		col = mix(col, s < 0.325 ? vec3(1.0, 0.0, 0.235) : (s < 0.65 ? vec3(0.0, 1.0, 0.47) : vec3(0.0, 0.353, 1.0)), 0.05);
		col *= mix(0.985, 1.0, step(0.5, fract(TIME / 0.16)));
		COLOR = vec4(col * bright, 1.0);
	}
}
