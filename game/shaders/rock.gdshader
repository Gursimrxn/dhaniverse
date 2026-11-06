shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

// Stylized river boulder: moss on up-facing faces, cool grey sides, wet band at the water line.
uniform float water_level = 0.0;
uniform vec3 moss_light : source_color = vec3(0.373, 0.561, 0.271);  // #5f8f45
uniform vec3 moss_dark : source_color = vec3(0.247, 0.42, 0.208);    // #3f6b35
uniform vec3 stone_light : source_color = vec3(0.639, 0.655, 0.651); // #a3a7a6
uniform vec3 stone_dark : source_color = vec3(0.435, 0.467, 0.51);   // #6f7782
uniform float moss_amount = 0.5;   // 0 = bare, 1 = heavy moss
uniform float brightness = 0.5;   // albedo scale so the palette lands right under the bright brand light

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float big = fbm2(wpos.xz * 0.9 + wpos.y * 0.7);
	float fine = vnoise(wpos.xz * 6.0 + wpos.yy * 5.0);

	// stone: light on top half of the side, darker towards the ground, soft mottling
	float up = n.y * 0.5 + 0.5;
	vec3 stone = mix(stone_dark, stone_light, smoothstep(0.1, 0.8, up + (big - 0.5) * 0.5));
	stone *= 0.92 + fine * 0.12;

	// moss caps: on up-facing faces, broken by noise, never under water
	float m = smoothstep(0.95 - moss_amount * 0.3, 1.05 - moss_amount * 0.3, n.y + (big - 0.5) * 0.45 + (fine - 0.5) * 0.1);
	m *= smoothstep(water_level + 0.15, water_level + 0.45, wpos.y);
	vec3 moss = mix(moss_dark, moss_light, smoothstep(0.3, 0.8, big + fine * 0.3));
	vec3 col = mix(stone, moss, m);

	// wet band just above the water, darker + tinted below it
	float above = wpos.y - water_level;
	float wet = 1.0 - smoothstep(0.0, 0.32 + big * 0.18, above);
	col *= 1.0 - wet * 0.38;
	float sub = smoothstep(0.0, -0.4, above);
	col = mix(col, col * vec3(0.55, 0.8, 0.78), sub);

	col *= brightness;
	col *= 1.0 - cloud_shadow(wpos) * 0.18;
	ALBEDO = apply_focus(col, wpos);
	ROUGHNESS = mix(1.0, 0.45, wet);
	EMISSION = col * 0.9 * (1.0 - focus_amount);   // cheap sky bounce: keeps shade soft, not navy
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
