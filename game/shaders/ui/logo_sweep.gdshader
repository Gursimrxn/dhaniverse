shader_type canvas_item;
// The title's name: cream, with the brand's gradient sweeping across it every so often. Colours by screen position, so it runs
// across the whole word rather than across each letter.
const vec3 STOPS[6] = { vec3(1.0, 0.925, 0.741), vec3(1.0, 0.4, 0.0), vec3(0.898, 0.18, 0.996), vec3(0.439, 0.475, 1.0), vec3(0.455, 0.737, 0.871), vec3(0.631, 1.0, 0.706) };
uniform vec3 cream : source_color = vec3(1.0, 0.973, 0.89);
uniform float every = 7.0;
uniform float width = 0.32;

vec3 ramp(float t) {
	float f = clamp(t, 0.0, 1.0) * 5.0;
	int i = int(min(floor(f), 4.0));
	return mix(STOPS[i], STOPS[i + 1], f - float(i));
}

void fragment() {
	float head = fract(TIME / every) * 2.4 - 0.5;
	float t = (SCREEN_UV.x - head) / width + 0.5;
	float inside = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.92, 1.0, t));
	COLOR.rgb = mix(cream, ramp(t), inside);
}
