shader_type canvas_item;
// The valley's copy of shaders/vh/grade.gdshader: bloom with five taps a level, steady 12-step light rays.

// The reference's output chain on the linear HDR frame (project uses hdr_2d, environment tonemap is
// linear): three.js ACESFilmicToneMapping (exposure / 0.6, AP1 matrices, RRT+ODT fit) -> sRGB transfer
// (OutputPass) -> Game.ts GradeShader (cool shadows, warm highlights, S-curve, vignette, dither).
// The Compatibility renderer does no sRGB encoding of its own, so this pass is the only one.
// The grade's tints, curve, saturation and white balance follow the time of day (defaults: the
// reference evening), and in daylight the sun throws screen-space god rays when it is in view.
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float bloom_strength = 0.32;      // UnrealBloomPass(strength 0.32, radius 0.55, threshold 1.1)
uniform float bloom_threshold = 1.1;
uniform float exposure = 1.0;
uniform float vignette = 0.42;
uniform float letterbox = 0.0;
uniform float sharpen = 0.0;      // > 0 when the 3D image is rendered smaller and scaled up (render scale < 1)
uniform vec3 lift = vec3(0.014, -0.002, 0.032);     // added in the shadows
uniform vec3 gain = vec3(0.018, 0.006, -0.012);     // added in the highlights
uniform float curve = 0.1;                          // S-curve
uniform float saturation = 1.0;
uniform float shadow_sat = 1.0;                     // saturation in the darks (night vision greys them)
uniform vec3 white = vec3(1.0);                     // white balance, linear gain before the tonemap
uniform float rays = 0.0;                           // god ray strength
uniform float ray_threshold = 1.6;                  // HDR luminance that counts as open sky / sun
uniform vec3 ray_tint = vec3(1.0, 0.95, 0.85);
uniform vec2 sun_uv = vec2(0.5, -1.0);              // the sun on screen (set per frame)
uniform float sun_vis = 0.0;                        // 0 when it is behind the camera / far off screen

vec3 rrt_odt(vec3 v) {
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return a / b;
}

vec3 aces(vec3 color) {
	const mat3 IN = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
	const mat3 OUT = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
	color *= exposure / 0.6;
	color = OUT * rrt_odt(IN * color);
	return clamp(color, 0.0, 1.0);
}

vec3 srgb(vec3 c) {
	return mix(pow(c, vec3(0.41666)) * 1.055 - vec3(0.055), c * 12.92, vec3(lessThanEqual(c, vec3(0.0031308))));
}

float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// LuminosityHighPassShader keeps pixels whose luminance clears the threshold (smoothWidth 0.01). Here the
// wide levels threshold an already-averaged mip, so they get a soft knee: a hard step on sparse taps
// shows up as cell-shaped edges.
vec3 hp(vec3 c, float knee) {
	return c * smoothstep(bloom_threshold - knee, bloom_threshold + 0.01 + knee, dot(c, vec3(0.2126, 0.7152, 0.0722)));
}

// one blur level: a mip near sigma / 1.5 texels, 3x3 Gaussian taps at +-1.25 sigma
vec3 level(vec2 uv, vec2 px, float sigma) {
	float lod = max(log2(sigma / 1.5), 0.0);
	vec2 o = px * sigma * 1.25;
	// four diagonal taps round the centre: the mip's own filtering does the rest of the blur
	vec3 k = hp(textureLod(screen, uv + o, lod).rgb, 0.4) + hp(textureLod(screen, uv - o, lod).rgb, 0.4)
		+ hp(textureLod(screen, uv + vec2(o.x, -o.y), lod).rgb, 0.4) + hp(textureLod(screen, uv + vec2(-o.x, o.y), lod).rgb, 0.4);
	return (hp(textureLod(screen, uv, lod).rgb, 0.4) + k * 0.5) / 3.0;
}

// UnrealBloomPass: five mips (half res down to 1/32) blurred with kernels 3..11 texels (truncated, so
// std ~1.36..5.5 texels), each fed the previous level -> cumulative std of 0.0027, 0.010, 0.030, 0.078 and
// 0.193 screen heights. Composite factors lerp(f, 1.2 - f, radius 0.55) for f = 1.0 .. 0.2.
vec3 bloom(vec2 uv, vec2 px) {
	float sh = 1.0 / px.y;
	return hp(textureLod(screen, uv, 0.6).rgb, 0.0) * 0.56 + level(uv, px, 0.0102 * sh) * 0.58 + level(uv, px, 0.030 * sh) * 0.60
		+ level(uv, px, 0.078 * sh) * 0.62 + level(uv, px, 0.193 * sh) * 0.64;
}

// Light shafts: march from the pixel towards the sun over the quarter-res mip, gathering what is bright
// enough to be open sky; leaves, roofs and hills in between leave dark streaks. Dithered start.
vec3 god_rays(vec2 uv, vec2 px, float jitter) {
	vec2 to_sun = sun_uv - uv;
	vec2 st = to_sun / 12.0;
	vec2 s = uv + st * jitter;
	vec3 acc = vec3(0.0);
	float w = 1.0;
	for (int i = 0; i < 12; i++) {
		vec3 c = textureLod(screen, clamp(s, vec2(0.002), vec2(0.998)), 2.0).rgb;
		acc += c * smoothstep(ray_threshold, ray_threshold * 2.2, dot(c, vec3(0.2126, 0.7152, 0.0722))) * w;
		w *= 0.91;
		s += st;
	}
	float d = length(to_sun * vec2(px.y / px.x, 1.0));
	return min(acc / 12.0, vec3(4.0)) * ray_tint * (rays * sun_vis * (1.0 - smoothstep(0.0, 1.2, d)));
}

void fragment() {
	vec3 hdr = max(texture(screen, SCREEN_UV).rgb, vec3(0.0));
	if (sharpen > 0.0) {
		// contrast-adaptive sharpening (after AMD's CAS / FSR 1 RCAS): the cross of neighbours sets how far the
		// centre may be pushed from their mean without ringing past their range
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 n = textureLod(screen, SCREEN_UV + vec2(0.0, -px.y), 0.0).rgb, s2 = textureLod(screen, SCREEN_UV + vec2(0.0, px.y), 0.0).rgb;
		vec3 e = textureLod(screen, SCREEN_UV + vec2(px.x, 0.0), 0.0).rgb, w = textureLod(screen, SCREEN_UV - vec2(px.x, 0.0), 0.0).rgb;
		vec3 lo = min(min(min(n, s2), min(e, w)), hdr), hi = max(max(max(n, s2), max(e, w)), hdr);
		vec3 amp = clamp(min(lo, 2.0 - hi) / max(hi, vec3(1e-4)), 0.0, 1.0);
		vec3 k = -sqrt(amp) * mix(0.125, 0.2, sharpen);
		hdr = max((hdr + (n + s2 + e + w) * k) / (1.0 + 4.0 * k), vec3(0.0));
	}
	if (bloom_strength > 0.0) hdr += bloom(SCREEN_UV, SCREEN_PIXEL_SIZE) * bloom_strength;
	if (rays > 0.0 && sun_vis > 0.0) hdr += god_rays(SCREEN_UV, SCREEN_PIXEL_SIZE, 0.5);
	vec3 c = srgb(aces(hdr * white));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c += lift * (1.0 - l) * (1.0 - l);
	c += gain * l * l;
	c = mix(c, c * c * (3.0 - 2.0 * c), curve);
	c = max(mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, mix(shadow_sat, saturation, smoothstep(0.04, 0.45, l))), vec3(0.0));
	vec2 q = SCREEN_UV - 0.5;
	c *= 1.0 - dot(q * vec2(1.0, 0.8), q * vec2(1.0, 0.8)) * vignette;
	// a fixed, faint dither only to stop 8-bit banding in the sky; no animated grain on the picture
	c += (h(FRAGCOORD.xy) - 0.5) / 512.0;
	float bar = 0.11 * letterbox;
	if (SCREEN_UV.y < bar || SCREEN_UV.y > 1.0 - bar) c = vec3(0.0);
	COLOR = vec4(c, 1.0);
}
