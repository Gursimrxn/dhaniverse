// The ink outline round a person (next pass of character.gdshader): the back faces pushed out along their
// normals by a width that grows with distance, so the line stays about two pixels wide from the high camera.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, ambient_light_disabled, shadows_disabled;

uniform vec3 ink : source_color = vec3(0.12, 0.1, 0.13);
uniform float px = 0.0011;           // outline width per metre of distance

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(wp, CAMERA_POSITION_WORLD);
	VERTEX += NORMAL * clamp(d * px, 0.004, 0.08);
}

void fragment() {
	ALBEDO = ink;
}
