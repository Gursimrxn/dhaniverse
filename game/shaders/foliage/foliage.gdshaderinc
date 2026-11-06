// Cel shading, wind and seasons shared by trees, bushes and grass. Ported from just-a-simple-tree
// (shading.js, wind.js; MIT, Mike Fernandez), after trungduyng's Blender anime tree: a Lambert surface read
// back as a colour and pushed through a hard-edged colour ramp. The ramp picks its band from how bright the
// light is, and the band is tinted by the light's hue. Shadows tint the sunlight they block blue rather than
// greying it. Tone mapping (Khronos neutral) happens here, per material.
//
// How a material uses it: ALBEDO = 1 and nothing else in fragment(); light() works out the whole colour for
// the sun (fol_lit -> fol_cel -> fol_emit) and adds lamps plainly. The scene needs its directional light.

#include "res://shaders/vh/vh.gdshaderinc"

global uniform vec3 fol_sun;          // the sun's irradiance (linear colour x intensity)
global uniform vec3 fol_sun_dir;      // towards the sun, world space
global uniform vec3 fol_sky;          // hemisphere fill: from above
global uniform vec3 fol_ground;       // and from below
global uniform vec4 fol_shadow;       // rgb: what shadow tints the blocked sunlight to, a: how far (darkness)
global uniform vec4 fol_weather;
global uniform vec4 fol_occlude;      // xyz: the player (chest height), w: how wide a view to keep clear of leaves and roofs (0: off)      // scripts/world/weather.gd: x overcast, y wet, z snow, w mist (each 0..1)
global uniform float fol_dim;         // brightness of the cel-banded surfaces: 1 by day, less at night
global uniform float fol_season;      // the leaves' age through the year: 0 unfolding, 0.35 summer, turning, 1 bare
global uniform vec4 fol_wind;         // x: direction it blows towards (radians), y: strength (m), z: speed, w: gust frequency (1/m)
global uniform vec2 fol_wind_extra;   // x: how far each branch swings on its own, y: a gust on top (1 blows twice as hard)

const float FOL_ALBEDO = 0.8;
const vec3 FOL_LUMA = vec3(0.2126, 0.7152, 0.0722);

// Lambert under the lights (the albedo the ramps' band edges expect): sky fill, plus the sun when `sun` > 0
vec3 fol_lit(vec3 n_world, float ndl, float shadow) {
	vec3 hemi = mix(fol_ground, fol_sky, n_world.y * 0.5 + 0.5);
	vec3 tint = mix(mix(vec3(1.0), fol_shadow.rgb, fol_shadow.a), vec3(1.0), shadow);
	// overcast: the cloud takes most of the sun and spreads it as a greyer, fuller sky light with softer shade
	float oc = fol_weather.x;
	hemi = mix(hemi, vec3(dot(hemi, FOL_LUMA)) * 1.1, oc * 0.5) * (1.0 + oc * 0.9);
	tint = mix(tint, vec3(1.0), oc * 0.6);
	return FOL_ALBEDO / PI * (hemi + fol_sun * (1.0 - 0.72 * oc) * ndl * tint);
}

// Weather on a surface's colour: wet darkens what soaks it up (porous 0..1); snow settles on what faces up.
vec3 fol_wetted(vec3 c, float porous) { return c * mix(1.0, 0.68, fol_weather.y * porous); }
vec3 fol_snowy(vec3 c, vec3 n_world) {
	return mix(c, vec3(0.95, 0.97, 1.0), fol_weather.z * smoothstep(0.55, 0.9, n_world.y));
}

// Three colours from stops s0 = 0, s1, s2, held flat between (Blender's constant ramp), tinted by the light's hue
vec3 fol_cel(vec3 lit, vec3 c0, vec3 c1, vec3 c2, float s1, float s2) {
	float v = dot(lit, FOL_LUMA);
	vec3 tint = mix(vec3(1.0), lit / max(v, 1e-4), smoothstep(0.0, 0.02, v));
	vec3 band = mix(mix(c0, c1, step(s1, v)), c2, step(s2, v));
	return band * tint;
}

// Snow as a material of its own, cel lit like everything else (lit from fol_lit)
const vec3 FOL_SNOW = vec3(0.92, 0.95, 1.0);
vec3 fol_snow_lit(vec3 lit) { return fol_cel(lit, FOL_SNOW * 0.7, FOL_SNOW, FOL_SNOW * 1.05, 0.497, 0.955); }

vec3 fol_tonemap(vec3 color) {
	const float start = 0.76;
	const float desat = 0.15;
	float x = min(color.r, min(color.g, color.b));
	float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
	color -= offset;
	float peak = max(color.r, max(color.g, color.b));
	if (peak < start) return color;
	const float d = 1.0 - start;
	float np = 1.0 - d * d / (peak + d - start);
	color *= np / peak;
	float g = 1.0 - 1.0 / (desat * (peak - np) + 1.0);
	return mix(color, vec3(np), g);
}

// Colour in and out. source_color uniforms reach the shader unconverted here (dev/color_probe.gd), so the
// palette (sRGB) is linearised by hand. Everything is lit in light(): Godot Compatibility draws the shadowed
// sun in an additive pass that sRGB-encodes what light() adds (see vh_out in vh.gdshaderinc).
//   fol_display 1 (dev/foliage_lab): straight to the screen, so tone map and let the pass encode it.
//   fol_display 0 (the world): into the linear buffer the grade pass tone maps, so mix in the valley's
//   aerial perspective and hand it over pre-decoded, for the pass's encoding to give it back linear. The
//   grade (shaders/vh/grade.gdshader) runs three.js ACES, which boosts by 1 / 0.6 first: FOL_WORLD_GAIN
//   takes that back, so the palette lands near the colours it was picked as.
global uniform float fol_display;

const float FOL_WORLD_GAIN = 0.6;

vec3 fol_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }

vec3 fol_emit(vec3 c, vec3 wp, vec3 cam) {
	if (fol_display > 0.5) return fol_tonemap(c);
	vec4 f = vh_fog(wp, cam);
	f.a = 1.0 - (1.0 - f.a) * exp(-distance(wp, cam) * 0.02 * fol_weather.w);    // mist closes in
	c = mix(max(c, vec3(0.0)) * FOL_WORLD_GAIN, f.rgb, f.a);
	return pow((c + 0.055) / 1.055, vec3(2.4));
}

// Keep the player in sight from the high camera: whatever lies between the camera and the player, within
// fol_occlude.w of that line, dissolves in a screen-door dither (call in fragment(); true = discard).
bool fol_occludes(vec3 wp, vec3 cam, vec2 frag) {
	if (fol_occlude.w <= 0.0) return false;
	vec3 ab = fol_occlude.xyz - cam;
	float t = dot(wp - cam, ab) / max(dot(ab, ab), 1e-4);
	if (t > 0.96) return false;
	float d = distance(wp, cam + ab * clamp(t, 0.0, 1.0));
	float fade = 1.0 - smoothstep(fol_occlude.w * 0.55, fol_occlude.w, d);
	// 4x4 ordered dither
	ivec2 q = ivec2(mod(frag, 4.0));
	int i = q.x + q.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return fade * 0.92 > (m[i] + 0.5) / 16.0;
}

// --- wind ----------------------------------------------------------------------------------------------------
float fol_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Smooth value noise, about -0.5..0.5, standing in for the reference's Perlin noise
float fol_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(fol_hash(i), fol_hash(i + vec3(1, 0, 0)), f.x), mix(fol_hash(i + vec3(0, 1, 0)), fol_hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(fol_hash(i + vec3(0, 0, 1)), fol_hash(i + vec3(1, 0, 1)), f.x), mix(fol_hash(i + vec3(0, 1, 1)), fol_hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z) - 0.5;
}

vec3 fol_downwind() { return vec3(cos(fol_wind.x), 0.0, sin(fol_wind.x)); }
float fol_blowing() { return fol_wind.y * (1.0 + fol_wind_extra.y); }

// How far a point sways, world space: a noise field drifting downwind pushes it along the wind with a little
// turbulence, more the higher up it is (h: its height over the tree's). A breeze moves only the crown, a gale
// bends the whole tree. On top, each branch swings on its own by its flex (0..1) and beat (phase).
vec3 fol_sway(vec3 world, float h, float flex, float phase) {
	vec3 down = fol_downwind();
	float blowing = fol_blowing();
	vec3 drift = world * fol_wind.w - down * TIME * fol_wind.z;
	float gust = fol_noise(drift) + 0.6;
	vec3 turb = vec3(fol_noise(drift + 17.3), fol_noise(drift + 41.1), fol_noise(drift + 73.7)) * 0.35;
	float bend = pow(max(h, 0.0), 2.0 - clamp(blowing, 0.0, 1.0));
	vec3 across = vec3(-down.z, 0.0, down.x);
	float b0 = sin(TIME * 0.42 * TAU + phase) * 0.6;
	float b1 = sin(TIME * 0.31 * TAU + phase + 2.1) * 0.45;
	float b2 = sin(TIME * 0.57 * TAU + phase + 4.2) * 0.2;
	vec3 own = (down * (b0 + 0.4) + across * b1 + vec3(0.0, b2, 0.0)) * (flex * gust * blowing * fol_wind_extra.x);
	return (down * gust + turb) * bend * blowing + own;
}

// A world-space offset as model space, for VERTEX (the tree may be turned and scaled)
vec3 fol_to_model(mat4 model, vec3 world_offset) {
	return inverse(mat3(model)) * world_offset;
}
