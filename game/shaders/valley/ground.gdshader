// The valley's ground (shaders/foliage/ground.gdshader, made cheaper for the valley: the flagstones are a
// baked tiling texture, assets/valley/flagstones.png, and the ground's colour is worked out once in fragment()
// and handed to light(), not again there). In the foliage's cel look (shaders/foliage): no photo textures, flat painted colours
// through the same three-band ramp and blue shadow tint as the trees and grass. Displaced on the GPU from
// the height field and split by slope / height above water / noise as shaders/vh/terrain.gdshaderinc does:
//   meadow  the meadow's own colour field (meadow.gdshaderinc), the one the blades on it show
//   clay    soft warm earth on the steep cuts only (never mud); ordinary slopes stay meadow
//   rock    a soft lavender grey on the steepest
//   sand    pale and warm along the water, cooler and darker where it is wet
//   paths   cream flagstones (a Voronoi of stones with soft grout) and a lighter rim where they meet grass
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"
#include "res://shaders/foliage/meadow.gdshaderinc"

uniform sampler2D field_tex : filter_linear, repeat_disable;   // r height, g water sd, b water level
uniform sampler2D paved_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paved_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 texel = vec2(0.0025, 0.0025);
uniform float cell = 2.0;

uniform vec3 meadow : source_color = vec3(0.302, 0.592, 0.322);      // #4d9752, the trees' mid green
uniform vec3 meadow_sun : source_color = vec3(0.459, 0.69, 0.353);   // #75b05a, the sunnier patches
uniform vec3 clay : source_color = vec3(0.776, 0.647, 0.514);        // #c6a583, soft and warm
uniform vec3 rock : source_color = vec3(0.682, 0.659, 0.749);       // #aea8bf
uniform vec3 sand : source_color = vec3(0.922, 0.835, 0.651);       // #ebd5a6
uniform vec3 stone : source_color = vec3(0.925, 0.871, 0.776);      // #ecdec6
uniform vec3 grout : source_color = vec3(0.773, 0.698, 0.596);      // #c5b298

varying vec3 v_wp;
varying vec3 v_n;
varying vec4 v_splat;     // meadow, clay, rock, sand
varying float v_level;

float hgt(vec2 uv) { return textureLod(field_tex, uv, 0.0).r; }
float snoise(vec2 p) { return vh_vnoise(p) * 2.0 - 1.0; }

uniform sampler2D flag_tex : filter_linear_mipmap, repeat_enable;   // r: edge distance / 0.5, g: the stone's random (8 x 8 stones a tile)

// Flagstones: distance to the nearest stone's edge (F2 - F1, in stones) and that stone's own random
vec2 flags(vec2 p) {
	vec4 t = texture(flag_tex, p / 8.0);
	return vec2(t.r * 0.5, t.g);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (w.xz - map_rect.xy) / map_rect.zw;
	vec4 f = textureLod(field_tex, uv, 0.0);
	float hl = hgt(uv - vec2(texel.x, 0.0)), hr = hgt(uv + vec2(texel.x, 0.0));
	float hu = hgt(uv - vec2(0.0, texel.y)), hd = hgt(uv + vec2(0.0, texel.y));
	VERTEX.y = f.r - UV2.y * 2.5;
	v_n = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	NORMAL = v_n;
	v_wp = vec3(w.x, f.r, w.z);
	v_level = f.b;
	float slope = 1.0 - v_n.y;
	float above = f.r - f.b;
	float n1 = snoise(w.xz * 0.07 + vec2(5.2, -1.3));
	float rk = smoothstep(0.3, 0.4, slope + n1 * 0.05);
	float sd = 1.0 - smoothstep(0.15, 0.6 + n1 * 0.2, above);
	float cl = smoothstep(0.2, 0.26, slope + n1 * 0.03) * 0.9;
	v_splat = vec4((1.0 - rk) * (1.0 - sd) * (1.0 - cl), (1.0 - rk) * (1.0 - sd) * cl, rk, (1.0 - rk) * sd);
}

// The ground's colour here (linear), before light. meadow_w: how much of it is lawn, which takes the meadow's
// own colour field and light (meadow.gdshaderinc), as the grass blades on it do; meadow_c: that colour
vec3 ground_col(vec3 cam, out float pav, out float meadow_w, out vec3 meadow_c) {
	vec3 p = v_wp;
	vec4 s = v_splat;
	// crisp, painted borders rather than blends: each layer wins where it is the most
	float wobble = snoise(p.xz * 0.6) * 0.08;
	vec4 w = vec4(s.x, s.y + wobble, s.z - wobble, s.w + wobble * 0.5);
	float best = max(max(w.x, w.y), max(w.z, w.w));
	vec4 pick = step(vec4(best - 1e-4), w);
	pick /= max(dot(pick, vec4(1.0)), 1.0);
	vec3 c = fol_lin(meadow) * pick.x + fol_lin(clay) * pick.y + fol_lin(rock) * pick.z + fol_lin(sand) * pick.w;
	// wet along the water: cooler and darker, a sharp line
	float above = p.y - v_level;
	float wet = step(above, 0.12) * (1.0 - pick.z);
	c = mix(c, fol_lin(sand) * vec3(0.55, 0.62, 0.66), wet);
	// the paths: flagstones with soft grout, and a pale rim where they meet the grass
	float pv = texture(paved_tex, (p.xz - paved_rect.xy) / paved_rect.zw).r + snoise(p.xz * 0.9) * 0.06;
	pav = step(0.45, pv);
	vec2 fl = flags(p.xz * 1.6);
	vec3 st = fol_lin(stone) * (0.94 + 0.1 * fl.y);
	st = mix(fol_lin(grout), st, smoothstep(0.04, 0.11, fl.x));
	c = mix(c, st, pav);
	float rim = step(0.36, pv) * (1.0 - pav);
	c = mix(c, mix(fol_lin(stone), fol_lin(meadow_sun), 0.35), rim);
	// under the water: sunk into the river's colour
	float under = clamp(-above, 0.0, 4.0);
	c *= exp(-under * vec3(0.5, 0.3, 0.32));
	// the lawn: the meadow's field, as dark as the blades' roots near by, as the blades on average far off
	float dist = distance(p, cam);
	meadow_w = pick.x * (1.0 - pav) * (1.0 - wet) * (1.0 - rim);
	meadow_c = meadow_col(p.xz, dist * 0.0012) * mix(0.74, 0.93, smoothstep(14.0, 50.0, dist));
	return c;
}

varying vec3 v_gc;     // the ground's colour, worked out once in fragment()
varying vec3 v_mc;
varying float v_pav;
varying float v_mw;

void fragment() {
	vh_clip(v_wp, CAMERA_POSITION_WORLD);
	ALBEDO = vec3(1.0);
	float pav, mw;
	vec3 mc;
	v_gc = ground_col(CAMERA_POSITION_WORLD, pav, mw, mc);
	v_mc = mc;
	v_pav = pav;
	v_mw = mw;
	// the street lamps' pools of light at night (added as the VH surfaces add them)
	if (vh_night > 0.02) EMISSION = vh_raw(vh_lamps(v_wp, v_n, CAMERA_POSITION_WORLD, 0.9, mix(v_gc, mc, mw), 0.0) * FOL_WORLD_GAIN);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float pav = v_pav, mw = v_mw;
		vec3 mc = v_mc;
		vec3 c = fol_wetted(v_gc, 0.55 + 0.45 * pav);
		vec3 lit = fol_lit(v_n, max(dot(NORMAL, LIGHT), 0.0), ATTENUATION);
		vec3 cel = fol_cel(lit, c * 0.62, c, c * 1.1, 0.497, 0.955) * fol_dim;
		// the lawn: its field's colour, the shadows soft on it, the hills' slopes reading a little
		float relief = 0.82 + 0.18 * clamp(dot(normalize(v_n), fol_sun_dir) * 1.4, 0.0, 1.0);
		vec3 lawn = meadow_light(fol_wetted(mc, 0.4), ATTENUATION) * relief;
		vec3 g = mix(cel, lawn, mw);
		// snow settles on what faces up, white at the light it lies in
		float snow = fol_weather.z * smoothstep(0.55, 0.9, normalize(v_n).y) * mix(1.0, 0.3, pav);   // paths are swept
		g = mix(g, fol_snow_lit(lit), snow);
		DIFFUSE_LIGHT += fol_emit(g, v_wp, INV_VIEW_MATRIX[3].xyz);
	}
}
