shader_type spatial;
// Sunlit dust / pollen motes in a box that wraps around the camera (the prototype's SunlitMotes and
// TownAtmosphere AirborneMotes): each instance origin is a seed position, drifted slowly by the wind and
// folded into the box, so the field follows the player without any CPU work. Glows when backlit.
// With `fireflies` the box sits on the ground around the player instead and each mote wanders slowly
// and blinks yellow-green, faded in with the night (vh_night).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/vh/vh_sky.gdshaderinc"

global uniform vec3 player_pos;
uniform vec3 box = vec3(26.0, 9.0, 26.0);
uniform float size = 0.022;
uniform vec3 tint = vec3(1.0, 0.82, 0.56);   // linear
uniform bool fireflies = false;

varying float glow;
varying vec2 q;

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float k = fract(seed.x * 0.173 + seed.z * 0.291);
	vec3 p;
	vec3 v;
	float d;
	if (fireflies) {
		vec3 wander = vec3(sin(TIME * 0.31 + k * 40.0) + sin(TIME * 0.57 + k * 13.0) * 0.5, sin(TIME * 0.43 + k * 23.0) * 0.35,
			cos(TIME * 0.27 + k * 31.0) + cos(TIME * 0.61 + k * 7.0) * 0.5) * 1.6;
		vec3 c = player_pos + vec3(0.0, box.y * 0.5 + 0.25, 0.0);
		p = c + (fract((seed + wander - c) / box) - 0.5) * box;
		v = normalize(p - CAMERA_POSITION_WORLD);
		d = distance(p, player_pos);
		float flash = pow(max(sin(TIME * (0.9 + k * 1.3) + k * 60.0), 0.0), 8.0);
		glow = (0.04 + 2.2 * flash) * vh_night * (1.0 - smoothstep(box.x * 0.32, box.x * 0.5, d)) * smoothstep(2.5, 6.0, distance(p, CAMERA_POSITION_WORLD));
	} else {
		vec3 drift = vec3(vh_wind.x, 0.0, vh_wind.y) * TIME * (0.25 + k * 0.3)
			+ vec3(sin(TIME * 0.6 + k * 40.0), sin(TIME * 0.43 + k * 23.0) * 0.6, cos(TIME * 0.51 + k * 31.0)) * 0.6;
		vec3 cam = CAMERA_POSITION_WORLD + vec3(0.0, box.y * 0.2, 0.0);
		p = cam + (fract((seed + drift - cam) / box) - 0.5) * box;
		v = normalize(p - CAMERA_POSITION_WORLD);
		d = distance(p, CAMERA_POSITION_WORLD);
		glow = (0.06 + 2.4 * pow(max(dot(v, vh_sun), 0.0), 6.0)) * (1.0 - smoothstep(box.x * 0.3, box.x * 0.5, d)) * smoothstep(0.6, 2.0, d)
			* (0.5 + 0.5 * sin(TIME * (1.0 + k * 2.0) + k * 60.0)) * (1.0 - vh_night);
	}
	q = VERTEX.xy * 2.0;
	vec3 right = INV_VIEW_MATRIX[0].xyz, up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = p + (right * VERTEX.x + up * VERTEX.y) * size * (0.6 + k);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	float a = max(1.0 - dot(q, q), 0.0);
	ALBEDO = vh_raw(tint * glow * a * a);
}
