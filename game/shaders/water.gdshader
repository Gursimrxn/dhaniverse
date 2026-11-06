shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

// Depth comes from the terrain height texture (no screen depth needed: browser-safe).
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 map_rect;          // x0, z0, width, depth of height_tex in metres
uniform vec3 shallow : source_color = vec3(0.12, 0.85, 0.62);
uniform vec3 deep : source_color = vec3(0.03, 0.42, 0.55);
uniform vec3 foam_col : source_color = vec3(1.0, 0.97, 0.9);
uniform vec2 flow = vec2(0.02, 0.35);
uniform float max_depth = 100.0;   // upper stream plane: hide where the ground is far below
uniform float calm = 0.0;          // 1 = still mirror reach: flatter ripples, stronger sky reflection
uniform vec3 sky_top : source_color = vec3(0.56, 0.61, 0.84);
uniform vec3 sky_horizon : source_color = vec3(0.96, 0.81, 0.77);

varying vec3 wpos;

float ground_at(vec2 xz) {
	vec2 uv = (xz - map_rect.xy) / map_rect.zw;
	return texture(height_tex, uv).r;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.6 + TIME * 1.3) * 0.02 + sin(wpos.z * 0.8 - TIME * 1.1) * 0.02;
	VERTEX.y += w;
}

// Classic animated caustic network (4 folded sine iterations), cheap and WebGL2-safe.
float caustic(vec2 uv, float t) {
	vec2 p = mod(uv * 6.28318, 6.28318) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 4; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	return pow(abs(c), 8.0);
}

void fragment() {
	// surface height comes from the mesh, so sloping rivers work too
	float depth = max(0.0, wpos.y - ground_at(wpos.xz));
	if (depth > max_depth) discard;
	vec2 p = wpos.xz;

	// ripple normal from two scrolling noise layers
	float n1 = fbm2(p * 0.5 + flow * TIME);
	float n2 = fbm2(p * 0.9 - flow.yx * TIME * 0.7);
	float ex = fbm2(p * 0.5 + flow * TIME + vec2(0.07, 0.0)) - n1;
	float ez = fbm2(p * 0.5 + flow * TIME + vec2(0.0, 0.07)) - n1;
	float rip = mix(2.4, 0.6, calm);
	vec3 nw = normalize(vec3(-ex * rip, 1.0, -ez * rip));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// clear tropical gradient: the bed shows through the shallows (terrain paints sand/gravel)
	float dt = 1.0 - exp(-depth * 0.55);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.0, dt));
	// light network drifting over the bed, strongest where it is shallow
	float cs = caustic(p * 0.11 + n1 * 0.05, TIME * 0.45) * 0.8 + caustic(p * 0.19 - 3.0, TIME * 0.33) * 0.5;
	col += vec3(0.85, 1.0, 0.8) * cs * (1.0 - dt) * 0.7;
	// tiny bright sparkles on the ripples
	col += vec3(1.0) * pow(max(n1 * n2 * 1.7 - 0.48, 0.0), 3.0) * 1.5;

	// foam ring where water meets the shore + soft broken lines
	float edge = 1.0 - smoothstep(0.0, 0.38, depth);
	float foam = smoothstep(0.52, 0.72, edge + (n2 - 0.5) * 0.5);
	float lines = smoothstep(0.82, 0.9, sin(depth * 22.0 - TIME * 1.1 + n1 * 5.0) * 0.5 + 0.5) * edge * 0.6;
	col = mix(col, foam_col, clamp(foam + lines, 0.0, 1.0) * 0.9);

	// sky reflection (browser-safe: no planar/SSR pass), strongest at grazing angles
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 rw = reflect(-vw, nw);
	vec3 skyc = mix(sky_horizon, sky_top, smoothstep(0.0, 0.55, rw.y));
	float fr = pow(1.0 - clamp(dot(nw, vw), 0.0, 1.0), 3.0);
	col = mix(col, skyc, clamp(fr * (0.45 + 0.4 * calm) + calm * 0.12, 0.0, 0.85) * (1.0 - foam));
	col = apply_focus(col, wpos);
	ALBEDO = col;
	// see-through shallows, denser deep water
	ALPHA = clamp(0.28 + dt * 0.62 + foam * 0.45, 0.0, 0.97) * (1.0 - focus_amount * 0.5);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = vec3(0.85, 0.95, 1.0) * fres * 0.3 * (1.0 - focus_amount) + col * 0.06;
}
