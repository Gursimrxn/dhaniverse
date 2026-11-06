shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"
// The town's surfaces: shaders/vh/pbr.gdshader, plus rooms. Inside a walk-in building (a box, set from
// world.gd's ROOMS) the sky's blue fill fades out for a warm indoor light, a little stronger on what faces up, so a
// room reads lit from within by day and at night. Direct sun still comes in through its openings and glass.
uniform vec4 room_lo[9];            // xyz: the room's low corner, w: how much sky light stays (a glass roof keeps more)
uniform vec4 room_hi[9];            // xyz: the high corner, w: how bright its light is (0: no room)
uniform vec3 room_light : source_color = vec3(1.0, 0.8, 0.58);

// MeshStandardMaterial equivalent for props: colour (x vertex/instance colour), roughness, metalness. (shaders/vh/pbr.gdshader's
// triplanar texture and flat shading are left out: nothing in the town uses them, and they made the shader slow to compile on the web.)
uniform vec3 albedo : source_color = vec3(1.0);
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform bool use_vcol = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 col = vh_lin(albedo);
	if (use_vcol) col *= COLOR.rgb;
	vec3 n = normalize(wn);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	float in_room = 0.0;
	float sky_keep = 1.0;
	float warm = 0.0;
	for (int i = 0; i < 9; i++) {
		if (room_hi[i].w <= 0.0) continue;
		vec3 q = max(room_lo[i].xyz - wpos, wpos - room_hi[i].xyz);
		float k = 1.0 - smoothstep(-0.5, 0.0, max(q.x, max(q.y, q.z)));
		if (k > in_room) { in_room = k; sky_keep = room_lo[i].w; warm = room_hi[i].w; }
	}
	vec3 indoor = vh_lin(room_light) * warm * (0.72 + 0.28 * n.y);
	vec3 fill = mix(vh_indirect(n), vh_indirect(n) * sky_keep + indoor, in_room);
	vec3 em = col * fill * (1.0 - metal) + vh_lin(emission_color) * emission_energy;
	em += vh_ibl_spec(NORMAL, VIEW, rough, mix(vec3(0.04), col, metal), INV_VIEW_MATRIX) * mix(1.0, sky_keep, in_room);
	em += vh_lamps(wpos, n, CAMERA_POSITION_WORLD, rough, col * (1.0 - metal), 0.0);
	vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
	vh_alb = ALBEDO;
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0);
	vec3 s = vec3(0.0);
	float att = vh_sun_att(wpos, ATTENUATION);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, att, ROUGHNESS, d, s);
	// metals reflect in their own colour (f0 = albedo); vh_direct assumes f0 = 0.04
	vh_out(d * (1.0 - metal), s * mix(vec3(1.0), vh_alb / 0.04, metal), vh_alb, SPECULAR_LIGHT);
}
