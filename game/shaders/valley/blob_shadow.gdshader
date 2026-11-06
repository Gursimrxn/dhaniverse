shader_type spatial;
// A soft round shadow laid on the ground (just-a-simple-tree's impostor shadow: a quad under the tree), for the
// low quality, where the sun casts no shadow map: the shadow's colour over what is under it, fading to nothing at
// its rim, as dark as the sun is strong.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://shaders/foliage/foliage.gdshaderinc"

uniform float darkness = 0.45;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float k = (1.0 - smoothstep(0.35, 1.0, r)) * darkness * clamp(dot(fol_sun, FOL_LUMA) / 4.5, 0.0, 1.0) * fol_dim;
	ALBEDO = vh_raw(fol_shadow.rgb * 0.5);
	ALPHA = k;
}
