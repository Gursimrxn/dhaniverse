class_name MenuWord
extends Control
## One line of the big menus: a serif word that rolls over into italic when chosen, with an orange tick drawing in and a small line beside
## it. Used by the title and the settings, so they read as one thing.

signal hovered
signal pressed

const HEIGHT := 57.0
const INDENT := 30.0
const TIME := 0.5                  # s

var _clip := Control.new()
var _plain := Label.new()
var _italic := Label.new()
var _tick := ColorRect.new()
var _sub := Label.new()
var _on := false
var _tween: Tween

func setup(word: String, sub := "", font_size := 43) -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tick.color = Brand.ORANGE
	_tick.size = Vector2(32, 4)
	_tick.position = Vector2(-10, HEIGHT * 0.5 - 2.0)
	_tick.scale.x = 0.0
	_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tick)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in [[_plain, Brand.FONT_EDITORIAL, Brand.CREAM], [_italic, Brand.FONT_EDITORIAL_ITALIC, Color("ffecbd")]]:
		var l: Label = pair[0]
		l.text = word
		l.add_theme_font_override("font", pair[1])
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", pair[2])
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size.y = HEIGHT
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clip.add_child(l)
	_italic.position.y = HEIGHT
	add_child(_clip)
	_sub.text = sub
	_sub.add_theme_font_override("font", Brand.FONT_BODY)
	_sub.add_theme_font_size_override("font_size", 13)
	_sub.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_sub.add_theme_constant_override("shadow_offset_y", 1)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.size.y = HEIGHT
	_sub.modulate.a = 0.0
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub)
	mouse_entered.connect(func(): hovered.emit())

func _ready() -> void:
	# the words' real width is only known from here
	await get_tree().process_frame
	var w := maxf(_plain.get_minimum_size().x, _italic.get_minimum_size().x) + 8.0
	_clip.size = Vector2(w, HEIGHT)
	_sub.position.x = w + 14.0
	custom_minimum_size.x = w + INDENT + 240.0 if _sub.text != "" else w + INDENT + 10.0

func set_on(on: bool) -> void:
	if on == _on: return
	_on = on
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_tick, "scale:x", 1.0 if on else 0.0, TIME * 0.8)
	_tween.tween_property(_clip, "position:x", INDENT if on else 0.0, TIME * 0.8)
	_tween.tween_property(_plain, "position:y", -HEIGHT if on else 0.0, TIME)
	_tween.tween_property(_italic, "position:y", 0.0 if on else HEIGHT, TIME)
	_tween.tween_property(_sub, "modulate:a", 1.0 if on else 0.0, TIME * 0.6)
	_tween.tween_property(_sub, "position:x", _clip.size.x + 14.0 + (INDENT if on else 0.0), TIME * 0.8)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()

## Change the small line beside the word.
func set_sub(text: String) -> void:
	_sub.text = text
