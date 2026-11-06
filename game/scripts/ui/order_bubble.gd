class_name OrderBubble
extends WorldTag
## What a customer wants, as a picture: no reading in a rush. The one at the counter is large; the ones waiting are small,
## so their bubbles don't cover each other and you can still plan ahead. A refusal turns it orange and says so.

const ICON_FRONT := 40.0
const ICON_WAITING := 20.0
const TAIL := Vector2(9, 8)      # half its width, its height
const OUTLINE := 3
const POP := 0.16                # s

var _row := HBoxContainer.new()
var _icon := TextureRect.new()
var _words := Label.new()
var _plate := StyleBoxFlat.new()
var _front := false

func _init() -> void:
	super()
	_plate.bg_color = Brand.PLATE
	_plate.border_color = Brand.CREAM
	_plate.set_border_width_all(OUTLINE)
	_plate.set_corner_radius_all(14)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_row.add_theme_constant_override("separation", 6)
	_row.add_child(_icon)
	_words.add_theme_font_override("font", Brand.FONT_BODY)
	_words.add_theme_font_size_override("font_size", 18)
	_words.add_theme_color_override("font_color", Color.BLACK)
	_row.add_child(_words)
	add_child(_row)

## Shows the order. front: this customer is at the counter.
func show_order(icon: Texture2D, front: bool) -> void:
	var grew := front and not _front
	var appeared := not visible
	_front = front
	_icon.texture = icon
	_words.visible = false
	_plate.bg_color = Brand.PLATE
	_lay_out(ICON_FRONT if front else ICON_WAITING, 8 if front else 5)
	visible = true
	if grew or appeared: _pop()

## Says something instead, for a moment: the caller goes back to show_order.
func say(words: String) -> void:
	_words.text = words
	_words.visible = true
	_plate.bg_color = Brand.ORANGE
	_lay_out(ICON_FRONT * 0.7, 8)

func clear() -> void:
	visible = false

func _lay_out(icon_size: float, margin: int) -> void:
	_icon.custom_minimum_size = Vector2.ONE * icon_size
	_row.position = Vector2.ONE * margin
	_row.reset_size()
	var body := _row.get_combined_minimum_size() + Vector2.ONE * margin * 2.0
	size = body + Vector2(0, TAIL.y)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	queue_redraw()

func _pop() -> void:
	scale = Vector2.ONE * 0.7
	create_tween().tween_property(self, "scale", Vector2.ONE, POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	_draw_speech(_plate, TAIL)
