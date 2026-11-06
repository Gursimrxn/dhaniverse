class_name BootIntro
extends CanvasLayer
## What the game opens with: black while the town loads, then the logo and the name; the name goes, the mark takes the centre, breathes in,
## and the town bursts out through it. Sits over everything until it's done.

signal opened                      # the town is showing through: the title can come in
signal done

const MARK := preload("res://assets/ui/coin_mark.svg")
const MARK_SIZE := 124.0           # px, at the 720 tall canvas
const WIPE_TIME := 1.7             # s
const HOLE_REVEAL := 0.112         # the wipe's reveal at which its hole is the mark's size
const BIGGEST := 14.0              # the wipe's biggest, in screen heights

var _root := Control.new()
var _black := ColorRect.new()
var _line := ColorRect.new()
var _line_fill := ColorRect.new()
var _center := CenterContainer.new()
var _mark := TextureRect.new()
var _wrap := Control.new()
var _word := Label.new()
var _wipe := ColorRect.new()
var _wipe_look := ShaderMaterial.new()
var _flash := ColorRect.new()
var _ring := Control.new()
var _ring_k := -1.0

func _ready() -> void:
	layer = 100
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_black)
	_build_line()
	_build_lockup()
	_build_wipe()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_root.add_child(_ring)

func _build_line() -> void:
	_line.color = Color(Brand.CREAM, 0.14)
	_line.size = Vector2(196, 2)
	_line.anchor_left = 0.5
	_line.anchor_top = 0.5
	_line.anchor_right = 0.5
	_line.anchor_bottom = 0.5
	_line.offset_left = -98
	_line.offset_right = 98
	_line.offset_top = -1
	_line.offset_bottom = 1
	_line_fill.color = Brand.CREAM
	_line_fill.size = Vector2(196, 2)
	_line_fill.scale.x = 0.0
	_line.add_child(_line_fill)
	_root.add_child(_line)
	# there's no knowing how far the town has got while it's being built, so it eases towards most of the way, then finishes
	create_tween().tween_property(_line_fill, "scale:x", 0.8, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build_lockup() -> void:
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.texture = MARK
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.custom_minimum_size = Vector2.ONE * MARK_SIZE
	_mark.pivot_offset = Vector2.ONE * MARK_SIZE * 0.5
	_mark.scale = Vector2.ONE * 0.2
	_mark.modulate.a = 0.0
	var look := ShaderMaterial.new()
	look.shader = preload("res://shaders/ui/gradient_mark.gdshader")
	_mark.material = look
	row.add_child(_mark)
	_wrap.clip_contents = true
	_wrap.custom_minimum_size = Vector2(0, MARK_SIZE)
	_word.text = "Dhaniverse"
	_word.add_theme_font_override("font", Brand.FONT_BODY)
	_word.add_theme_font_size_override("font_size", 78)
	_word.add_theme_constant_override("outline_size", 0)
	_word.add_theme_color_override("font_color", Brand.CREAM)
	_word.position = Vector2(24, (MARK_SIZE - 100.0) * 0.5)
	_wrap.add_child(_word)
	row.add_child(_wrap)
	_center.add_child(row)
	_root.add_child(_center)

func _build_wipe() -> void:
	_wipe_look.shader = preload("res://shaders/ui/mark_wipe.gdshader")
	_wipe_look.set_shader_parameter("mark", MARK)
	_wipe_look.set_shader_parameter("cover", Color.BLACK)
	_wipe_look.set_shader_parameter("biggest", BIGGEST)
	_wipe.material = _wipe_look
	_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.visible = false
	_root.add_child(_wipe)
	_flash.color = Color(Brand.CREAM, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

## The town is built: finish the line, and run the whole thing.
func play() -> void:
	var finish := create_tween()
	finish.tween_property(_line_fill, "scale:x", 1.0, 0.25).set_trans(Tween.TRANS_CUBIC)
	finish.tween_property(_line, "modulate:a", 0.0, 0.2)
	await finish.finished
	_line.visible = false

	# the mark pops in, spinning a little
	_mark.rotation_degrees = -90.0
	var pop := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_mark, "scale", Vector2.ONE, 0.5)
	pop.tween_property(_mark, "rotation_degrees", 0.0, 0.5)
	pop.tween_property(_mark, "modulate:a", 1.0, 0.25)
	await pop.finished

	# the name opens beside it, and the row re-centres itself as it does
	await _open_word(_word.get_minimum_size().x + 32.0)
	await get_tree().create_timer(0.7).timeout
	await _open_word(0.0)

	# breathes in
	var breath := create_tween()
	breath.tween_property(_mark, "scale", Vector2.ONE * 0.86, 0.26).set_trans(Tween.TRANS_SINE)
	breath.tween_property(_mark, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await breath.finished

	_burst()

func _open_word(to: float) -> void:
	var t := create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(w: float): _wrap.custom_minimum_size.x = w, _wrap.custom_minimum_size.x, to, 0.6)
	await t.finished

## The boom: the town through the mark, a shockwave, a flash.
func _burst() -> void:
	_center.visible = false
	_black.visible = false
	var size := _root.size
	_wipe_look.set_shader_parameter("aspect", size.x / size.y)
	_wipe_look.set_shader_parameter("reveal", HOLE_REVEAL)
	_wipe.visible = true
	opened.emit()
	var t := create_tween().set_parallel()
	t.tween_method(func(v: float): _wipe_look.set_shader_parameter("reveal", v), HOLE_REVEAL, 1.0, WIPE_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(_set_ring, 0.0, 1.0, 1.1).set_delay(0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_flash, "color:a", 0.5, 0.12).set_delay(0.5)
	t.chain().tween_property(_flash, "color:a", 0.0, 0.5)
	await t.finished
	done.emit()
	queue_free()

func _set_ring(k: float) -> void:
	_ring_k = k
	_ring.queue_redraw()

func _draw_ring() -> void:
	if _ring_k < 0.0 or _ring_k >= 1.0: return
	var c := _ring.size * 0.5
	_ring.draw_arc(c, lerpf(70.0, _ring.size.x * 0.7, _ring_k), 0.0, TAU, 96, Color(Brand.CREAM, 0.9 * (1.0 - _ring_k)), lerpf(7.0, 1.5, _ring_k), true)
