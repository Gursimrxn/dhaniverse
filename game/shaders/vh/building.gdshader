shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/vh/vh.gdshaderinc"

// The approved building masters, each repainted in its own palette and given real surfaces, lit like the
// reference's architecture (PBR, sky light, sun, aerial perspective). Keeps the interior cut-away.
// The authored vertex colours sort into classes - light walls, mid trims, near-black frames and roofs,
// timber, and designed colours (plants, signs, fixtures) that stay as they are - and every class takes the
// building's own colour for it (site.gd STYLES), keeping the authored light-dark steps within the class.
// The facade class is laid in the building's own surface (render, brick, lap siding, panels, ashlar, board
// and batten, tiles) with box-filtered joints, relief and unit-to-unit variation; roofs get tiles or a
// membrane, timber its boards and grain. Weathering: grime at the foot of the walls, rain streaks, mottling,
// moss on masonry in the shade. Light: sunlight bounced off the ground (vh_bounce), contact darkening at the
// foot of the walls and in the joints, matte render, satin timber, a sheen on the frames and metal.
// After dark (vh_glow) uplights wash the facade in the building's colour, fixtures glow, the lettering
// lights up like channel letters, and a dim ceiling light warms the ground floor (every floor once the
// player is inside).
global uniform vec3 vh_bounce;    // sunlight bounced off the ground onto a wall (irradiance / PI, linear)

uniform bool use_vcol = true;
uniform vec3 base : source_color = vec3(0.9);
uniform bool focused = false;     // this building is the one being entered
uniform int kind = 0;             // 0 painted (sorted by colour), 2 timber, 3 metal, 4 render, 5 as authored
uniform int glow_kind = 0;        // 0 surface, 1 light fixture (glows in its own colour), 2 lettering
uniform vec3 glow_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float glow_energy = 3.0;
uniform vec3 int_lo = vec3(100000.0);   // the building's box (world) for its interior light (none by default)
uniform vec3 int_hi = vec3(-100000.0);
uniform float floor_y = 0.0;
uniform float int_energy = 1.0;
uniform vec3 int_color : source_color = vec3(1.0, 0.8, 0.58);
// the building's palette and facade (site.gd STYLES)
uniform vec3 pal_wall : source_color = vec3(0.86, 0.85, 0.8);
uniform vec3 pal_trim : source_color = vec3(0.74, 0.73, 0.68);
uniform vec3 pal_accent : source_color = vec3(0.45, 0.5, 0.52);
uniform vec3 pal_roof : source_color = vec3(0.56, 0.58, 0.6);
uniform vec3 pal_wood : source_color = vec3(0.72, 0.53, 0.34);
uniform vec3 pal_wash : source_color = vec3(1.0, 0.85, 0.62);
uniform int facade = 0;           // 0 render, 1 brick, 2 lap siding, 3 panels, 4 ashlar, 5 board and batten, 6 tiles
uniform int facade_on = 0;        // the class laid in it: 0 the walls, 1 the trims
uniform sampler2D t_noise : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wn;

// Irradiance / PI from a warm ceiling light over each room: it hangs 2.7 m above the floor of the
// fragment's storey, pulled a third of the way towards the middle and kept 1 m inside the walls, so
// floors and inner walls catch it while outer faces (turned away from it) stay dark.
vec3 interior(vec3 p, vec3 n) {
	float k = vh_glow.z * int_energy * (focused ? 2.4 : 1.0);
	if (k <= 0.0) return vec3(0.0);
	if (any(lessThan(p.xz, int_lo.xz - 0.3)) || any(greaterThan(p.xz, int_hi.xz + 0.3))) return vec3(0.0);
	float fh = 3.3;
	float lvl = floor((p.y - floor_y) / fh);
	if (lvl < 0.0 || (!focused && lvl > 0.0)) return vec3(0.0);
	vec2 q = mix(clamp(p.xz, int_lo.xz + 1.0, int_hi.xz - 1.0), (int_lo.xz + int_hi.xz) * 0.5, 0.33);
	vec3 dl = vec3(q.x, floor_y + lvl * fh + 2.7, q.y) - p;
	float d2 = dot(dl, dl);
	float nl = max(dot(n, dl * inversesqrt(max(d2, 1e-4))), 0.0);
	float room = 0.7 + 0.3 * vh_hash12(floor(p.xz / 6.0) + lvl * 7.3);
	return vh_lin(int_color) * (k * nl * room / ((1.0 + 0.09 * d2) * PI));
}

// Share of [x - w/2, x + w/2] lying in joints of width j centred on multiples of p (box-filtered, so
// joints thinner than a pixel fade to their average instead of shimmering).
float joint(float x, float p, float j, float w) {
	w = max(w, 1e-4);
	vec2 a = (vec2(-0.5, 0.5) * w + x + 0.5 * j) / p;
	vec2 i = floor(a) * j + min(fract(a) * p, j);
	return (i.y - i.x) / w;
}

// Joint coverage of the facade at q (metres: x along the wall, y up from the floor) for filter widths w;
// tone = the brick's / board's / panel's own shade (-1..1), already faded where units shrink under a pixel.
float facade_j(vec2 q, vec2 w, int s, out float tone) {
	tone = 0.0;
	float wm = max(w.x, w.y);
	if (s == 1) {                     // brick, running bond: 215 x 65 mm, 10 mm joints
		float row = floor(q.y / 0.075);
		float x = q.x + mod(row, 2.0) * 0.1125;
		float jy = joint(q.y, 0.075, 0.01, w.y);
		float jx = mix(joint(x, 0.225, 0.01, w.x), 0.044, smoothstep(0.02, 0.05, w.y));
		tone = (vh_hash12(vec2(floor(x / 0.225), row)) * 2.0 - 1.0) * (1.0 - smoothstep(0.03, 0.07, wm));
		return 1.0 - (1.0 - jx) * (1.0 - jy);
	} else if (s == 2) {              // lap siding: 180 mm boards, a shadow line under each
		float row = floor(q.y / 0.18);
		tone = (vh_hash12(vec2(row, floor(q.x / 4.8 + vh_hash12(vec2(row, 3.0))))) * 2.0 - 1.0) * (1.0 - smoothstep(0.06, 0.14, wm));
		return joint(q.y, 0.18, 0.016, w.y);
	} else if (s == 3) {              // panels 1.2 x 0.6 m, 8 mm open joints
		tone = (vh_hash12(floor(q / vec2(1.2, 0.6))) * 2.0 - 1.0) * (1.0 - smoothstep(0.2, 0.5, wm));
		return 1.0 - (1.0 - joint(q.x, 1.2, 0.008, w.x)) * (1.0 - joint(q.y, 0.6, 0.008, w.y));
	} else if (s == 4) {              // ashlar: 0.4 m courses of 0.5-0.9 m blocks, 8 mm joints
		float row = floor(q.y / 0.4);
		float len = 0.5 + 0.4 * vh_hash12(vec2(row, 7.0));
		float x = q.x + vh_hash12(vec2(row, 1.0)) * len;
		float jx = mix(joint(x, len, 0.008, w.x), 0.008 / len, smoothstep(0.1, 0.25, w.y));
		tone = (vh_hash12(vec2(floor(x / len), row)) * 2.0 - 1.0) * (1.0 - smoothstep(0.1, 0.25, wm));
		return 1.0 - (1.0 - jx) * (1.0 - joint(q.y, 0.4, 0.008, w.y));
	} else if (s == 5) {              // board and batten: 50 mm battens every 0.3 m (raised)
		tone = (vh_hash12(vec2(floor(q.x / 0.3), 1.0)) * 2.0 - 1.0) * (1.0 - smoothstep(0.06, 0.15, wm));
		return joint(q.x, 0.3, 0.05, w.x);
	} else if (s == 6) {              // tiles 0.3 x 0.15 m, 4 mm joints
		tone = (vh_hash12(floor(q / vec2(0.3, 0.15))) * 2.0 - 1.0) * (1.0 - smoothstep(0.05, 0.12, wm));
		return 1.0 - (1.0 - joint(q.x, 0.3, 0.004, w.x)) * (1.0 - joint(q.y, 0.15, 0.004, w.y));
	}
	return 0.0;
}

// Night uplights at the foot of the outer walls, every 3.6 m: each throws a cone that widens and fades up
// the wall. Only on faces near the building's shell and turned out of it.
float wash(vec3 p, vec3 n, float u, float h) {
	if (vh_glow.x <= 0.0 || abs(n.y) > 0.5 || h < 0.0) return 0.0;
	vec2 c = (int_lo.xz + int_hi.xz) * 0.5;
	vec2 q = abs(p.xz - c) - (int_hi.xz - int_lo.xz) * 0.5;
	float shell = smoothstep(-1.8, -1.0, max(q.x, q.y)) * step(0.0, dot(n.xz, p.xz - c));
	float du = (fract(u / 3.6) - 0.5) * 3.6;
	float sig = 0.16 + h * 0.27;
	return exp(-du * du / (2.0 * sig * sig)) * smoothstep(0.0, 0.3, h) / (1.0 + h * h * 0.1) * shell * vh_glow.x;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	if (focused && wpos.y > cut_height) discard;
	vh_clip(wpos, CAMERA_POSITION_WORLD);
	vec3 src = use_vcol ? COLOR.rgb : vh_lin(base);
	vec3 n = normalize(wn);
	float h = wpos.y - floor_y;
	float dist = distance(wpos, CAMERA_POSITION_WORLD);
	// --- the authored colour's class: x light walls, y mid trims, z near-black frames / roofs, w timber
	float Y = dot(src, vec3(0.2126, 0.7152, 0.0722));
	float mx = max(src.r, max(src.g, src.b));
	float sat = (mx - min(src.r, min(src.g, src.b))) / max(mx, 1e-4);
	float green = smoothstep(1.12, 1.3, src.g / max(src.r, 1e-4)) * smoothstep(1.1, 1.3, src.g / max(src.b, 1e-4));
	float keep = kind == 5 ? 1.0 : max(smoothstep(0.7, 0.8, sat), green);
	float timber = smoothstep(2.6, 3.2, src.r / max(src.b, 1e-3)) * (1.0 - smoothstep(0.42, 0.5, Y));
	vec4 cls = vec4(smoothstep(0.6, 0.64, Y), 0.0, 1.0 - smoothstep(0.12, 0.2, Y), 0.0);
	cls.y = max(1.0 - cls.x - cls.z, 0.0);
	cls = vec4(cls.xyz * (1.0 - timber), timber);
	if (kind == 2) cls = vec4(0.0, 0.0, 0.0, 1.0);
	if (kind == 4) cls = vec4(1.0, 0.0, 0.0, 0.0);
	// roofs: dark pitched or high surfaces, and flat tops near the top of the building
	float pitched = smoothstep(0.3, 0.45, n.y) * step(2.2, h);
	float top = smoothstep(0.86, 0.94, n.y) * smoothstep(int_hi.y - 1.9, int_hi.y - 1.3, wpos.y);
	float roof = max(cls.z * pitched, (cls.x + cls.y) * top) * (1.0 - keep);
	// --- repaint, keeping the authored steps within each class
	vec3 col = cls.x * vh_lin(pal_wall) * clamp(Y / 0.68, 0.85, 1.12)
		+ cls.y * vh_lin(pal_trim) * clamp(Y / 0.5, 0.8, 1.15)
		+ cls.z * vh_lin(pal_accent) * clamp(Y / 0.07, 0.8, 1.2)
		+ cls.w * vh_lin(pal_wood) * clamp(Y / 0.22, 0.85, 1.3);
	col = mix(col, vh_lin(pal_roof) * mix(1.0, clamp(Y / 0.5, 0.85, 1.12), cls.y), roof);
	// colours kept as authored: plants stay green; any other strong colour (fins, panels, awnings) is calmed
	// to a soft, slightly warm tone of the same lightness so no surface shouts
	float ky = dot(src, vec3(0.2126, 0.7152, 0.0722));
	vec3 calm = mix(src, vec3(ky) * vec3(1.05, 1.0, 0.93), 0.72);
	col = mix(col, kind == 5 ? src : mix(calm, src, green), keep);
	float rough = mix(dot(cls, vec4(0.9, 0.82, 0.46, 0.64)), 0.74, roof);
	vec3 f0 = vec3(0.04);
	if (kind == 3) {                  // bare metal: tinted, sheened reflections
		rough = 0.36;
		f0 = mix(vec3(0.04), col, 0.55);
	}
	rough = mix(rough, 0.6, keep);
	// --- surface: facade units and joints, roof tiles / membrane, timber boards; relief from the joints
	bool wall = abs(n.y) < 0.7;
	vec3 T = wall ? normalize(vec3(n.z, 0.0, -n.x)) : vec3(1.0, 0.0, 0.0);
	vec3 B = wall ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
	vec2 q = vec2(dot(wpos, T), wall ? h : wpos.z);   // metres: along the wall and up it, or x and z
	vec2 fw = max(fwidth(q) * 1.4, vec2(1e-4));
	vec3 Tr = normalize(vec3(n.z, 0.0, -n.x) + vec3(1e-5, 0.0, 0.0));   // along a pitched roof's contour
	vec2 r = vec2(dot(wpos, Tr), wpos.y / max(sqrt(max(1.0 - n.y * n.y, 0.0)), 0.2));
	vec2 rw = max(fwidth(r) * 1.4, vec2(1e-4));
	// every texture read up front, out of the per-triangle branches below
	vec4 nz = texture(t_noise, wpos.xz * 0.031 + wpos.y * vec2(0.017, 0.023));
	vec4 nf = texture(t_noise, q * 0.37);
	float streak = smoothstep(0.58, 0.85, texture(t_noise, vec2(q.x * 0.55, q.y * 0.025)).b);
	float grain = texture(t_noise, q * vec2(7.0, 0.3)).r;
	float on_facade = (facade_on == 0 ? cls.x : cls.y) * (1.0 - roof) * (1.0 - keep) * (wall ? 1.0 : 0.0);
	vec3 nw = n;
	float cav = 1.0;
	if (dist < 120.0) {
		float J = 0.0;
		float tone = 0.0;
		if (on_facade > 0.01 && facade > 0) {
			J = facade_j(q, fw, facade, tone);
			// joints sit 4 mm in (battens stand 4 mm out): bump the normal down their flanks, from the
			// screen-space slope of that relief (surface gradient), so the pattern is evaluated only once
			float hb = J * (facade == 5 ? 0.004 : -0.004) * on_facade;
			vec3 dpx = dFdx(wpos), dpy = dFdy(wpos);
			vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
			float det = dot(dpx, r1);
			vec3 sg = (dFdx(hb) * r1 + dFdy(hb) * r2) / (abs(det) > 1e-12 ? det : 1e-12);
			nw = normalize(nw - sg / max(1.0, length(sg) / 0.9));
			if (facade == 1 || facade == 4 || facade == 6) {
				// mortar: paler and greyer than the units
				vec3 unit = col * (1.0 + tone * vec3(0.1, 0.075, 0.04) * (facade == 1 ? 1.0 : 0.7));
				col = mix(col, mix(unit, mix(col, vec3(0.5, 0.48, 0.44), facade == 6 ? 0.3 : 0.55), J), on_facade);
				cav = 1.0 - J * 0.3 * on_facade;
			} else if (facade == 5) {
				col *= 1.0 + (J * 0.05 + tone * 0.03) * on_facade;
			} else {
				col *= 1.0 + (tone * (facade == 3 ? 0.035 : 0.025) - J * 0.5) * on_facade;
				cav = 1.0 - J * 0.4 * on_facade;
			}
			if (facade == 2) nw = normalize(nw - vec3(0.0, 0.07 * on_facade, 0.0));   // lap boards tilt their faces down
		} else if (roof > 0.01) {
			if (n.y < 0.95) {             // pitched: tile courses down the slope
				float row = floor(r.y / 0.32);
				float x = r.x + mod(row, 2.0) * 0.125;
				J = 1.0 - (1.0 - joint(r.y, 0.32, 0.035, rw.y)) * (1.0 - mix(joint(x, 0.25, 0.01, rw.x), 0.04, smoothstep(0.05, 0.12, rw.y)));
				tone = (vh_hash12(vec2(floor(x / 0.25), row)) * 2.0 - 1.0) * (1.0 - smoothstep(0.05, 0.15, max(rw.x, rw.y)));
				col *= 1.0 + (tone * 0.07 - J * 0.4) * roof;
			} else if (pal_roof.g > pal_roof.r + 0.05 && pal_roof.g > pal_roof.b + 0.02) {   // flat and green: a sedum roof, patchy, reddening in places
				col *= 1.0 + ((nf.r - 0.5) * 0.5 + (grain - 0.5) * 0.2) * roof;
				col = mix(col, col * vec3(1.5, 0.85, 0.6), smoothstep(0.62, 0.8, nf.b) * 0.45 * roof);
			} else {                      // flat: membrane sheets with welded seams, a little gravel
				J = 1.0 - (1.0 - joint(wpos.x, 2.0, 0.03, fw.x)) * (1.0 - joint(wpos.z, 1.0, 0.03, fw.y));
				col *= 1.0 - (J * 0.05 - (grain - 0.5) * 0.08) * roof;
			}
			cav = 1.0 - J * 0.3 * roof;
		} else if (cls.w > 0.5 && keep < 0.5) {   // timber: boards and grain
			float jb = joint(q.x, 0.14, 0.006, fw.x);
			tone = vh_hash12(vec2(floor(q.x / 0.14), 5.0)) * 2.0 - 1.0;
			col *= 1.0 + (grain - 0.5) * 0.22 + tone * 0.06 - jb * 0.45;
			cav = 1.0 - jb * 0.3;
			rough = mix(rough, 0.5 + grain * 0.25, cls.w);
		}
		// --- weathering: mottling, rain streaks, grime at the foot of the walls, moss on masonry in the shade
		float plain = (1.0 - keep) * (kind == 3 ? 0.4 : 1.0);
		col *= 1.0 + ((nz.r - 0.5) * 0.11 + (nf.g - 0.5) * 0.07) * plain;
		if (wall) {
			col *= 1.0 - streak * 0.06 * plain * (1.0 - cls.z);
			float grime = 1.0 - smoothstep(0.0, 0.35 + 0.6 * nf.a, h);
			col = mix(col, col * vec3(0.66, 0.61, 0.53), grime * 0.55 * plain);
			if (facade == 1 || facade == 4) {
				float shade = smoothstep(0.35, -0.1, dot(n, normalize(vh_light)));
				float moss = (1.0 - smoothstep(0.15, 1.3, h)) * smoothstep(0.48, 0.7, nf.b) * shade * on_facade;
				col = mix(col, vec3(0.06, 0.09, 0.03), moss * 0.5);
			}
		}
	}
	// contact darkening where the walls meet the ground, and in the joints
	float ao = cav * (wall ? mix(0.6, 1.0, smoothstep(0.0, 1.0, h)) * mix(0.88, 1.0, smoothstep(0.5, 3.5, h)) : 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	vec3 em = col * ((vh_indirect(nw) + vh_bounce * (0.5 - 0.5 * nw.y)) * ao + interior(wpos, nw));
	em += col * vh_lin(pal_wash) * (1.05 * wash(wpos, n, q.x, h) * (1.0 - keep));
	em += vh_lamps(wpos, nw, CAMERA_POSITION_WORLD, rough, col, 0.0);
	if (glow_kind == 1) em += col * glow_energy * vh_glow.x;
	else if (glow_kind == 2) em += vh_lin(glow_color) * glow_energy * vh_glow.y;
	if (focused) {
		FOG = vec4(0.0);
		em = vh_raw(em);
		vh_fog_a = 0.0;
		vh_alb = vec3(0.0);
	} else {
		em += vh_ibl_spec(NORMAL, VIEW, rough, f0, INV_VIEW_MATRIX) * ao;
		vh_fog_a = vh_finish(wpos, CAMERA_POSITION_WORLD, ALBEDO, em, FOG);
		vh_alb = ALBEDO;
	}
	EMISSION = em;
}

void light() {
	vec3 d = vec3(0.0), s = vec3(0.0);
	vh_direct(NORMAL, VIEW, LIGHT, LIGHT_COLOR, vh_sun_att(wpos, ATTENUATION), ROUGHNESS, d, s);
	vh_out(d, s, vh_alb, SPECULAR_LIGHT);
}
