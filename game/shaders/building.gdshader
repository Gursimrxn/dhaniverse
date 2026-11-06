shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

// Recolours the approved models' vertex colours into the brand palette:
// pale/cream surfaces -> this building's wall colour, charcoal -> plum ink,
// warm timber and saturated details kept but graded warm.
uniform vec3 wall : source_color = vec3(0.9, 0.6, 0.55);
uniform vec3 ink : source_color = vec3(0.16, 0.19, 0.24);
uniform vec3 roof : source_color = vec3(0.23, 0.26, 0.31);
uniform bool use_vcol = true;
uniform bool recolor = false;    // off: render the authored model colours as-is
uniform vec3 base : source_color = vec3(0.9);
uniform bool focused = false;     // this building is the one being entered
uniform float floor_y = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// cut away everything above the current floor while inside
	if (focused && wpos.y > cut_height) discard;

	vec3 src = use_vcol ? COLOR.rgb : base;
	float mx = max(src.r, max(src.g, src.b));
	float mn = min(src.r, min(src.g, src.b));
	float sat = (mx - mn) / max(mx, 0.001);
	float lum = dot(src, vec3(0.3, 0.55, 0.15));

	vec3 col = src;
	float pale = smoothstep(0.55, 0.7, lum) * (1.0 - smoothstep(0.12, 0.25, sat)) * float(use_vcol) * float(recolor);
	vec3 w = wall * (0.85 + lum * 0.2);
	// upward-facing pale surfaces are roofs/terraces
	w = mix(w, roof, smoothstep(0.75, 0.95, wnorm.y) * step(floor_y + 2.5, wpos.y));
	// pale floors indoors stay warm terrazzo, not wall paint
	float flr = smoothstep(0.8, 0.95, wnorm.y) * (1.0 - step(floor_y + 2.5, wpos.y));
	w = mix(w, vec3(0.84, 0.82, 0.78) * (0.85 + lum * 0.15), flr);
	col = mix(col, w, pale);
	float dark = 1.0 - smoothstep(0.12, 0.28, lum);
	col = mix(col, ink, dark * (1.0 - smoothstep(0.2, 0.4, sat)) * float(recolor));

	// soft ground contact
	col *= mix(0.72, 1.0, smoothstep(floor_y, floor_y + 1.2, wpos.y));
	col *= 1.0 - cloud_shadow(wpos) * 0.15;
	ALBEDO = focused ? col : apply_focus(col, wpos);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
