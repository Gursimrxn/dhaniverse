shader_type canvas_item;
// The Dhaniverse mark, filled with the brand's gradient, flowing slowly.
const vec3 STOPS[6] = { vec3(1.0, 0.925, 0.741), vec3(1.0, 0.4, 0.0), vec3(0.898, 0.18, 0.996), vec3(0.439, 0.475, 1.0), vec3(0.455, 0.737, 0.871), vec3(0.631, 1.0, 0.706) };

vec3 ramp(float t) {
	float f = clamp(t, 0.0, 1.0) * 5.0;
	int i = int(min(floor(f), 4.0));
	return mix(STOPS[i], STOPS[i + 1], f - float(i));
}

void fragment() {
	float t = (UV.x + UV.y) * 0.5;
	t = 0.5 + 0.5 * sin((t * 1.6 + TIME * 0.45) * 3.14159);
	COLOR = vec4(ramp(t), texture(TEXTURE, UV).a);
}
