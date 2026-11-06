shader_type spatial;
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/vh/vh_sky.gdshaderinc"

// Screen-space ambient occlusion, multiplied over the opaque scene before any glass, water or haze is drawn
// (render_priority -128): contact shade in the corners of buildings, under eaves, sills and balconies,
// between leaves and at the foot of grass, trees and walls. Six taps on a rotated disc `radius` metres
// wide at the pixel's depth; each compares the depth found there with the depth the pixel's own plane
// predicts (depth-buffer values are linear across the screen on a plane), so flat and slanted surfaces stay
// clean and only creases and things standing in front of a surface darken it. Silhouette pixels, the sky
// and the distance are left alone. Drawn as a full-screen quad on its own layer (not in the reflection).
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float radius = 0.85;      // metres
uniform float strength = 0.9;
uniform float fade_far = 70.0;    // metres: no occlusion beyond

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float m22 = PROJECTION_MATRIX[2][2];
	float m32 = PROJECTION_MATRIX[3][2];
	float d0 = texture(depth_tex, uv).r;
	float z = m32 / (d0 * 2.0 - 1.0 + m22);
	// depth change per unit of screen uv (window y and uv y may run opposite ways)
	vec2 dd = vec2(dFdx(d0) / dFdx(uv.x), dFdy(d0) / dFdy(uv.y));
	float jump = max(abs(dFdx(z)), abs(dFdy(z)));
	float ao = 1.0;
	float rpx = radius * abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y / max(z, 0.05);
	if (d0 < 0.99999 && z < fade_far && jump < 0.04 * z && rpx > 1.5) {
		rpx = min(rpx, 56.0);
		float a0 = 6.2831853 * fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		float bias = 0.04 + z * 0.01;
		float occ = 0.0;
		for (int i = 0; i < 6; i++) {
			float a = a0 + float(i) * 2.3999632;
			vec2 o = vec2(cos(a), sin(a)) * sqrt((float(i) + 0.5) / 6.0) * rpx;
			vec2 ou = o / VIEWPORT_SIZE;
			float ds = texture(depth_tex, uv + ou).r;
			float zs = m32 / (ds * 2.0 - 1.0 + m22);
			float zp = m32 / ((d0 + dot(dd, ou)) * 2.0 - 1.0 + m22);   // the pixel's plane, there
			float diff = zp - zs;                                    // > 0: something stands in front of it
			occ += smoothstep(bias, bias * 3.0 + 0.04, diff) * (1.0 - smoothstep(radius * 1.2, radius * 3.0, diff));
		}
		ao = max(1.0 - strength * (occ / 6.0) * (1.0 - smoothstep(fade_far * 0.55, fade_far, z)), 0.3);
	}
	ALBEDO = vh_raw(vec3(ao));
}
