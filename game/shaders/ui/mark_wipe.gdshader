shader_type canvas_item;
// A wipe through the Dhaniverse mark: the screen is covered except through the mark, which grows until it has opened the whole
// screen. reveal 0 is fully covered, 1 is fully open.

uniform sampler2D mark : filter_linear, repeat_disable;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.778;          // screen width over height
uniform float mark_aspect = 1.024;     // the mark's width over height
uniform float biggest = 14.0;          // the mark's height, in screen heights, once it fills the screen
uniform vec4 cover : source_color = vec4(0.149, 0.153, 0.153, 1.0);

void fragment() {
	float grown = reveal * reveal * biggest;
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	vec2 m = p / max(grown, 0.0001) / vec2(mark_aspect, 1.0) + 0.5;
	float inside = 0.0;
	if (m.x >= 0.0 && m.x <= 1.0 && m.y >= 0.0 && m.y <= 1.0 && grown > 0.0) {
		inside = texture(mark, m).a;
	}
	COLOR = vec4(cover.rgb, cover.a * (1.0 - inside));
}
