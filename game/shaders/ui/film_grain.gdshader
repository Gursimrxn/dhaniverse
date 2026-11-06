shader_type canvas_item;
// A little film grain over the title shot.
uniform float amount = 0.05;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float n = noise(floor(FRAGCOORD.xy * 0.5) + fract(TIME) * 91.0);
	COLOR = vec4(vec3(n), amount);
}
