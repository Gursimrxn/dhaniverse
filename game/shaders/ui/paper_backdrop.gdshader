shader_type canvas_item;
// Behind a paper: the scene, blurred and darkened, as the boards' blur(.4rem) brightness(.62).
uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 sigma = vec2(0.0028, 0.005);   // .4rem (3.6px) at 1280x720, in UV so it holds at any window size
uniform float brightness = 0.62;

void fragment() {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = exp(-0.5 * float(x * x + y * y));
			sum += texture(screen, SCREEN_UV + vec2(float(x), float(y)) * sigma).rgb * w;
			total += w;
		}
	}
	COLOR = vec4(sum / total * pow(brightness, 2.2), 1.0);   // hdr_2d keeps the screen linear; the boards dim in sRGB
}
