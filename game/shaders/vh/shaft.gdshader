shader_type spatial;
// Sunbeams through the tree crowns (daylight): one strip per instance, hung from a point inside a crown
// and running down along the sunlight (vh_light) to the ground, turned about its own axis to face the
// camera so it never shows edge-on. Additive, soft across and at both ends, the gap in the leaves
// opening and closing with the wind, dust drifting down it, brighter looking towards the sun.
// Instance origin = the beam's top; INSTANCE_CUSTOM = (height above the ground, half width, phase, -).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://shaders/vh/vh.gdshaderinc"

global uniform vec4 vh_shafts;        // rgb = beam colour x strength (0 = off)

varying vec2 q;          // x across -1..1, y along 0 (top) .. 1 (ground)
varying float k;
varying vec3 wpos;

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	vec3 top = MODEL_MATRIX[3].xyz;
	vec3 L = -normalize(vh_light);
	float len = cu.x / max(-L.y, 0.25);
	float along = 0.5 - VERTEX.y;
	vec3 axis = top + L * (len * along);
	vec3 side = normalize(cross(L, CAMERA_POSITION_WORLD - axis));
	wpos = axis + side * (VERTEX.x * 2.0 * cu.y * (0.7 + 0.6 * along));
	q = vec2(VERTEX.x * 2.0, along);
	k = cu.z;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}

void fragment() {
	float across = exp(-q.x * q.x * 3.5);
	float ends = smoothstep(0.0, 0.3, q.y) * (1.0 - smoothstep(0.55, 1.0, q.y));
	float gap = clamp(0.5 + 0.8 * sin(TIME * 0.6 + k * 40.0) * sin(TIME * 0.23 + k * 17.0), 0.0, 1.0);
	float dust = 0.75 + 0.25 * vh_vnoise(vec2(q.x * 2.5 + k * 9.0, q.y * 7.0 - TIME * 0.35));
	vec3 V = normalize(wpos - CAMERA_POSITION_WORLD);
	// dust scatters forward: beams stand out looking into the light, and all but vanish looking down-sun
	float phase = 0.1 + 1.9 * pow(max(dot(V, normalize(vh_light)), 0.0), 4.0);
	float near = smoothstep(2.0, 7.0, distance(wpos, CAMERA_POSITION_WORLD));
	float fog = vh_fog(wpos, CAMERA_POSITION_WORLD).a;
	ALBEDO = vh_raw(vh_shafts.rgb * (across * ends * gap * dust * phase * near * (1.0 - fog) * (1.0 - focus_amount)));
}
