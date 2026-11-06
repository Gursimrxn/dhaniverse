// GPU placement for ground cover fields. The MultiMesh is a fixed lattice that follows the camera in
// whole cells; every world lattice point hashes its own jitter / size / phase and reads height and
// density from the valley textures, so no per-instance data lives on the CPU.
uniform sampler2D height_tex : filter_linear, repeat_disable;   // r = terrain height
uniform sampler2D dens_tex : filter_linear, repeat_disable;     // cover densities (rgba)
uniform sampler2D paved_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 paved_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float spacing = 1.0;
uniform float field_radius = 30.0;
uniform float inner_radius = 0.0;
uniform vec2 size_range = vec2(0.8, 1.2);
uniform vec4 channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float density = 1.0;

// xyz = world root, w = scale (0 = culled). hs = three hashes in 0..1.
vec4 field_place(vec3 lattice, vec3 centre, out vec3 hs) {
	vec2 cell = floor(lattice.xz / spacing + 0.5);
	hs = vec3(fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453),
		fract(sin(dot(cell, vec2(39.3468, 11.135))) * 24634.6345),
		fract(sin(dot(cell, vec2(73.156, 52.235))) * 13758.937));
	vec2 w = (cell + hs.xy - 0.5) * spacing;
	vec2 muv = (w - map_rect.xy) / map_rect.zw;
	float d = dot(textureLod(dens_tex, muv, 0.0), channel) * density;
	d *= 1.0 - smoothstep(0.2, 0.55, textureLod(paved_tex, (w - paved_rect.xy) / paved_rect.zw, 0.0).r);
	float r = length(w - centre.xz);
	d *= (1.0 - smoothstep(field_radius * 0.72, field_radius, r)) * smoothstep(inner_radius * 0.72, inner_radius, r);
	return vec4(w.x, textureLod(height_tex, muv, 0.0).r, w.y, mix(size_range.x, size_range.y, hs.x) * step(hs.z, d));
}

mat3 field_yaw(float a) {
	float c = cos(a), s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}
