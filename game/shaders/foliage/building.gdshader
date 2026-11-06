// Buildings in the foliage's painted look (shaders/foliage): the same cel light, blue-tinted shadows and
// aerial perspective as the trees and ground, so the town reads as one place. No weathering of any kind:
// no grime, moss, streaks or dirt. Each surface is a part (site.gd part_for, from its material name in the
// quarter's GLBs) painted in its site's colour; the two retained masters, whose surfaces are not named,
// are sorted into parts by their authored vertex colours as shaders/vh/building.gdshader sorted them.
// Close up, each part shows gentle detail that fades with distance: a soft mottle on render, rounded
// joints between stone blocks, the boards of timber, courses of roof tiles. Glass is a dark sky-tinted
// surface with a soft highlight, and after dark some windows glow warm from the rooms behind them.
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"


const int P_WALL = 0;
const int P_TRIM = 1;
const int P_FRAME = 2;
const int P_ROOF = 3;
const int P_WOOD = 4;
const int P_STONE = 5;
const int P_METAL = 6;
const int P_CANVAS = 7;
const int P_PLANT = 8;
const int P_LIGHT = 9;
const int P_GLASS = 10;
const int P_AUTHORED = 11;
const int P_BY_COLOUR = -1;

uniform int part = -1;
uniform vec3 col : source_color = vec3(0.945, 0.922, 0.878);   // this part's colour (sRGB), named parts
uniform vec3 base : source_color = vec3(0.9);                  // a surface's own colour when it has no vertex colours
uniform bool use_vcol = false;
// the site's palette, for the parts sorted by colour (sRGB)
uniform vec3 pal_wall : source_color = vec3(0.945, 0.922, 0.878);
uniform vec3 pal_trim : source_color = vec3(0.847, 0.808, 0.737);
uniform vec3 pal_frame : source_color = vec3(0.227, 0.239, 0.251);
uniform vec3 pal_roof : source_color = vec3(0.298, 0.325, 0.349);
uniform vec3 pal_wood : source_color = vec3(0.69, 0.514, 0.353);
uniform vec3 glass_tint : source_color = vec3(0.17, 0.21, 0.25);
uniform vec3 glow_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float glow_energy = 2.5;
uniform bool focused = false;
uniform float floor_y = 0.0;
uniform vec3 int_lo = vec3(100000.0);
uniform vec3 int_hi = vec3(-100000.0);

varying vec3 v_wp;
varying vec3 v_nw;
varying vec3 v_col;       // the part's colour (linear)
varying float v_part;     // the part, for its surface detail

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nw = normalize(mat3(MODEL_MATRIX) * NORMAL);
	int p = part;
	vec3 c = fol_lin(col);
	if (p == P_BY_COLOUR) {
		// the retained masters: sort the authored colour into wall, trim, frame, timber or a colour kept
		// as it is (plants, fittings), each class repainted in the site's palette keeping its light-dark steps
		vec3 src = use_vcol ? COLOR.rgb : fol_lin(base);
		float Y = dot(src, FOL_LUMA);
		float mx = max(src.r, max(src.g, src.b));
		float sat = (mx - min(src.r, min(src.g, src.b))) / max(mx, 1e-4);
		float green = smoothstep(1.12, 1.3, src.g / max(src.r, 1e-4)) * smoothstep(1.1, 1.3, src.g / max(src.b, 1e-4));
		float keep = max(smoothstep(0.7, 0.8, sat), green);
		float timber = smoothstep(2.6, 3.2, src.r / max(src.b, 1e-3)) * (1.0 - smoothstep(0.42, 0.5, Y));
		vec4 cls = vec4(smoothstep(0.6, 0.64, Y), 0.0, 1.0 - smoothstep(0.12, 0.2, Y), 0.0);
		cls.y = max(1.0 - cls.x - cls.z, 0.0);
		cls = vec4(cls.xyz * (1.0 - timber), timber);
		float pitched = smoothstep(0.3, 0.45, v_nw.y) * step(2.2, v_wp.y - floor_y);
		float top = smoothstep(0.86, 0.94, v_nw.y) * smoothstep(int_hi.y - 1.9, int_hi.y - 1.3, v_wp.y);
		float roof = max(cls.z * pitched, (cls.x + cls.y) * top) * (1.0 - keep);
		c = cls.x * fol_lin(pal_wall) * clamp(Y / 0.68, 0.88, 1.08)
			+ cls.y * fol_lin(pal_trim) * clamp(Y / 0.5, 0.85, 1.1)
			+ cls.z * fol_lin(pal_frame) * clamp(Y / 0.07, 0.85, 1.15)
			+ cls.w * fol_lin(pal_wood) * clamp(Y / 0.22, 0.9, 1.2);
		c = mix(c, fol_lin(pal_roof), roof);
		vec3 calm = mix(src, vec3(Y) * vec3(1.05, 1.0, 0.93), 0.6);
		c = mix(c, mix(calm, src, green), keep);
		p = roof > 0.5 ? P_ROOF : (cls.w > 0.5 ? P_WOOD : (cls.z > 0.5 ? P_FRAME : P_WALL));
		if (keep > 0.5) p = P_AUTHORED;
	} else if (p == P_AUTHORED || p == P_LIGHT) {
		c = use_vcol ? COLOR.rgb : fol_lin(base);
	} else if (p == P_GLASS) {
		c = fol_lin(glass_tint);
	}
	v_col = c;
	v_part = float(p);
}

// Surface detail as a brightness multiplier, near the camera only. u runs along the wall, v up it.
float detail(int p, vec3 wp, vec3 n, float dist) {
	float k = 1.0 - smoothstep(22.0, 55.0, dist);
	if (k <= 0.0) return 1.0;
	vec3 t = normalize(abs(n.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : cross(vec3(0.0, 1.0, 0.0), n));
	float u = dot(wp, t);
	float v = wp.y;
	float m = 1.0;
	if (p == P_WALL || p == P_TRIM) {
		m = 1.0 + (vh_vnoise(vec2(u, v) * 0.35 + wp.xz * 0.05) - 0.5) * 0.06;
	} else if (p == P_STONE) {
		float row = floor(v / 0.3);
		float uu = u / 0.6 + 0.5 * mod(row, 2.0);
		vec2 f = vec2(fract(uu) * 0.6, fract(v / 0.3) * 0.3);
		float edge = min(min(f.x, 0.6 - f.x), min(f.y, 0.3 - f.y));
		m = mix(0.8, 1.0, smoothstep(0.008, 0.03, edge)) * (0.95 + 0.1 * vh_hash12(vec2(floor(uu), row)));
	} else if (p == P_WOOD) {
		float b = u / 0.14;
		m = mix(0.86, 1.0, smoothstep(0.02, 0.07, min(fract(b), 1.0 - fract(b)))) * (0.94 + 0.12 * vh_hash12(vec2(floor(b), 3.0)));
	} else if (p == P_ROOF) {
		float row = floor(v / 0.12);
		m = mix(0.84, 1.0, smoothstep(0.0, 0.25, fract(v / 0.12))) * (0.95 + 0.1 * vh_hash12(vec2(floor(u / 0.3 + 0.5 * row), row)));
	}
	return mix(1.0, m, k);
}

void fragment() {
	if (focused && v_wp.y > cut_height) discard;
	if (fol_occludes(v_wp, CAMERA_POSITION_WORLD, FRAGCOORD.xy)) discard;
	vh_clip(v_wp, CAMERA_POSITION_WORLD);
	int p = int(round(v_part));
	vec3 n = normalize(v_nw);
	float dist = distance(v_wp, CAMERA_POSITION_WORLD);
	float m = detail(p, v_wp, n, dist);
	if (p == P_GLASS) {
		// a soft highlight from the sky, brighter towards the top of each pane's storey
		m = 1.0 + 0.5 * smoothstep(0.2, 1.0, fract((v_wp.y - floor_y) / 3.3)) * (1.0 - abs(n.y));
	}
	ALBEDO = vec3(m);
	// after dark: lamps and fittings glow, and the rooms behind some windows are lit
	float night = clamp(vh_night, 0.0, 1.0);
	vec3 em = vec3(0.0);
	if (p == P_LIGHT) em = v_col * glow_energy * night;
	if (p == P_GLASS) {
		float room = vh_hash12(floor(v_wp.xz / 4.0) + floor((v_wp.y - floor_y) / 3.3) * 7.3);
		em = fol_lin(glow_color) * 0.45 * step(0.35, room) * night;
	}
	em += vh_lamps(v_wp, n, CAMERA_POSITION_WORLD, 0.9, v_col, 0.0);
	EMISSION = vh_raw(em * FOL_WORLD_GAIN);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 c = v_col;
		if (int(round(v_part)) == P_GLASS) {
			// glass is mostly the sky it reflects, darker in a building's shade; not banded like a wall
			vec3 sky = fol_sky * 0.55;
			c = mix(c, sky, 0.45) * mix(0.75, 1.0, ATTENUATION);
			DIFFUSE_LIGHT += fol_emit(c, v_wp, INV_VIEW_MATRIX[3].xyz);
		} else {
			vec3 lit = fol_lit(normalize(v_nw), max(dot(NORMAL, LIGHT), 0.0), ATTENUATION);
			c = fol_snowy(fol_wetted(c, 0.45), normalize(v_nw));
			DIFFUSE_LIGHT += fol_emit(fol_cel(lit, c * 0.62, c, c * 1.08, 0.497, 0.955), v_wp, INV_VIEW_MATRIX[3].xyz);
		}
	}
}
