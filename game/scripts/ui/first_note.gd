class_name FirstNote
extends Control
## A small first, like a first meal: a line under the clock and a little confetti, over the scene. It doesn't cover anything or stop
## anything. The full blast (MilestoneBlast) is kept for the firsts that are really earned.

const TOP := 74.0                # px, under the clock
const LASTS := 3.2               # s
const FADE := 0.3                # s
const RISE := 12.0               # px
const PIECES := 26
const GRAVITY := 420.0

var _column := VBoxContainer.new()
var _title := Label.new()
var _line := Label.new()
var _t := -1.0
var _bits: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

var playing: bool:
	get: return _t >= 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	_column.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_column.add_theme_constant_override("separation", 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kicker := Label.new()
	kicker.text = "A NEW FIRST"
	for part in [[kicker, Brand.FONT_DISPLAY, 15], [_title, Brand.FONT_EDITORIAL, 50], [_line, Brand.FONT_BODY, 16]]:
		var l: Label = GameHud.on_scene(part[0], part[1], part[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_column.add_child(l)
	add_child(_column)
	visible = false

func show_note(title: String, line: String) -> void:
	_title.text = title
	_line.text = line
	_t = 0.0
	visible = true
	_bits.clear()
	var from := Vector2(size.x * 0.5, TOP + 40.0)
	for i in PIECES:
		_bits.append({"at": from + Vector2(_rng.randf_range(-120.0, 120.0), 0.0), "v": Vector2(_rng.randf_range(-260.0, 260.0), _rng.randf_range(-260.0, -60.0)),
			"spin": _rng.randf_range(-8.0, 8.0), "size": Vector2(_rng.randf_range(4, 8), _rng.randf_range(6, 11)), "colour": MilestoneBlast.CONFETTI_COLOURS[i % MilestoneBlast.CONFETTI_COLOURS.size()]})

func _process(delta: float) -> void:
	if _t < 0.0: return
	_t += delta
	if _t >= LASTS:
		_t = -1.0
		visible = false
		return
	for b in _bits:
		b.v.y += GRAVITY * delta
		b.at += b.v * delta
	modulate.a = minf(minf(_t / FADE, (LASTS - _t) / FADE), 1.0)
	_column.position.y = TOP + RISE * (1.0 - minf(_t / FADE, 1.0))
	queue_redraw()

func _draw() -> void:
	for b in _bits:
		draw_set_transform(b.at, b.spin * _t)
		draw_rect(Rect2(-b.size * 0.5, b.size), b.colour)
	draw_set_transform(Vector2.ZERO)
