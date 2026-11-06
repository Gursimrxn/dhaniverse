// River water in the foliage's painted look: clear in the shallows (the sand bed shows through, bent a
// little by the ripples), deepening in soft bands from aqua to teal; a wobbly foam line where it meets the
// bank and foam streaks drifting with the current; sparkles towards the sun; the sky's colour at grazing
// angles. Unshaded, one pass. Replaces shaders/vh/water.gdshader on the river ribbons (UV2 = flow, m/s).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 shallow : source_color = vec3(0.494, 0.89, 0.843);   // #7ee3d7
uniform vec3 mid : source_color = vec3(0.235, 0.71, 0.737);       // #3cb5bc
uniform vec3 deep : source_color = vec3(0.141, 0.459, 0.584);     // #247595
uniform vec3 foam : source_color = vec3(0.98, 0.965, 0.902);      // #faf6e6
uniform vec3 sky_tint : source_color = vec3(0.769, 0.953, 0.992); // #c4f3fd
uniform vec2 foam_center = vec2(0.0, -10000.0);                  // the foot of the falls: churned white

varying vec3 wpos;
varying vec2 flow;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = UV2;
}

float vn(vec2 p) { return vh_vnoise(p); }

void fragment() {
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec2 fl = flow * TIME;
	// ripples: two noises drifting with the current, for the bending, the streaks and the sparkles
	float r1 = vn(wpos.xz * 0.9 - fl * 1.1);
	float r2 = vn(wpos.xz * 2.3 + vec2(3.1, 7.7) - fl * 1.7);
	vec2 bendv = (vec2(r1, r2) - 0.5) * 0.012;
	// how deep the water is along the view, from the depth buffer
	vec2 suv = SCREEN_UV + bendv;
	float d_raw = texture(depth_tex, suv).r;
	vec4 bed_v = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, d_raw * 2.0 - 1.0, 1.0);
	bed_v.xyz /= bed_v.w;
	float thick = max(length(bed_v.xyz) - length(VERTEX), 0.0);
	vec3 Vw = normalize(CAMERA_POSITION_WORLD - wpos);
	float depth = thick * max(Vw.y, 0.25);   // about how far down the bed is
	// the water's colour in soft bands, the bed showing through the shallows
	vec3 c = mix(fol_lin(shallow), fol_lin(mid), smoothstep(0.25, 0.55, depth));
	c = mix(c, fol_lin(deep), smoothstep(1.0, 1.6, depth));
	c *= FOL_WORLD_GAIN;
	vec3 bed = texture(screen_tex, suv).rgb;
	float clear = 1.0 - smoothstep(0.05, 0.9, depth);
	c = mix(c, bed * mix(vec3(1.0), fol_lin(shallow) * 1.2, 0.5), clear * 0.65);
	// grazing: the sky's colour coming in towards the far reaches
	float fres = pow(1.0 - max(Vw.y, 0.0), 4.0);
	c = mix(c, fol_lin(sky_tint) * FOL_WORLD_GAIN, smoothstep(0.15, 0.7, fres) * 0.45);
	float near = 1.0 - smoothstep(25.0, 60.0, length(VERTEX));   // foam detail fades with distance
	// foam: a wobbly line along the bank, streaks along the current, white water under the falls
	float edge = 0.12 + 0.1 * vn(wpos.xz * 1.7 - fl * 0.6);
	float line = step(depth, edge) * step(0.02, thick) * mix(0.5, 1.0, near);
	vec2 fd = normalize(flow + vec2(1e-5, 0.0));
	vec2 q = vec2(dot(wpos.xz, fd) * 0.22, dot(wpos.xz, vec2(-fd.y, fd.x)) * 1.6);
	float streak = step(0.9, vn(q - vec2(TIME * length(flow) * 0.22, 0.0))) * step(0.5, r2) * near;
	float falls = 1.0 - smoothstep(4.0, 14.0, distance(wpos.xz, foam_center));
	float fm = max(max(line, streak * 0.7), step(0.55 - falls * 0.5, r1 * r2 * 2.0) * falls);
	c = mix(c, fol_lin(foam) * FOL_WORLD_GAIN, fm);
	// sparkles towards the sun
	vec3 H = normalize(Vw + fol_sun_dir);
	float spark = step(0.86, r2) * step(0.6, r1) * pow(max(dot(normalize(vec3(r1 - 0.5, 4.0, r2 - 0.5)), H), 0.0), 30.0);
	c += vec3(spark) * 2.0 * FOL_WORLD_GAIN * clamp(fol_sun_dir.y * 3.0, 0.0, 1.0);
	ALBEDO = vh_fogged(c, wpos, CAMERA_POSITION_WORLD, 0.0);
	ALPHA = 1.0;
}
