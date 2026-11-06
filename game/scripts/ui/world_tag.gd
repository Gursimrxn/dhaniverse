class_name WorldTag
extends Control
## Stays over a point in the world at a constant size. What it shows: OrderBubble, KeyHint.

const FAR := 12.0                # m from the camera: beyond this it stays out of the way, and doesn't show through walls

var at := Vector3.ZERO           # the point in the world it sits over

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(_delta: float) -> void:
	if not visible: return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(at) or cam.global_position.distance_to(at) > FAR:
		modulate.a = 0.0
		return
	modulate.a = 1.0
	position = cam.unproject_position(at) - Vector2(size.x * 0.5, size.y)

## A plate with a tail pointing down at the thing: tail is half its width, and its height.
func _draw_speech(look: StyleBoxFlat, tail: Vector2) -> void:
	var bottom := size.y - tail.y
	var mid := size.x * 0.5
	var edge := look.get_border_width(SIDE_BOTTOM)
	draw_style_box(look, Rect2(0, 0, size.x, bottom))
	draw_colored_polygon(PackedVector2Array([Vector2(mid - tail.x - 2, bottom - edge), Vector2(mid + tail.x + 2, bottom - edge), Vector2(mid, size.y + 2)]), look.border_color)
	draw_colored_polygon(PackedVector2Array([Vector2(mid - tail.x, bottom - edge), Vector2(mid + tail.x, bottom - edge), Vector2(mid, size.y - 3)]), look.bg_color)
