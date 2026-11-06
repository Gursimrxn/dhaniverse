// Grass on the GPU field lattice (field.gdshaderinc, scripts/world/grass_builder.gd), or wildflowers with
// FLOWER defined.
// The blades are built as just-a-simple-tree builds them (grass.js; MIT, Mike Fernandez, after the grass of
// Bruno Simon's Portfolio2024): each a strip of three segments bent along a bezier from its root to a tip
// leaning forward, tapering with an ease-out, turned any way round, leant downwind by the gusts, and widened
// along the camera's right as it turns edge on, so a blade never thins to a flickering line. The mesh only
// carries each blade's root in its clump (VERTEX.xz), where it is along the strip (UV) and three randoms
// (COLOR); the shader builds the rest.
// Their colour is the meadow's (meadow.gdshaderinc), the same field the ground under them shows, darker at the
// root, lighter at the tip, the shadows lying on it softly. Where characters walk the blades are pushed aside
// and stand back up (fol_trails, scripts/foliage/grass_trails.gd), as Dylearn's grass bends from its characters.
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"
#include "res://shaders/foliage/meadow.gdshaderinc"
#include "res://shaders/field.gdshaderinc"

global uniform vec3 player_pos;
global uniform sampler2D fol_trails;     // 32 x 1: (x, y, z, age 0..1) where characters walked
uniform float target_density = 14.0;     // clumps per m2 next to the camera
uniform float near_full = 16.0;
uniform float max_dist = 70.0;
uniform float blade_height = 0.15;       // m: ankle to shin on the 1.4 m figure (the reference's 0.34 suits its 5 m tree, not a town)
uniform float blade_width = 0.03;
uniform float clump_spread = 0.3;        // m: how far a clump's blades stand from its lattice point

varying vec3 v_wp;
varying vec3 v_col;
#ifdef FLOWER
varying vec3 v_petal;
varying float v_is_petal;
#endif

float sn(vec2 p) { return vh_vnoise(p) * 2.0 - 1.0; }

// How far the walked trails push a blade rooted at x, and which way (the push's length up to 1)
uniform bool trails = true;              // bends where characters walked (the near ring only; the far rings skip the loop)
vec2 trail_push(vec2 x, float root_y) {
	vec2 push = vec2(0.0);
	if (!trails || distance(x, player_pos.xz) > 16.0) return push;   // trails are near the player
	for (int i = 0; i < 32; i++) {
		vec4 t = texelFetch(fol_trails, ivec2(i, 0), 0);
		vec2 d = x - t.xz;
		float r = length(d);
		float reach = mix(0.85, 0.6, t.w);
		if (r > reach || abs(root_y - t.y) > 1.4) continue;
		float k = (1.0 - smoothstep(0.1, reach, r)) * pow(1.0 - t.w, 2.0);
		push += d / max(r, 0.02) * k;
	}
	float l = length(push);
	return l > 1.0 ? push / l : push;
}

vec3 turn(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

float ease_out3(float x) { float b = 1.0 - x; return 1.0 - b * b * b; }
float ease_out4(float x) { float b = 1.0 - x; return 1.0 - b * b * b * b; }

vec3 bezier(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
	float u = 1.0 - t;
	return p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t;
}

void vertex() {
	vec3 hs;
	vec4 fp = field_place(MODEL_MATRIX[3].xyz, NODE_POSITION_WORLD, hs);
	vec4 h2 = fract(hs.xyzx * vec4(97.13, 61.71, 43.37, 29.93) + hs.yzxy * 7.31);
	float camD = distance(CAMERA_POSITION_WORLD.xz, fp.xz);
	float f = camD < near_full ? 1.0 : pow(near_full / camD, 1.8);
	float keep = fp.w * step(h2.w, target_density * f * spacing * spacing);
	// blades sink into the ground (which shows the same colour) as the field ends, rather than popping out
	float fullness = 1.0 - smoothstep(max_dist * 0.55, max_dist, camD);
	float px = camD * 0.0012;               // about the metres a pixel covers there
	vec3 down = fol_downwind();
#ifdef FLOWER
	keep *= step(h2.x, smoothstep(0.35, 0.65, sn(fp.xz * 0.11 + vec2(40.0, -12.0))));
	float ci = sn(fp.xz * 0.02 + vec2(-5.0, 8.0)) > 0.35 ? 2.0 + floor(h2.y * 2.999) : floor(h2.y * 1.999);
	// the palette's flowers: cream, white, marigold, lilac, poppy red (the anime meadow's)
	v_is_petal = step(0.9, COLOR.r * COLOR.g * COLOR.b);
	v_petal = ci < 0.5 ? vec3(1.0, 0.96, 0.84) : ci < 1.5 ? vec3(1.0, 1.0, 0.97) : ci < 2.5 ? vec3(1.0, 0.72, 0.2) : ci < 3.5 ? vec3(0.76, 0.66, 0.98) : vec3(0.93, 0.23, 0.16);
	float h = (0.17 + h2.z * 0.1) * fullness;
	float gT = clamp(VERTEX.y, 0.0, 1.0);
	float rot = hs.x * TAU;
	vec3 t = VERTEX;
	t.xz *= 1.0 + camD * 0.012;
	t.y *= h;
	t.xz = vec2(cos(rot) * t.x - sin(rot) * t.z, sin(rot) * t.x + cos(rot) * t.z);
	float gust = fol_noise(vec3(fp.x, 0.0, fp.z) * fol_wind.w * 8.0 - down * TIME * fol_wind.z * 2.0) + 0.6;
	vec2 bend = down.xz * max(gust, 0.0) * fol_blowing() * gT * gT * h + trail_push(fp.xz, fp.y) * 0.9 * gT * h;
	t.xz += bend;
	t.y -= dot(bend, bend) * 0.5 / max(h, 0.05);
	VERTEX = t * keep + (vec3(fp.x, fp.y - 0.03, fp.z) - MODEL_MATRIX[3].xyz);
	v_col = meadow_col(fp.xz, px) * 0.8;
#else
	// this blade: its root in the clump (turned with the clump), where along the strip, its own randoms
	float ca = cos(hs.x * TAU), sa = sin(hs.x * TAU);
	vec2 root = fp.xz + vec2(ca * VERTEX.x - sa * VERTEX.z, sa * VERTEX.x + ca * VERTEX.z) * (clump_spread / 0.3);
	vec3 base = vec3(root.x, fp.y - 0.02, root.y);
	float side = UV.x;
	float up = UV.y;
	vec3 r = fract(COLOR.rgb + hs);
	// taller in long-grass patches
	float tall = mix(0.85, 1.3, smoothstep(-0.35, 0.55, sn(root * 0.045 + vec2(7.0, 0.0))));
	float height = blade_height * tall * mix(0.75, 1.25, r.x) * fullness * keep * (1.0 - 0.75 * fol_weather.z);
	float width = blade_width * ease_out3(1.06 - up) * mix(0.8, 1.2, r.y) * (1.0 + camD * 0.02);
	// wind: a noise field smaller than the trees' gusts, drifting downwind, leans the blades along it; each
	// blade also leans its own way and rocks a little
	vec3 drift = vec3(root.x, 0.0, root.y) * fol_wind.w * 8.0 - down * TIME * fol_wind.z * 2.0;
	float gust = max(fol_noise(drift) + 0.6, 0.0);
	float blowing = fol_blowing() * 1.3;
	float blow = min(gust * blowing * 3.0, 1.3) * up;
	float rock = sin(TIME * fol_wind.z * 5.0 + r.z * TAU) * blowing * 0.25;
	float lean = (r.z - 0.5) * 0.6 + rock;
	vec3 curve = bezier(vec3(0.0), vec3(0.0, 0.33, 0.0), vec3(0.0, 0.66, 0.0), vec3(0.0, cos(lean), sin(lean)), up);
	vec3 local = vec3((side - 0.5) * width, curve.y * height, curve.z * height);
	float yaw = r.x * 37.0 + r.y * 11.0;
	vec3 wind_axis = normalize(cross(vec3(0.0, 1.0, 0.0), down));
	vec3 blade = turn(turn(local, vec3(0.0, 1.0, 0.0), yaw), wind_axis, blow) + base;
	// walked through: pressed down and aside, standing back up as the trail ages
	vec2 push = up > 0.01 ? trail_push(root, fp.y) * 1.1 * up * up * height : vec2(0.0);   // roots never move
	blade.xz += push;
	blade.y -= dot(push, push) * 0.5 / max(height, 0.05);
	// seen edge on a blade is a line: widen it along the camera's right as it turns away
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - base);
	vec3 face = turn(turn(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), yaw), wind_axis, blow);
	float facing = dot(face, to_cam);
	float thicken = ease_out4(1.0 - abs(facing)) * smoothstep(0.0, 0.2, abs(facing));
	blade += INV_VIEW_MATRIX[0].xyz * thicken * (side - 0.5) * width * 0.5 * sign(facing + 1e-4);
	VERTEX = blade - MODEL_MATRIX[3].xyz;
	// the meadow's colour where it roots, darker at the root (as the anime grass multiplies its hair's
	// position along it in), lifting towards the tip
	vec3 c = meadow_col(root, px);
	c *= mix(0.62, 1.0, pow(up, 0.7));
	v_col = mix(c, c * 1.12 + vec3(0.02, 0.025, 0.0), up * up * up * 0.6);
#endif
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vh_clip(v_wp, CAMERA_POSITION_WORLD);
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);   // lit as the ground is
	ALBEDO = vec3(1.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
#ifdef FLOWER
		vec3 c = mix(v_col, fol_lin(v_petal) * 0.85, v_is_petal);
#else
		vec3 c = v_col;
#endif
		vec3 lit = meadow_light(fol_wetted(c, 0.4), ATTENUATION);
		// snow: the blades take the snow's white at the light they stand in (the meadow field sets their colour)
		vec3 up_lit = fol_lit(vec3(0.0, 1.0, 0.0), max(fol_sun_dir.y, 0.0), ATTENUATION);
		lit = mix(lit, fol_snow_lit(up_lit), fol_weather.z * 0.9);
		DIFFUSE_LIGHT += fol_emit(lit, v_wp, INV_VIEW_MATRIX[3].xyz);
	}
}
