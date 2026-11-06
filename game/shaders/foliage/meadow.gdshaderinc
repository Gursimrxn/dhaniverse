// The meadow's colour, one field over the world, shared by the grass blades (grass.gdshaderinc) and the ground
// under them (ground.gdshader), so a lawn reads as one soft carpet and the blades only add texture to it.
// After the anime grass in reference/youtube 3d stylized/animegrass.blend (material crzyzha_grass), whose
// colour is noise, not light: a lime base multiplied by large soft fbm patches (x0.75), a fine fbm speckle
// (x0.69), cool sky-blue patches (x0.39), and a few bright sun spots screened on; the root darkened and the
// shadows multiplied in softly rather than banded. Dylearn's grass splits its colour by noise the same way.
// Scales here are in metres, sized for a third-person camera rather than that 2 m test plane. The noise is
// baked into a texture (MeadowNoise), not hashed per vertex: the grass draws hundreds of thousands of them.

uniform vec3 m_lime : source_color = vec3(0.745, 0.918, 0.36);    // #becf5c.. #beea5c, the sunny lawn
uniform vec3 m_base : source_color = vec3(0.58, 0.82, 0.31);    // #94d14f
uniform vec3 m_deep : source_color = vec3(0.37, 0.67, 0.27);    // #5fab45, the darker patches
uniform vec3 m_cool : source_color = vec3(0.627, 0.851, 0.98);    // #a0d9fa, the cool patches' multiply
uniform vec3 m_spot : source_color = vec3(0.9, 0.98, 0.52);    // #e6fa85, sun spots
uniform float m_patch = 2.6;          // m: the soft dark patches' size
uniform float m_speck = 0.45;         // m: the fine speckle's size

global uniform sampler2D fol_noise_tex : filter_linear_mipmap, repeat_enable;   // MeadowNoise: 4 fbm channels

// One channel of the baked noise (four features across a tile), at a world scale of `size` metres a feature,
// at the mip a pixel covering px metres can show
float m_noise(vec2 x, float size, float px, vec4 channel) {
	float tile = size * 4.0;
	float lod = log2(max(px / tile * 256.0, 1e-4));
	return dot(textureLod(fol_noise_tex, x / tile, lod), channel);
}

// The lawn's colour (linear) at world xz; px: metres one screen pixel covers there
vec3 meadow_col(vec2 x, float px) {
	vec3 c = mix(fol_lin(m_base), fol_lin(m_lime), smoothstep(0.3, 0.75, m_noise(x + 31.0, m_patch * 2.3, px, vec4(0, 0, 1, 0))));
	// the soft darker patches
	float big = m_noise(x, m_patch, px, vec4(1, 0, 0, 0));
	c = mix(c, c * fol_lin(m_deep) / fol_lin(m_base), 0.75 * (1.0 - smoothstep(0.32, 0.62, big)));
	// the fine speckle (its mips flatten it to grey far off, where it would only shimmer)
	float sp = m_noise(x, m_speck, px, vec4(0, 1, 0, 0));
	c *= mix(1.0, mix(0.72, 1.06, smoothstep(0.35, 0.7, sp)), 0.69);
	// cool patches, where the sky seems to lie on the grass
	float cool = m_noise(x - 9.0, 7.5, px, vec4(0, 0, 1, 0));
	c *= mix(vec3(1.0), fol_lin(m_cool), 0.39 * smoothstep(0.55, 0.75, cool));
	// a few sun spots, screened on
	float spot = m_noise(x, 3.4, px, vec4(0, 0, 0, 1));
	vec3 s = fol_lin(m_spot) * smoothstep(0.66, 0.8, spot);
	c = 1.0 - (1.0 - c) * (1.0 - s * 0.35);
	return c;
}

// How the meadow is lit: colour from the field, so the sun only scales it with the time of day and the
// shadows lie on it softly and cool (as the anime grass multiplies its painted shadows in at 0.775)
vec3 meadow_light(vec3 c, float shadow) {
	float day = clamp(dot(fol_sun, FOL_LUMA) / 4.5, 0.12, 1.0);
	vec3 shade = mix(vec3(1.0), mix(vec3(1.0), fol_shadow.rgb * 8.0 + 0.2, fol_shadow.a), 0.775);
	return c * day * mix(shade, vec3(1.0), shadow);
}
