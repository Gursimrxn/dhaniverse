// Butterflies round the flowering shrubs and blossom trees, all on the GPU: each instance (MODEL_MATRIX
// origin) is the bush it belongs to; INSTANCE_CUSTOM r: its own random, g: its species (0..4), b: how far it
// strays (m). It loops a wandering path round the bush, its heading following its flight, its two wings
// flapping on the body's axis, quick beats with now and then a glide. The wings are a shape, not a texture:
// a rounded forewing and a smaller hindwing, a dark rim and a pale spot, in the species' colours. Gone at
// night and past `far` metres. Mesh: two quads, x -1..0 the left wing, 0..1 the right, UV over each wing.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform float wingspan = 0.075;       // m, half a span (one wing)
uniform float far = 45.0;

varying vec2 v_uv;
varying float v_kind;
varying vec3 v_wp;

vec3 species(float k, float part) {
	// lemon, cabbage white, monarch orange, blue, rose
	vec3 base = k < 0.5 ? vec3(1.0, 0.88, 0.32) : k < 1.5 ? vec3(1.0, 0.98, 0.93) : k < 2.5 ? vec3(1.0, 0.56, 0.16)
		: k < 3.5 ? vec3(0.45, 0.72, 1.0) : vec3(1.0, 0.62, 0.8);
	vec3 rim = k < 1.5 ? vec3(0.32, 0.3, 0.28) : k < 2.5 ? vec3(0.12, 0.08, 0.06) : vec3(0.18, 0.2, 0.32);
	return part < 0.5 ? base : rim;
}

void vertex() {
	vec3 anchor = MODEL_MATRIX[3].xyz;
	float rnd = INSTANCE_CUSTOM.r;
	v_kind = INSTANCE_CUSTOM.g;
	float reach = INSTANCE_CUSTOM.b;
	float t = TIME * mix(0.35, 0.6, rnd) + rnd * 91.0;
	// a wandering loop: three incommensurate swings, so it never quite repeats
	vec3 p = vec3(sin(t * 1.0 + rnd * 6.0) + 0.35 * sin(t * 2.7), 0.0, cos(t * 1.3 + rnd * 3.0) + 0.35 * cos(t * 3.1));
	p.xz *= reach;
	p.y = 0.55 + 0.35 * sin(t * 1.9 + rnd * 4.0) + 0.12 * sin(t * 7.3);
	vec3 dp = vec3(cos(t + rnd * 6.0) + 0.945 * cos(t * 2.7), 0.0, -1.3 * sin(t * 1.3 + rnd * 3.0) - 1.085 * sin(t * 3.1)) * reach;
	vec3 fwd = normalize(vec3(dp.x, 0.0, dp.z) + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	// flapping: fast beats, gliding now and then with the wings half open
	float glide = smoothstep(0.6, 0.9, sin(t * 0.7 + rnd * 9.0));
	float flap = mix(sin(TIME * 22.0 + rnd * 40.0) * 1.1 + 0.25, 0.35, glide);
	float side = sign(VERTEX.x);
	float span = abs(VERTEX.x);
	// the wing turns up about the body's axis (fwd): out along right, up as it flaps
	vec3 wing = (right * side * cos(flap) + vec3(0.0, 1.0, 0.0) * sin(flap)) * span * wingspan + fwd * VERTEX.z * wingspan;
	// gone at night and far off
	float day = smoothstep(0.25, 0.5, clamp(dot(fol_sun, FOL_LUMA) / 4.5, 0.0, 1.0));
	float near = 1.0 - smoothstep(far * 0.8, far, distance(anchor, CAMERA_POSITION_WORLD));
	v_wp = anchor + p + wing * day * near;
	VERTEX = v_wp - anchor;
	v_uv = UV;
}

void fragment() {
	// UV: x out from the body (0) to the wingtip (1), y from the front (0) to the back (1)
	vec2 q = v_uv;
	float fore = length((q - vec2(0.42, 0.34)) / vec2(0.62, 0.36));
	float hind = length((q - vec2(0.3, 0.74)) / vec2(0.36, 0.28));
	float d = min(fore, hind);
	if (d > 1.0) discard;
	float rim = step(0.78, fore) * step(fore, hind);
	float spot = 1.0 - step(0.12, length(q - vec2(0.62, 0.3)));
	vec3 c = fol_lin(species(v_kind, rim));
	c = mix(c, vec3(1.0), spot * 0.8 * (1.0 - rim));
	c *= mix(0.78, 1.0, q.x);   // a little darker by the body
	ALBEDO = vh_fogged(c * FOL_WORLD_GAIN * 0.9, v_wp, CAMERA_POSITION_WORLD, 0.0);
}
