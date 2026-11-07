class_name KeyHint
extends WorldTag
## A key and what it does, on the thing in reach, as on the design board: a green plate with a tail pointing at the thing. With no key
## it's a plain remark, on the dark plate.

const CAP_EDGE := Color("9d9477")
const LEARNED_AFTER := 4         # times shown before the words go, and the key alone is enough
const TAIL := Vector2(9, 11)      # half its width, and its height
const TAIL_GAP := 1.0
const RING := 3.0                # the cream ring, drawn outside the plate
const MARGIN := Vector2(7, 7)
const POP := 0.22                # s it takes to pop in
const TAIL_AFTER := 0.12         # s after the pop starts, the tail drops in
const TAIL_DROP := 7.0           # px it drops
const SINK := 2.0                # px the cap sinks when its key is pressed

static var _shown := {}          # a hint's first word -> how many times it has come up
static var enabled := true       # the player can turn key hints off in settings; remarks with no key still show
var name_tag := false             # ux02: a person's tag, magenta with black words, never a key
var always_words := false        # words that change with what's there (a quest's step): never learned away

var _row := HBoxContainer.new()
var _cap := Label.new()
var _words := Label.new()
var _plate := StyleBoxFlat.new()
var _last := ""
var _cap_look := StyleBoxFlat.new()
var _tail := 1.0                 # how far the tail has dropped in
var _pop: Tween

func _init() -> void:
	super()
	_plate.bg_color = Brand.GREEN
	_plate.border_color = Brand.CREAM
	_plate.set_border_width_all(3)
	_plate.set_corner_radius_all(99)
	Brand.as_plate(_plate)
	var cap := _cap_look
	cap.bg_color = Brand.CREAM
	cap.border_color = CAP_EDGE
	cap.border_width_bottom = 3
	cap.set_corner_radius_all(7)
	cap.content_margin_left = 7
	cap.content_margin_right = 7
	_cap.add_theme_stylebox_override("normal", cap)
	_cap.add_theme_font_override("font", Brand.FONT_DISPLAY)
	_cap.add_theme_font_size_override("font_size", 12)
	_cap.add_theme_color_override("font_color", Brand.PLATE)
	_cap.custom_minimum_size = Vector2(25, 25)
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_words.add_theme_font_override("font", Brand.FONT_BODY)
	_words.add_theme_font_size_override("font_size", 15)
	_words.add_theme_color_override("font_color", Color.WHITE)
	_row.add_theme_constant_override("separation", 11)
	_row.add_child(_cap)
	_row.add_child(_words)
	add_child(_row)

## Empty words hide it. An empty key leaves just the words: nothing to press, only something to know.
func show_hint(key: String, words: String) -> void:
	var was := visible
	visible = words != "" and (enabled or key == "")
	set_process_input(visible and key != "")
	if not visible:
		_last = ""
		return
	_cap.visible = key != ""
	_cap.text = key
	_words.text = words
	if key != "":
		var verb := words.get_slice(" ", 0)
		if words != _last: _shown[verb] = int(_shown.get(verb, 0)) + 1
		_words.visible = always_words or int(_shown[verb]) <= LEARNED_AFTER
	else:
		_words.visible = true
	_last = words
	_plate.bg_color = Brand.GREEN if key != "" else (Brand.MAGENTA if name_tag else Brand.PLATE)
	_words.add_theme_color_override("font_color", Color.BLACK if name_tag and key == "" else Color.WHITE)
	_words.add_theme_font_size_override("font_size", 13 if name_tag and key == "" else 15)
	# the board's .8rem round the key and 1.6rem after the words
	var lead := MARGIN if key != "" else (Vector2(10, 4) if name_tag else Vector2(16, 6))
	var trail := (MARGIN.x * 2.0 if _words.visible else MARGIN.x) if key != "" else (10.0 if name_tag else 16.0)
	_row.position = lead
	_row.reset_size()
	size = _row.get_combined_minimum_size() + Vector2(lead.x + trail, lead.y * 2.0 + RING + TAIL_GAP + TAIL.y)
	pivot_offset = Vector2(size.x * 0.5, size.y)
	if not was: _pop_in()
	queue_redraw()

## Coming into reach: the plate pops in from .8 with a little overshoot, and the tail drops in just after it. WorldTag owns modulate,
## so the fade is on the plate's own drawing and on the row.
func _pop_in() -> void:
	if _pop: _pop.kill()
	if not HudMotion.on:
		scale = Vector2.ONE
		self_modulate.a = 1.0
		_row.modulate.a = 1.0
		_tail = 1.0
		return
	scale = Vector2.ONE * 0.8
	self_modulate.a = 0.0
	_row.modulate.a = 0.0
	_tail = 0.0
	_pop = create_tween().set_parallel()
	_pop.tween_property(self, "scale", Vector2.ONE, POP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(self, "self_modulate:a", 1.0, POP * 0.6)
	_pop.tween_property(_row, "modulate:a", 1.0, POP * 0.6)
	_pop.tween_method(_drop_tail, 0.0, 1.0, POP).set_delay(TAIL_AFTER).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _drop_tail(v: float) -> void:
	_tail = v
	queue_redraw()

## Its key pressed: the cap sinks onto its lip and comes back up.
func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo or not _cap.visible: return
	if OS.get_keycode_string(k.keycode if k.keycode != KEY_NONE else k.physical_keycode) != _cap.text: return
	if not HudMotion.on: return
	var t := create_tween()
	t.tween_method(_sink, 0.0, 1.0, 0.05)
	t.tween_interval(0.08)
	t.tween_method(_sink, 1.0, 0.0, 0.1)

func _sink(v: float) -> void:
	var d := roundi(SINK * v)
	_cap_look.expand_margin_top = -d
	_cap_look.expand_margin_bottom = d
	_cap_look.border_width_bottom = 3 - d
	_cap_look.content_margin_top = d * 2

## The plate, its ring outside it as on the board, then the board's tail: a cream triangle of its own, just under the ring.
func _draw() -> void:
	var bottom := size.y - TAIL.y - TAIL_GAP - RING
	var mid := size.x * 0.5
	draw_style_box(_plate, Rect2(0, 0, size.x, bottom))
	var y := bottom + RING + TAIL_GAP - TAIL_DROP * (1.0 - _tail)
	draw_colored_polygon(PackedVector2Array([Vector2(mid - TAIL.x, y), Vector2(mid + TAIL.x, y), Vector2(mid, y + TAIL.y)]), Color(Brand.CREAM, clampf(_tail, 0.0, 1.0)))
