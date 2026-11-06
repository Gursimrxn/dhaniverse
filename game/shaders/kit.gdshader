shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

// Procedural architecture kit (scripts/kit). Colour comes straight from vertex
// colour (already linear); UV.x carries a 0..1 sway weight for cloth / leaves.
uniform float sway = 0.0;       // metres of cloth/leaf flutter at weight 1
uniform float emissive = 0.0;   // lamp glass glow
uniform float grain = 0.06;     // subtle world-space value noise so flat colours read as material

varying vec3 wpos;
varying float hgt;

void vertex() {
	vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway > 0.0) {
		float ph = TIME * 2.1 + w0.x * 0.9 + w0.z * 0.6;
		float k = UV.x * sway * wind_strength;
		VERTEX.y += (sin(ph) * 0.7 + sin(ph * 2.3 + 1.7) * 0.3) * k;
		VERTEX.x += sin(ph * 0.7 + 0.4) * k * 0.4;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = VERTEX.y;
}

void fragment() {
	vec3 col = COLOR.rgb;
	col *= 1.0 - grain + grain * 2.0 * fbm2(wpos.xz * 2.7 + wpos.y * 3.1);
	col *= mix(0.78, 1.0, smoothstep(-0.05, 0.9, hgt));   // soft ground contact
	col *= 1.0 - cloud_shadow(wpos) * 0.15;
	ALBEDO = apply_focus(col, wpos);
	EMISSION = col * emissive * (1.0 - focus_amount * 0.5);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
