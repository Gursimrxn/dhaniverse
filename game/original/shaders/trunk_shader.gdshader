shader_type spatial;
render_mode specular_disabled;

uniform float light_steps = 3.0;
uniform sampler2D color_texture : filter_nearest, source_color;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float outline_mask = 1.0;

varying float occlusion;
varying vec4 world_pos;

void vertex() {
	world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
}

void fragment() {
	occlusion = round(COLOR.r * light_steps) / light_steps;
	vec4 color = texture(color_texture, UV * uv_scale);
	ALBEDO = color.rgb;
	SPECULAR = 0.0;
	ROUGHNESS = outline_mask;
}

void light() {
	float light = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	light = ceil(light * light_steps) / light_steps;
	DIFFUSE_LIGHT += light * ATTENUATION * occlusion * LIGHT_COLOR / PI;
}
