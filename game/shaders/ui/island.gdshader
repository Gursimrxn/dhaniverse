shader_type canvas_item;
// The island (scripts/ui/island.gd): the pill, the round lobe a moment splits off it, and the glance's card, as one signed distance
// with a smooth union, so they join with a liquid neck the way the board's goo filter joins them. The cream ring is an outer band of
// the same distance, the drop shadow is the distance again, offset and softened. Sizes are pixels in this rect.

uniform vec2 size;
uniform vec3 lobe;                      // centre, radius; radius 0: no lobe
uniform vec4 pill;                      // x, y, w, h: a capsule
uniform vec4 card;                      // x, y, w, h; h 0: no card
uniform float card_r;
uniform float k = 18.0;                 // how far the union reaches across a gap
uniform float ring = 3.0;
uniform vec4 body : source_color = vec4(0.149, 0.153, 0.153, 1.0);
uniform vec4 cream : source_color = vec4(1.0, 0.973, 0.89, 1.0);
uniform vec4 lobe_fill : source_color = vec4(0.0);   // alpha: how much of it shows
uniform float sheen = 0.0;              // the brand gradient over the ring, as a moment opens
uniform vec2 shadow_at = vec2(0.0, 8.9);
uniform float shadow_blur = 14.0;
uniform float shadow_a = 0.35;

const vec3 BRAND[7] = { vec3(1.0, 0.925, 0.741), vec3(1.0, 0.4, 0.0), vec3(0.898, 0.18, 0.996), vec3(0.439, 0.475, 1.0), vec3(0.455, 0.737, 0.871), vec3(0.631, 1.0, 0.706), vec3(1.0, 0.925, 0.741) };

float box(vec2 p, vec4 r, float round_by) {
	vec2 half_size = r.zw * 0.5;
	vec2 q = abs(p - r.xy - half_size) - half_size + round_by;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - round_by;
}

float smin(float a, float b) {
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

float shape(vec2 p) {
	float d = box(p, pill, min(pill.z, pill.w) * 0.5);
	if (lobe.z > 0.0) d = smin(d, length(p - lobe.xy) - lobe.z);
	if (card.w > 0.0) d = smin(d, box(p, card, min(card_r, min(card.z, card.w) * 0.5)));
	return d;
}

// CSS conic-gradient(from 90deg, ...): it starts at the right and goes clockwise, round each shape's own middle
vec3 conic(vec2 p, vec2 c) {
	float f = fract(atan(p.y - c.y, p.x - c.x) / 6.2831853) * 6.0;
	int i = int(min(floor(f), 5.0));
	return mix(BRAND[i], BRAND[i + 1], f - float(i));
}

void fragment() {
	float faded = COLOR.a;              // the node's modulate: the opening fades the plates in
	vec2 p = UV * size;
	float d = shape(p);
	float inner = clamp(0.5 - d, 0.0, 1.0);
	float outer = clamp(0.5 - (d - ring), 0.0, 1.0);
	float shade = shadow_a * (1.0 - smoothstep(-shadow_blur * 0.5, shadow_blur, shape(p - shadow_at) - ring));
	vec3 rc = cream.rgb;
	if (sheen > 0.0) {
		bool near_lobe = lobe.z > 0.0 && length(p - lobe.xy) - lobe.z < box(p, pill, pill.w * 0.5);
		rc = mix(rc, conic(p, near_lobe ? lobe.xy : pill.xy + pill.zw * 0.5), sheen);
	}
	vec3 col = mix(rc, body.rgb, inner);
	if (lobe.z > 0.0) col = mix(col, lobe_fill.rgb, clamp(0.5 - (length(p - lobe.xy) - lobe.z), 0.0, 1.0) * lobe_fill.a);
	float a = outer + shade * (1.0 - outer);
	COLOR = vec4(a > 0.0 ? col * outer / a : col, a * faded);
}
