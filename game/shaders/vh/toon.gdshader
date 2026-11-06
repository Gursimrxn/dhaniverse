shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

// The player's soft toon look (the old StandardMaterial3D: toon diffuse at roughness 1, rim 0.35 tint
// 0.6) on the valley's light: the sun / moon wraps softly round the body, the sky fills the shade, the
// lamps reach it at night, and a sky-coloured rim keeps the silhouette readable in any light.
uniform vec3 albedo : source_color = vec3(1.0);
uniform float rim = 0.35;
uniform float rim_tint = 0.6;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 col = vh_lin(albedo);
	vec3 n = normalize(wn);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	vec3 em = col * vh_indirect(n) * 1.15;
	em += vh_lamps(wpos, n, CAMERA_POSITION_WORLD, 0.9, col, 0.35);
	float r = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5);
	em += mix(vec3(1.0), col, rim_tint) * vh_sky_sh(normalize(n + vec3(0.0, 0.6, 0.0))) * (r * rim * 1.6);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	float wrap = smoothstep(-1.0, 1.0, dot(NORMAL, LIGHT));
	vh_out(LIGHT_COLOR * (vh_sun_att(wpos, ATTENUATION) * wrap / PI), vec3(0.0), vh_alb, SPECULAR_LIGHT);
}
