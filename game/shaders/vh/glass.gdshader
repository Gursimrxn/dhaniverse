shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// Dark mirror glazing: a near-black, almost opaque body under a coated surface (F0 `mirror`, rising to a full
// mirror at grazing angles) that reflects the world - the sky with its gradient and sun, the hazy line of the
// far woods and hills on the horizon, the dark ground below. Each pane sits a hair out of true, so the
// reflection breaks from pane to pane as on a real curtain wall. After dark (vh_glow.z) the panes show the
// rooms behind them lit low and warm: one light per 4 m room cell and storey, most on, a few off, some a
// cooler white, brightest under the ceiling.
uniform vec3 tint : source_color = vec3(0.105, 0.125, 0.137);   // #1b2023
uniform float opacity = 0.9;
uniform float mirror = 0.1;
uniform bool focused = false;
uniform float floor_y = 0.0;
uniform float window_energy = 0.5;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// What the glass mirrors in direction r (world).
vec3 world_env(vec3 r) {
	vec3 sky = vh_sky(vec3(r.x, max(r.y, 0.0), r.z));
	float az = atan(r.x, r.z);
	// the far tree line: a ragged band just over the horizon, hazed towards the sky colour
	float top = 0.035 + 0.045 * vh_vnoise(vec2(az * 9.0, 1.7)) + 0.02 * vh_vnoise(vec2(az * 61.0, 4.3));
	vec3 hor = vh_sky(vec3(r.x, 0.0, r.z));
	vec3 woods = mix(vec3(0.045, 0.06, 0.042) * (vh_indirect(vec3(0.0, 1.0, 0.0)) * 3.0 + 0.2), hor, 0.5);
	vec3 ground = mix(woods, vh_sky_ground * 1.6, smoothstep(0.0, 0.35, -r.y));
	vec3 env = mix(sky, woods, 1.0 - smoothstep(top - 0.012, top + 0.012, r.y));
	return r.y < 0.0 ? ground : env;
}

void fragment() {
	if (focused && wpos.y > cut_height) discard;
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 n = normalize(wn);
	// every pane (about 1.5 m) a little out of true
	vec3 cellp = floor(wpos / 1.5);
	vec2 wob = vec2(vh_hash12(cellp.xz + cellp.y * 7.1), vh_hash12(cellp.zy + cellp.x * 3.3)) - 0.5;
	vec3 t1 = normalize(abs(n.y) < 0.9 ? cross(n, vec3(0.0, 1.0, 0.0)) : vec3(1.0, 0.0, 0.0));
	vec3 nw = normalize(n + (t1 * wob.x + cross(n, t1) * wob.y) * 0.035);
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float nv = max(dot(nw, V), 0.0);
	float F = mirror + (1.0 - mirror) * pow(1.0 - nv, 5.0);
	ALBEDO = vh_lin(tint);
	ALPHA = focused ? 0.08 : mix(opacity, 1.0, F);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	vec3 em = vh_lin(tint) * vh_indirect(nw) * 0.35 * (1.0 - F);
	// a neutral-grey coating: it mirrors the world a little darker and cooler than it is, never sky-blue
	vec3 env = world_env(reflect(-V, nw));
	env = mix(vec3(dot(env, vec3(0.2126, 0.7152, 0.0722))), env, 0.55) * vec3(0.92, 0.95, 1.0);
	em += env * F;
	float win = focused ? 0.0 : vh_glow.z;
	if (win > 0.0) {
		float sy = (wpos.y - floor_y) / 3.3;
		vec3 cell = floor(vec3(wpos.x / 4.0, sy, wpos.z / 4.0));
		float h = vh_hash12(cell.xz + cell.y * 13.7);
		// skylights and glass roofs glow evenly; facades go room by room
		float on = abs(n.y) > 0.7 ? 0.3 : smoothstep(0.16, 0.26, h);
		vec3 warm = mix(vec3(1.0, 0.56, 0.24), vec3(1.0, 0.78, 0.52), vh_hash12(cell.xz * 1.7 + cell.y + 3.0));
		float glow = on * (0.65 + 0.35 * smoothstep(0.15, 0.95, fract(sy))) * (0.75 + 0.5 * fract(h * 7.31));
		em += warm * glow * win * window_energy * (1.0 - F * 0.6);
		ALPHA = mix(ALPHA, 1.0, clamp(glow * win, 0.0, 1.0));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, vh_sun_att(wpos, ATTENUATION), ROUGHNESS, d, s);
	vh_out(d * 0.2, s * 2.5, vh_alb, SPECULAR_LIGHT);
}
