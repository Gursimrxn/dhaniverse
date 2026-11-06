class_name Cinema
extends Control
## The look every cutscene shares: letterbox bars, title cards and a transition through the Dhaniverse mark. The Director moves
## the camera; this frames it. Each call returns when its motion has finished, so a cutscene reads top to bottom with await.

const BAR := 0.11                # of the screen's height, each
const BARS_TIME := 0.5           # s
const WIPE_TIME := 0.9           # s
const CARD_FADE := 0.35          # s
const OVER_THE_WORLD := 40       # z index: over world tags, under papers
const SAYS_FOR := 3.5            # s
const SAID_ABOVE_EDGE := 34.0    # px, in play

var _top := ColorRect.new()
var _bottom := ColorRect.new()
var _wipe := ColorRect.new()
var _wipe_look := ShaderMaterial.new()
var _card := VBoxContainer.new()
var _kicker := Label.new()
var _title := Label.new()
var _line := Label.new()
static var say_scale := 1.0       # the player's subtitle size

var _said := Label.new()
var _said_tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = OVER_THE_WORLD
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for bar in [_top, _bottom]:
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		add_child(bar)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_constant_override("separation", 6)
	_style(_kicker, Brand.FONT_DISPLAY, 22)
	_style(_title, Brand.FONT_EDITORIAL, 110)
	_style(_line, Brand.FONT_BODY, 24)
	for part in [_kicker, _title, _line]: _card.add_child(part)
	_card.visible = false
	add_child(_card)
	_wipe_look.shader = preload("res://shaders/ui/mark_wipe.gdshader")
	_wipe_look.set_shader_parameter("mark", preload("res://assets/ui/coin_mark.svg"))
	_wipe.material = _wipe_look
	_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.visible = false
	_style(_said, Brand.FONT_BODY, 22)
	_said.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_said.visible = false
	add_child(_said)
	add_child(_wipe)

func _style(label: Label, font: Font, font_size: int) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Brand.CREAM)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## The bars come in: this is now a film.
func bars_in() -> void:
	var h := size.y * BAR
	_top.size = Vector2(size.x, h)
	_bottom.size = Vector2(size.x, h)
	_top.position = Vector2(0, -h)
	_bottom.position = Vector2(0, size.y)
	_top.visible = true
	_bottom.visible = true
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_top, "position:y", 0.0, BARS_TIME)
	t.tween_property(_bottom, "position:y", size.y - h, BARS_TIME)
	await t.finished

## The bars go: control is the player's again.
func bars_out() -> void:
	var h := size.y * BAR
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_top, "position:y", -h, BARS_TIME)
	t.tween_property(_bottom, "position:y", size.y, BARS_TIME)
	await t.finished
	_top.visible = false
	_bottom.visible = false

## A title card over the shot, then it fades. Empty parts are left out.
func card(title: String, kicker := "", line := "", holds := 2.5) -> void:
	_title.text = title
	_kicker.text = kicker
	_line.text = line
	_kicker.visible = kicker != ""
	_line.visible = line != ""
	_card.visible = true
	_card.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_card, "modulate:a", 1.0, CARD_FADE)
	t.tween_interval(holds)
	t.tween_property(_card, "modulate:a", 0.0, CARD_FADE)
	await t.finished
	_card.visible = false

## Closes the screen down onto the mark.
func wipe_closed() -> void:
	await _run_wipe(1.0, 0.0)

## Opens the screen out through the mark.
func wipe_open() -> void:
	await _run_wipe(0.0, 1.0)
	_wipe.visible = false

## Through the mark to somewhere else: close, do the change, open.
func cut(change: Callable) -> void:
	await wipe_closed()
	change.call()
	await wipe_open()

func _run_wipe(from: float, to: float) -> void:
	_wipe_look.set_shader_parameter("aspect", size.x / size.y)
	_wipe_look.set_shader_parameter("reveal", from)
	_wipe.visible = true
	var t := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(v: float): _wipe_look.set_shader_parameter("reveal", v), from, to, WIPE_TIME)
	await t.finished

## A line someone says, as a subtitle: on the lower bar in a film, low on the screen in play. Doesn't wait.
func say(words: String, holds := SAYS_FOR) -> void:
	_said.text = words
	_said.add_theme_font_size_override("font_size", int(22.0 * say_scale))
	var room := size.x * 0.62           # a long line wraps, rather than running off the screen
	var wide := _said.get_theme_font("font").get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22.0 * say_scale)).x + 50.0
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide > room else TextServer.AUTOWRAP_OFF
	_said.custom_minimum_size.x = room if wide > room else 0.0
	_said.size = Vector2.ZERO
	var on_bars := _top.visible
	if on_bars: _said.remove_theme_stylebox_override("normal")
	else: _said.add_theme_stylebox_override("normal", _said_plate())
	_said.reset_size()
	var bar := size.y * BAR
	var y := size.y - bar * 0.5 - _said.size.y * 0.5 if on_bars else size.y - _said.size.y - SAID_ABOVE_EDGE
	_said.position = Vector2((size.x - _said.size.x) * 0.5, y)
	_said.visible = true
	_said.modulate.a = 1.0
	if _said_tween: _said_tween.kill()
	_said_tween = create_tween()
	_said_tween.tween_interval(holds)
	_said_tween.tween_property(_said, "modulate:a", 0.0, CARD_FADE)
	_said_tween.tween_callback(func(): _said.visible = false)

## In play there are no bars to sit on, so the line gets the HUD's dark plate.
func _said_plate() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(99)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
