// Shared look for every world shader: brand toon light, focus blackout, noise.
global uniform vec4 focus_sphere;   // xyz centre, w radius of the building being entered
global uniform float focus_amount;  // 0 = outdoors, 1 = inside (outside fades to night)
global uniform vec4 focus_box;      // xz centre + xz half size of the entered building
global uniform float cut_height;    // roof cut-away height while inside
global uniform vec3 sun_dir;        // towards the sun
global uniform vec3 player_pos;
global uniform float wind_strength;

const vec3 SHADOW_TINT = vec3(0.29, 0.42, 0.55);   // cool blue shade   // plum
const vec3 SUN_TINT = vec3(1.0, 0.95, 0.86);          // honey
const vec3 NIGHT = vec3(0.02, 0.035, 0.05);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
			mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.13 + 7.1) * 0.35;
}

// soft drifting cloud shadows over the town
float cloud_shadow(vec3 wp) {
	vec2 p = wp.xz * 0.018 + vec2(TIME * 0.012, TIME * 0.006);
	return smoothstep(0.42, 0.7, fbm2(p));
}

// 1 when this point should be swallowed by the interior blackout
float outside_focus(vec3 wp) {
	vec2 q = abs(wp.xz - focus_box.xy) - focus_box.zw;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	return focus_amount * smoothstep(-0.5, 1.5, d);
}

vec3 apply_focus(vec3 col, vec3 wp) {
	return mix(col, NIGHT, outside_focus(wp));
}

// Brand toon ramp: two soft bands, plum shadows instead of grey.
vec3 toon_diffuse(float ndl, float atten, vec3 light_col) {
	float lit = smoothstep(0.0, 0.18, ndl) * 0.55 + smoothstep(0.35, 0.6, ndl) * 0.45;
	lit *= atten;
	return light_col * lit / PI;
}

// Up to four extra characters (NPCs / other players) push foliage aside.
// xyz = feet position, w = push radius (0 = inactive). Set by the actor manager.
global uniform vec4 actor_a;
global uniform vec4 actor_b;
global uniform vec4 actor_c;
global uniform vec4 actor_d;

vec3 _push_one(vec3 root_w, vec4 a, float radius_default) {
	float r = a.w > 0.0 ? a.w : radius_default;
	vec3 away = root_w - a.xyz;
	float d = length(away.xz);
	float k = (1.0 - smoothstep(0.0, r, d)) * step(abs(away.y), 1.8);
	return normalize(vec3(away.x, 0.0, away.z) + 0.0001) * k;
}

// Combined sideways push (unit-ish) from the player + all actors at a root point.
vec3 actor_push(vec3 root_w, float radius) {
	vec3 p = _push_one(root_w, vec4(player_pos, radius), radius);
	if (actor_a.w > 0.0) p += _push_one(root_w, actor_a, radius);
	if (actor_b.w > 0.0) p += _push_one(root_w, actor_b, radius);
	if (actor_c.w > 0.0) p += _push_one(root_w, actor_c, radius);
	if (actor_d.w > 0.0) p += _push_one(root_w, actor_d, radius);
	float l = length(p);
	return l > 1.0 ? p / l : p;
}
