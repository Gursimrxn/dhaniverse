shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

uniform vec3 bark_dark : source_color = vec3(0.24, 0.17, 0.14);
uniform vec3 bark_light : source_color = vec3(0.46, 0.33, 0.25);
uniform vec3 moss : source_color = vec3(0.33, 0.5, 0.3);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// trunks lean gently with the crown
	float gust = fbm2(wpos.xz * 0.05 + TIME * 0.18);
	float h = max(0.0, VERTEX.y - 1.0);
	VERTEX.xz += vec2(1.0, 0.35) * (gust - 0.4) * 0.012 * h * h * wind_strength;
}

void fragment() {
	// vertical bark ridges + moss on the shaded side near the ground
	float ridges = vnoise(vec2(atan(wnorm.z, wnorm.x) * 4.0, wpos.y * 1.2));
	vec3 col = mix(bark_dark, bark_light, ridges * 0.7 + COLOR.r * 0.3);
	float m = smoothstep(0.2, -0.6, dot(wnorm, sun_dir)) * smoothstep(2.5, 0.3, wpos.y - COLOR.g);
	col = mix(col, moss, m * 0.6);
	ALBEDO = apply_focus(col, wpos);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
