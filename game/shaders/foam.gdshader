shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
#include "res://shaders/common.gdshaderinc"

// Flat foam disc on a PlaneMesh of size 2 (local xz in -1..1).
// Used for the churning pool under a waterfall and for ripple rings around rocks.
uniform vec3 foam_col : source_color = vec3(1.0, 1.0, 0.97);
uniform float inner = 0.35;     // radius (0..1) where the rock / impact edge sits
uniform float churn = 1.0;      // dense boiling foam patches (waterfall pool)
uniform float rings = 0.6;      // expanding ripple rings strength
uniform float opacity = 0.9;

varying vec3 wpos;
varying vec2 lp;
varying float phase;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = VERTEX.xz;
	phase = hash12(floor(MODEL_MATRIX[3].xz * 3.0)) * 6.28;
}

void fragment() {
	float r = length(lp);
	float t = (r - inner) / max(1.0 - inner, 0.01);   // 0 at edge, 1 at rim
	if (r > 1.0 || t < -0.05) discard;

	// boiling foam: noise pushed outwards from the centre
	vec2 dir = lp / max(r, 0.001);
	vec2 q = lp * 4.0 - dir * TIME * 1.1 + phase;   // seamless, drifts outwards
	float n = fbm2(q * 1.6) * 0.7 + vnoise(wpos.xz * 3.0 + TIME * 0.4) * 0.3;
	float hug = 1.0 - smoothstep(0.0, 0.35 + n * 0.25, t);          // tight band at the edge
	float patches = smoothstep(0.52, 0.6, n + (1.0 - t) * 0.55 - 0.42) * churn;

	// thin expanding rings
	float w = fract(t * 1.6 - TIME * 0.35 + phase);
	float ring = smoothstep(0.0, 0.05, w) * (1.0 - smoothstep(0.05, 0.14, w));
	ring *= (1.0 - t) * rings * smoothstep(0.35, 0.6, vnoise(dir * 2.0 + TIME * 0.3 + phase) + 0.3);

	float a = max(max(hug * 0.95, patches), ring) * (1.0 - smoothstep(0.75, 1.0, r));
	ALBEDO = apply_focus(foam_col, wpos);
	ALPHA = clamp(a, 0.0, 1.0) * opacity;
}
