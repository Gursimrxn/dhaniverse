shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// distant.ts city: lavender-steel massing lit by the low sun, warm rim toward the sun, faint floor
// bands, then dissolved by the same aerial perspective as everything else. body / sun tint follow the
// time of day; at night the towers go dark and their windows light up (averaged: out there a window is
// far below a pixel), floor bands and towers each with their own share of rooms still lit.
uniform vec3 body = vec3(0.50, 0.52, 0.70);
uniform vec3 sun_tint = vec3(1.25, 0.8, 0.6);

varying vec3 vn;
varying vec3 vc;
varying vec3 wpos;

void vertex() {
	vn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vc = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(vn);
	vec3 sdh = normalize(vec3(vh_sun.x, 0.0, vh_sun.z));
	vec3 base = body * vc;
	vec3 col = base * (0.55 + 0.25 * n.y + 0.2 * max(dot(n, sdh), 0.0));
	float ndl = max(dot(n, normalize(vec3(vh_light.x, 0.25, vh_light.z))), 0.0);
	col += base * sun_tint * ndl * 0.55;
	float rim = pow(1.0 - abs(n.y), 2.0) * max(dot(n, sdh), 0.0);
	col += vec3(0.9, 0.62, 0.48) * rim * 0.25 * (sun_tint / 1.25);
	col *= 0.88 + 0.22 * smoothstep(0.0, 900.0, wpos.y);
	col *= 1.0 - step(0.55, fract(wpos.y / 5.0)) * 0.035;
	if (vh_night > 0.0) {
		vec2 tower = floor(wpos.xz / 24.0);
		float share = 0.3 + 0.35 * vh_hash12(vec2(floor(wpos.y / 15.0) * 0.37, 1.0) + tower * 1.31);
		vec3 win = mix(vec3(1.0, 0.66, 0.34), vec3(0.72, 0.84, 1.0), step(0.7, vh_hash12(tower + 7.0)));
		float lit = (1.0 - abs(n.y)) * share * (0.6 + 0.4 * step(0.55, fract(wpos.y / 5.0)));
		col = mix(col, col * 0.04 + win * lit * 0.3, vh_night);
	}
	ALBEDO = vh_fogged(col, wpos, CAMERA_POSITION_WORLD, vh_outside(wpos));
}
