class_name PlayerFace
extends Control
## The round portrait at the head of the HUD, with its ring: how much energy is left, at a glance. The ring draws outside the
## portrait's box, as on the board, so the plates beside it line up with the face itself.

const SIZE := 82.0
const RING_R := 48.0             # px from the middle, as the board's r 54 of 116
const RING_W := 5.0
const RING := Color("55C06C")
const BACK := Color("BFE3F0")
const FACE := preload("res://assets/ui/player_face.png")

var _fill := 1.0

func _ready() -> void:
	custom_minimum_size = Vector2.ONE * SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := TextureRect.new()
	circle.texture = FACE
	circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	circle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	circle.size = Vector2.ONE * SIZE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment() { COLOR.a *= smoothstep(0.5, 0.49, length(UV - vec2(0.5))); }"
	var round_it := ShaderMaterial.new()
	round_it.shader = shader
	circle.material = round_it
	add_child(circle)

func set_fill(part: float) -> void:
	_fill = clampf(part, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var mid := size * 0.5
	for i in 6:    # the board's soft shadow under the portrait
		draw_circle(mid + Vector2(0, 9), SIZE * 0.5 + 4.0 + i * 2.0, Color(0, 0, 0, 0.05))
	draw_circle(mid, SIZE * 0.5 + 4.0, Brand.CREAM)
	draw_circle(mid, SIZE * 0.5, BACK)
	draw_arc(mid, RING_R, 0.0, TAU, 64, Brand.PLATE, RING_W, true)
	if _fill <= 0.0: return
	var end := -PI * 0.5 + TAU * _fill
	draw_arc(mid, RING_R, -PI * 0.5, end, 64, RING, RING_W, true)
	for a in [-PI * 0.5, end]:    # round caps
		draw_circle(mid + Vector2.from_angle(a) * RING_R, RING_W * 0.5, RING)
