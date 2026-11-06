shader_type sky;
// atmosphere.ts SKY_FRAG: sky gradient, sun disc, banked painterly clouds. The cubemap pass is the
// reference's ENV_PASS (dark ground below the horizon) and feeds ambient + reflections (its PMREM).
// Clouds are static (the reference drifts them ~0.0025/s) so the radiance map is built once.
// Colours come from the time-of-day globals (vh_sky_*, vh_cloud_*). At night (vh_night) the disc at
// vh_sun is the moon, and a twinkling star field with the Milky Way shows between the clouds; time
// comes in through vh_time because TIME here would re-render the radiance cubemap every frame.
#include "res://shaders/vh/vh_sky.gdshaderinc"

global uniform vec4 vh_sun_core;      // rgb, intensity of the soft core (pow 400)
global uniform vec4 vh_sun_disc;      // rgb, intensity of the disc (main pass only)
global uniform vec3 vh_cloud_lit;
global uniform vec3 vh_cloud_lit_sun;
global uniform vec3 vh_cloud_shade;
global uniform vec3 vh_cloud_glow;
global uniform float vh_cloud_cover;

vec4 clouds(vec3 d) {
	vec2 uv = d.xz / (d.y + 0.07) * 0.55;
	float n = vh_fbm5(uv * 1.6 + vec2(3.1, 1.7));
	// cloud banks are placed relative to the sun, as in the reference (its sun sits at 7.5 deg)
	float az = atan(d.x, -d.z) - (atan(vh_sun.x, -vh_sun.z) - 0.1309);
	az = mod(az + PI, TAU) - PI;
	float bank = exp(-pow(abs((az + 0.30) / 0.38), 2.0)) * smoothstep(0.05, 0.12, d.y) * (1.0 - smoothstep(0.26, 0.42, d.y));
	float bank2 = exp(-pow(abs((az + 0.78) / 0.25), 2.0)) * smoothstep(0.08, 0.16, d.y) * (1.0 - smoothstep(0.24, 0.34, d.y));
	float wisp = exp(-pow(abs((az - 0.60) / 0.30), 2.0)) * smoothstep(0.10, 0.16, d.y) * (1.0 - smoothstep(0.26, 0.38, d.y));
	float high = smoothstep(0.35, 0.6, d.y) * 0.25;
	float cov = vh_cloud_cover - bank * 0.36 - bank2 * 0.22 - wisp * 0.2 - high * 0.2;
	float dens = smoothstep(cov, cov + 0.2, n);
	vec2 toSun = normalize(vh_sun.xz) * 0.08;
	float n2 = vh_fbm5((uv + toSun) * 1.6 + vec2(3.1, 1.7));
	float lit = clamp(0.55 + (n - n2) * 5.0, 0.0, 1.0);
	float sd = max(dot(d, vh_sun), 0.0);
	vec3 litCol = mix(vh_cloud_lit, vh_cloud_lit_sun, pow(sd, 4.0));
	vec3 cc = mix(vh_cloud_shade, litCol, lit * (0.55 + 0.45 * (1.0 - smoothstep(0.1, 0.4, d.y))));
	cc += vh_cloud_glow * pow(sd, 10.0) * (1.0 - dens) * 1.6;
	float fade = smoothstep(0.02, 0.1, d.y);
	return vec4(cc, dens * fade * 0.92);
}

// Stars on a cube-face grid of ~0.3 deg cells (one candidate each, more inside the Milky Way), a few
// bright and many faint, twinkling; plus the band's own faint glow. Fades into the horizon haze.
vec3 night_sky(vec3 d) {
	vec3 mwn = normalize(vec3(0.42, 0.55, -0.72));
	float band = exp(-pow(dot(d, mwn) / 0.2, 2.0));
	float dust = vh_fbm5(d.xz / (abs(d.y) + 0.6) * 3.2 + vec2(7.0, 3.0));
	vec3 col = vec3(0.022, 0.026, 0.04) * band * smoothstep(0.35, 0.8, dust) * 1.6;
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) { uv = d.zy / a.x; face = d.x > 0.0 ? 0.0 : 1.0; }
	else if (a.y >= a.z) { uv = d.xz / a.y; face = d.y > 0.0 ? 2.0 : 3.0; }
	else { uv = d.xy / a.z; face = d.z > 0.0 ? 4.0 : 5.0; }
	vec2 g = uv * 150.0;
	vec2 c = floor(g) + face * 517.0;
	float h = vh_hash12(c);
	float thr = mix(0.962, 0.9, band * smoothstep(0.3, 0.7, dust));
	if (h > thr) {
		vec2 o = vec2(vh_hash12(c + 11.7), vh_hash12(c + 37.3)) * 0.6 + 0.2;
		vec2 f = g - floor(g) - o;
		float mag = pow((h - thr) / (1.0 - thr), 3.0);
		float tw = 0.7 + 0.3 * sin(vh_time * (1.3 + h * 7.0) + h * 91.0);
		vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.88, 0.72), vh_hash12(c + 5.1));
		col += tint * exp(-dot(f, f) * 38.0) * (0.12 + 3.2 * mag) * tw;
	}
	return col * smoothstep(0.0, 0.22, d.y);
}

// The moon: a soft-edged disc with darker maria and a slightly dimmer limb.
vec3 moon(vec3 d, float sd) {
	float r = 0.0128;                       // ~0.73 deg
	float x = sqrt(max(2.0 * (1.0 - sd), 0.0)) / r;   // 0 at the centre, 1 at the edge
	if (x > 1.2) return vec3(0.0);
	vec3 t = normalize(cross(vh_sun, vec3(0.0, 1.0, 0.0)));
	vec3 b = cross(t, vh_sun);
	vec2 m = vec2(dot(d, t), dot(d, b)) / r;
	float maria = smoothstep(0.42, 0.62, vh_fbm5(m * 1.7 + vec2(4.0, 9.0)));
	float body = (1.0 - smoothstep(0.96, 1.0, x)) * (1.0 - 0.22 * x * x) * (1.0 - 0.3 * maria);
	return vec3(0.92, 0.95, 1.0) * body * 9.0;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col;
	if (AT_CUBEMAP_PASS && d.y < 0.0) {
		col = mix(vh_sky(vec3(d.x, 0.0, d.z)) * 0.55, vh_sky_ground, smoothstep(0.0, 0.3, -d.y));
	} else {
		col = vh_sky(d);
		float sd = max(dot(d, vh_sun), 0.0);
		col += vh_sun_core.rgb * pow(sd, 400.0) * vh_sun_core.a;
		if (!AT_CUBEMAP_PASS) {
			if (vh_night > 0.0) col += (night_sky(d) + moon(d, sd)) * vh_night;
			col += vh_sun_disc.rgb * smoothstep(0.99993, 0.99996, sd) * vh_sun_disc.a * (1.0 - vh_night);
		}
		if (d.y > 0.01) {
			vec4 c = clouds(d);
			col = mix(col, c.rgb, c.a);
		}
	}
	if (!AT_CUBEMAP_PASS) col = mix(col, vec3(0.03, 0.025, 0.05), focus_amount * 0.92);
	COLOR = vh_raw(col);
}
