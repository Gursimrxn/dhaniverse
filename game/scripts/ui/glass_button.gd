class_name GlassButton
extends PanelContainer
## The landing's Play Now button (Figma 1919:1603), the game's one clickable button: a frosted cream shell, a dark pill inside it
## shading from grey at the top to black at the bottom with a soft shadow, the label in the editorial serif, a key cap in front when a
## key does the same. Scaled to the 1280x720 canvas.

signal pressed

const PILL_H := 43.0
const SHADE := """shader_type canvas_item;
uniform vec2 size;
uniform float radius = 15.0;
uniform float hover = 0.0;
void fragment() {
	vec2 p = abs(UV * size - size * 0.5) - (size * 0.5 - radius);
	float d = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - radius;
	vec3 c = mix(vec3(0.4), vec3(0.0), UV.y) + hover * 0.08;
	COLOR = vec4(c, clamp(0.5 - d, 0.0, 1.0));
}"""

var _pill := Button.new()
var _bg := ColorRect.new()
var _mat := ShaderMaterial.new()

func _init(text: String, key := "", width := 0.0) -> void:
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color(1.0, 0.973, 0.89, 0.1)
	shell.border_color = Color(0, 0, 0, 0.1)
	shell.set_border_width_all(1)
	shell.set_corner_radius_all(22)
	shell.set_content_margin_all(9)
	shell.shadow_color = Color(1, 1, 1, 0.1)
	shell.shadow_size = 30
	shell.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", shell)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: _pill.add_theme_stylebox_override(state, flat)
	_pill.custom_minimum_size = Vector2(width, PILL_H)
	_pill.focus_mode = Control.FOCUS_NONE
	_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pill.pressed.connect(func(): pressed.emit())
	_pill.mouse_entered.connect(func(): _mat.set_shader_parameter("hover", 1.0))
	_pill.mouse_exited.connect(func(): _mat.set_shader_parameter("hover", 0.0))
	_mat.shader = Shader.new()
	_mat.shader.code = SHADE
	_bg.material = _mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.resized.connect(func(): _mat.set_shader_parameter("size", _bg.size))
	_pill.add_child(_bg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	if key != "":
		var cap := GameHud.key_cap(key, 11)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cap)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Brand.FONT_EDITORIAL)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Brand.CREAM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_pill.add_child(row)
	if width <= 0.0: _pill.custom_minimum_size.x = row.get_combined_minimum_size().x + 32.0
	add_child(_pill)
