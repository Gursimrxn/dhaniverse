// Sky gradient + globals shared by the sky shader and every surface (atmosphere.ts SKY_GLSL).
// The sky colours are globals so the valley can change the time of day (scripts/world/sky_modes.gd);
// their project defaults are the reference's evening, so the parity harness renders as before.
global uniform vec3 vh_sun;       // towards the visible sun disc (the moon at night)
global uniform vec3 vh_light;     // towards the shading light
global uniform vec2 vh_wind;
global uniform float vh_water_y;  // valley water level the height mist is measured from
global uniform float vh_refl_y;   // mirror plane: cameras below it (the reflection camera) clip below it
global uniform vec3 vh_sh0;
global uniform vec3 vh_sh1;
global uniform vec3 vh_sh2;
global uniform vec3 vh_sh3;
global uniform vec3 vh_sh4;
global uniform vec3 vh_sh5;
global uniform vec3 vh_sh6;
global uniform vec3 vh_sh7;
global uniform vec3 vh_sh8;
global uniform vec4 focus_box;    // interior focus: xz centre + half size of the entered building
global uniform float focus_amount;
global uniform float cut_height;

global uniform vec3 vh_sky_zenith;
global uniform vec3 vh_sky_upper;
global uniform vec3 vh_sky_mid_sun;
global uniform vec3 vh_sky_mid_away;
global uniform vec3 vh_sky_hor_sun;
global uniform vec3 vh_sky_hor_away;
global uniform vec3 vh_sky_halo;     // glow around the sun (or the moon)
global uniform vec3 vh_sky_ground;   // env-pass ground below the horizon
global uniform vec3 vh_sky_glow;     // light dome low over the capital (night)
global uniform vec2 vh_glow_dir;     // its azimuth, as a unit xz direction
global uniform float vh_night;       // 0 day / evening .. 1 night: stars, moon, fireflies
global uniform vec4 vh_glow;         // artificial light on: x LEDs + fixtures, y signs, z windows, w lamp halos + pools
global uniform vec3 vh_unlit;        // brightness of the unshaded water, spray and distant city
global uniform float vh_time;        // TIME for the sky shader (TIME there would re-render the radiance every frame)
global uniform vec3 vh_eye;          // the main camera (shadow passes have their own CAMERA_POSITION_WORLD)
global uniform vec3 vh_sun_light;    // the sun's LIGHT_COLOR (linear colour x intensity), for unshaded surfaces
global uniform vec4 vh_tree_lod;     // trees hand over to impostors: x..y m (clamp), z px per m at 1 m, w px per texel

vec3 vh_sky(vec3 d) {
	float y = max(d.y, 0.0);
	vec2 sh = normalize(vh_sun.xz);
	vec2 dh = normalize(d.xz + vec2(1e-5));
	float az = dot(dh, sh) * 0.5 + 0.5;
	vec3 hor = mix(vh_sky_hor_away, vh_sky_hor_sun, pow(clamp(az, 0.0, 1.0), 3.5));
	vec3 mid = mix(vh_sky_mid_away, vh_sky_mid_sun, pow(clamp(az, 0.0, 1.0), 2.2));
	vec3 c = mix(hor, mid, smoothstep(0.0, 0.14, y));
	c = mix(c, vh_sky_upper, smoothstep(0.08, 0.5, y));
	c = mix(c, vh_sky_zenith, smoothstep(0.4, 1.0, y));
	float sd = max(dot(d, vh_sun), 0.0);
	c += vh_sky_halo * (pow(sd, 5.0) * 0.32 + pow(sd, 32.0) * 0.55);
	c += vh_sky_glow * pow(max(dot(dh, vh_glow_dir), 0.0), 6.0) * exp(-y * 9.0);
	return c;
}

// The Compatibility renderer does no sRGB conversion on inputs or output: decode sRGB colours and
// textures here (three.js does it in hardware); the final screen pass applies ACES + sRGB encoding.
vec3 vh_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }

// What a shader outputs is not quite what lands in the HDR buffer: Godot 4.7's Compatibility scene and
// sky shaders take ALBEDO / EMISSION / COLOR as sRGB, decode them with a cubic fit (srgb_to_linear), add
// lights and FOG, then write linear_to_srgb (1.055 x^(1/2.4) - 0.055, clamped at 0). Over the mid tones
// the pair cancels, but near black it does not: everything under ~0.027 comes out 0 and the darks are
// pulled down, so night skies and shade would crush to black. vh_raw(c) is the value whose round trip
// gives c back exactly: invert linear_to_srgb, then the cubic (two Newton steps, starting above the root
// from the smaller of its quadratic-only and cubic-only solutions, both upper bounds; exact to half float).
vec3 vh_raw(vec3 c) {
	vec3 t = pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4));
	vec3 x = min((sqrt(0.000156823 + 2.728684444 * t) - 0.012522878) / 1.364342222, pow(t / 0.305306011, vec3(1.0 / 3.0)));
	for (int i = 0; i < 2; i++) {
		x -= (((0.305306011 * x + 0.682171111) * x + 0.012522878) * x - t) / ((0.915918033 * x + 1.364342222) * x + 0.012522878);
	}
	return x;
}

float vh_hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vh_vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(vh_hash12(i), vh_hash12(i + vec2(1.0, 0.0)), u.x), mix(vh_hash12(i + vec2(0.0, 1.0)), vh_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float vh_fbm5(vec2 p) {
	float s = 0.0, a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 5; i++) { s += a * vh_vnoise(p); p = m * p; a *= 0.5; }
	return s;
}
