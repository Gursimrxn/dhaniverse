class_name EnergyPips
extends Control
## Energy as a row of pips that fill one by one: meals fill it. It shows what the server says and works nothing out for itself.

const PIPS := 10                   # ux02: ten pips, ten energy each
const PIP := Vector2(12, 7)        # the board's 13 x 8, on the 1280x720 canvas
const GAP := 2.5
const RADIUS := 4
const OFF := Color("3d3e3e")
const FILL := 0.32               # s a pip takes to fill
const FILL_STAGGER := 0.07       # s between pips, left to right
const BREATH := 1.6              # s each way, the last pip's breath

var _lit := PIPS
var _fill := PackedFloat32Array()  # how far across each pip is lit
var _breath := 1.0               # the last pip's opacity
var _heard := false
var _breathing: Tween
var _rising: Tween
var _pip := StyleBoxFlat.new()

func _ready() -> void:
	_fill.resize(PIPS)
	_fill.fill(1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PIPS * PIP.x + (PIPS - 1) * GAP, PIP.y)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pip.set_corner_radius_all(RADIUS)

## Newly lit pips fill left to right; at one pip left, that pip breathes.
func show_energy(energy: int) -> void:
	var lit := clampi(ceili(energy / 100.0 * PIPS), 0, PIPS)
	if lit != _lit:
		if _rising: _rising.kill()
		var moves := HudMotion.on and _heard      # the first word from the server is no change
		var from := _lit if moves else lit
		for i in PIPS: _fill[i] = 1.0 if i < mini(from, lit) else 0.0
		_rising = create_tween().set_parallel()
		for i in range(from, lit):
			_rising.tween_method(_fill_pip.bind(i), 0.0, 1.0, FILL).set_delay((i - from) * FILL_STAGGER).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_rising.tween_callback(queue_redraw)
		_lit = lit
	_heard = true
	_breathe(lit == 1 and HudMotion.on)
	queue_redraw()

func _fill_pip(v: float, i: int) -> void:
	_fill[i] = v
	queue_redraw()

func _breathe(on: bool) -> void:
	if on == (_breathing != null): return
	if not on:
		_breathing.kill()
		_breathing = null
		_breath = 1.0
		return
	_breathing = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breathing.tween_method(_set_breath, 1.0, 0.45, BREATH)
	_breathing.tween_method(_set_breath, 0.45, 1.0, BREATH)

func _set_breath(v: float) -> void:
	_breath = v
	queue_redraw()

func _draw() -> void:
	for i in PIPS:
		var x := i * (PIP.x + GAP)
		_pip.bg_color = OFF
		draw_style_box(_pip, Rect2(Vector2(x, 0), PIP))
		if _fill[i] <= 0.0: continue
		# the board's scaleX from the left edge
		_pip.bg_color = Color(Brand.GREEN, _breath if _lit == 1 else 1.0)
		draw_set_transform(Vector2(x, 0), 0.0, Vector2(_fill[i], 1.0))
		draw_style_box(_pip, Rect2(Vector2.ZERO, PIP))
		draw_set_transform(Vector2.ZERO)
