shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/common.gdshaderinc"

// GPU terrain: flat tiles displaced from field_tex (r = height, g = signed metres to water).
// Skirt vertices (UV2.y = 1) drop below the surface so LOD seams never show sky.
uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform sampler2D paved_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);     // field_tex coverage, texel-centre aligned
uniform vec4 paved_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 texel = vec2(0.0025, 0.0025);
uniform float cell = 2.0;                              // metres per field texel

uniform vec3 grass_dark : source_color = vec3(0.15, 0.33, 0.06);
uniform vec3 grass_light : source_color = vec3(0.27, 0.46, 0.08);
uniform vec3 path_col : source_color = vec3(0.79, 0.78, 0.74);
uniform vec3 path_dark : source_color = vec3(0.56, 0.55, 0.52);
uniform vec3 rock_light : source_color = vec3(0.6, 0.6, 0.56);
uniform vec3 rock_dark : source_color = vec3(0.36, 0.37, 0.35);
uniform vec3 moss : source_color = vec3(0.3, 0.42, 0.16);
uniform vec3 sand_col : source_color = vec3(0.86, 0.78, 0.55);
uniform vec3 gravel_col : source_color = vec3(0.52, 0.58, 0.52);
uniform vec3 lip_col : source_color = vec3(0.3, 0.2, 0.14);

varying vec3 wpos;
varying float wsd;
varying float steep;

float hgt(vec2 uv) { return textureLod(field_tex, uv, 0.0).r; }

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (w.xz - map_rect.xy) / map_rect.zw;
	vec4 f = textureLod(field_tex, uv, 0.0);
	float hl = hgt(uv - vec2(texel.x, 0.0)), hr = hgt(uv + vec2(texel.x, 0.0));
	float hu = hgt(uv - vec2(0.0, texel.y)), hd = hgt(uv + vec2(0.0, texel.y));
	VERTEX.y = f.r - UV2.y * 2.5;
	NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	steep = 1.0 - NORMAL.y;
	wsd = f.g;
	wpos = vec3(w.x, f.r, w.z);
}

// rounded cobbles: cell distance with jittered centres
float cobble(vec2 p, out float id) {
	vec2 g = floor(p);
	vec2 fr = fract(p);
	float best = 8.0;
	id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = vec2(hash12(g + o), hash12(g + o + 19.7));
			vec2 r = o + 0.25 + h * 0.5 - fr;
			float d = dot(r, r);
			if (d < best) { best = d; id = hash12(g + o + 3.3); }
		}
	}
	return sqrt(best);
}

void fragment() {
	float n = fbm2(wpos.xz * 0.12);
	float n2 = vnoise(wpos.xz * 0.9);
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.25, 0.8, n) * 0.8 + n2 * 0.15);

	// rock on steep ground: faceted bands with moss on the tops
	float id;
	float facet = cobble(vec2(wpos.x + wpos.z, wpos.y * 2.2) * 0.35, id);
	vec3 rock = mix(rock_dark, rock_light, 0.45 + id * 0.45) * (0.9 + n2 * 0.2);
	rock *= 1.0 - smoothstep(0.38, 0.5, facet) * 0.25;
	rock = mix(rock, moss, smoothstep(0.55, 0.85, n) * 0.5);
	col = mix(col, rock, smoothstep(0.28, 0.42, steep + (n2 - 0.5) * 0.12));

	// lanes + trails from the 0.5 m mask: soft setts, worn grass edge
	float c = cobble(wpos.xz * 2.6, id);
	vec3 stones = mix(path_dark, path_col, 0.72 + id * 0.28);
	stones *= 1.0 - smoothstep(0.34, 0.48, c) * 0.3;
	stones *= 0.94 + n2 * 0.1;
	float paved = texture(paved_tex, (wpos.xz - paved_rect.xy) / paved_rect.zw).r;
	col = mix(col, stones, smoothstep(0.25, 0.55, paved + (n2 - 0.5) * 0.25));

	// shoreline: soil lip, sandy beach on gentle banks, sand/gravel bed under the water
	float under = smoothstep(0.2, -0.4, wsd);
	float depthw = max(0.0, -wsd) * 0.35;
	vec3 bed = mix(sand_col, gravel_col, smoothstep(0.3, 1.6, depthw)) * (0.82 + n2 * 0.3);
	float shore = smoothstep(2.6, 0.0, wsd) * (1.0 - under) * (1.0 - paved) * (1.0 - smoothstep(0.3, 0.5, steep));
	vec3 beach = mix(lip_col, sand_col, smoothstep(0.35, 0.8, vnoise(wpos.xz * 0.35)));
	col = mix(col, beach, shore * 0.85);
	col = mix(col, bed, under);
	col *= 1.0 - cloud_shadow(wpos) * 0.18;
	ALBEDO = apply_focus(col, wpos);
	ROUGHNESS = 1.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(dot(NORMAL, LIGHT), ATTENUATION, LIGHT_COLOR);
}
