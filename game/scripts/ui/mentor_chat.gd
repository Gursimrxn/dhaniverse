class_name MentorChat
extends Control
## The mentor: only ever reads your own story, and never changes anything. A short line surfaces in the corner when something
## real has happened; H opens the big chat, where the line types itself out and you can ask something back. Nothing pauses.

## Sizes are the design board's (GameDialogue), scaled from 1440x810 to 1280x720.
const PLATE_MARGIN := 98.0       # px from the screen's sides
const PLATE_HEIGHT := 258.0      # at least: the board's three answers fit it, our four rows make it taller
const PLATE_ABOVE := 100.0       # px from the screen's bottom
const BAR := 57.0                # the letterbox, each
const PORTRAIT := 133.0
const TEXT_AT := Vector2(204, 39)
const TEXT_WIDTH := 338.0
const ROWS_AT := Vector2(569, 28)
const ROW_GAP := 11.0
const INSET := 28.0              # the plate's padding at the right and bottom
const LINE := 1.25               # the mentor's line height, of its font size
const RISE := 21.0               # px the answers slide in from
const SHADE := Color("1b1c1c")   # the letterbox
const CAP_EDGE := Color("9d9477")
const TYPE_RATE := 45.0          # letters a second
const CORNER_FOR := 9.0          # s
const MAX_QUESTION := 200
const PROMPTS := ["What just happened to me?", "What should I look at next?", "Why did that cost so much?"]
const NAME := "Your mentor"
const TAGLINE := "Asks the annoying but valid questions."   # the board's "Your AI mentor." is left off: no model answers yet
const FACE := preload("res://assets/ui/mentor_face.png")

static var speaks_up := true     # off: lines wait for the player to open the chat

var client: TownClient
var is_open: bool:
	get: return _screen.visible

var _screen := Control.new()
var _plate := Panel.new()
var _text := Label.new()
var _caret := ColorRect.new()
var _rows: Array[PanelContainer] = []
var _field := LineEdit.new()
var _blink := 0.0
var _corner := PanelContainer.new()
var _corner_text := Label.new()
var _corner_left := 0.0
var _shown := 0.0
var _heard := "Nothing to talk about yet. Go and live a bit. I'll be here."
var _held: Array[String] = []    # lines waiting for a moment to finish
var _holding := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	_build_plate()
	_build_corner()
	resized.connect(func(): if is_open: _layout())
	if client: client.event.connect(_on_event)

func _plate_look(radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 6)
	return s

## The board's mentor screen: the scene dimmed under letterbox bars, and the plate with the portrait, the line and the answers.
func _build_plate() -> void:
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.visible = false
	add_child(_screen)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)    # the board's brightness(.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(dim)
	_build_bars()
	var look := _plate_look(25)
	look.shadow_offset = Vector2(0, 12)
	look.set_expand_margin_all(3)      # the outline sits outside the plate, as the board's ring does
	_plate.add_theme_stylebox_override("panel", look)
	_screen.add_child(_plate)
	_build_face()
	_text.position = TEXT_AT
	_text.size.x = TEXT_WIDTH
	_text.add_theme_font_override("font", Brand.FONT_BODY)
	_text.add_theme_color_override("font_color", Brand.CREAM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plate.add_child(_text)
	_caret.color = Brand.CREAM
	_caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_caret)
	for i in PROMPTS.size():
		var row := _row(str(i + 1), PhonePage.words(PROMPTS[i], 15, Brand.CREAM, false))
		row.mouse_entered.connect(_light.bind(row, true))
		row.mouse_exited.connect(_light.bind(row, false))
		row.gui_input.connect(_clicked.bind(PROMPTS[i]))
	# Typed questions are the last answer, with their own key.
	_field.placeholder_text = "Or ask anything."
	_field.max_length = MAX_QUESTION
	_field.add_theme_font_override("font", Brand.FONT_BODY)
	_field.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "focus", "read_only"]: _field.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_field.add_theme_color_override("caret_color", Brand.CREAM)
	_field.text_submitted.connect(_ask)
	var asking := _row(str(PROMPTS.size() + 1), _field)
	_field.focus_entered.connect(_light.bind(asking, true))
	_field.focus_exited.connect(_light.bind(asking, false))
	_light(asking, false)

func _clicked(e: InputEvent, question: String) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _ask(question)

func _build_bars() -> void:
	var top := _bar(Control.PRESET_TOP_WIDE)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 11)
	var mark := TextureRect.new()
	mark.texture = preload("res://assets/ui/coin_mark.svg")
	mark.modulate = Brand.CREAM
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(21, 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_child(mark)
	title.add_child(_centred(PhonePage.words("Mentor chat", 13, Brand.CREAM, false)))
	top.add_child(title)
	var legend := _bar(Control.PRESET_BOTTOM_WIDE)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 25)
	var answer_keys: Array[String] = []
	for i in PROMPTS.size() + 1: answer_keys.append(str(i + 1))
	for part in [[answer_keys, "Answer"], [["Space"], "Skip line"], [["Esc"], "Walk away"]]:
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 7)
		group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for key in part[0]: group.add_child(_cap(key))
		group.add_child(_centred(PhonePage.words(part[1], 12, Brand.CREAM, false)))
		legend.add_child(group)

## A letterbox bar, and the row that holds what's printed on it.
func _bar(preset: Control.LayoutPreset) -> HBoxContainer:
	var bar := ColorRect.new()
	bar.color = SHADE
	bar.set_anchors_and_offsets_preset(preset)
	if preset == Control.PRESET_TOP_WIDE: bar.offset_bottom = BAR
	else: bar.offset_top = -BAR
	_screen.add_child(bar)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 28
	line.offset_right = -28
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)
	return line

func _centred(label: Label) -> Label:
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## A key to press, as the board prints it: a cream cap with a darker edge under it.
func _cap(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.custom_minimum_size = Vector2(25, 25)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_override("font", Brand.FONT_DISPLAY)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Brand.PLATE)
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.CREAM
	look.border_color = CAP_EDGE
	look.border_width_bottom = 3
	look.expand_margin_bottom = 3      # the edge hangs under the cap, as the board's shadow does
	look.set_corner_radius_all(7)
	look.content_margin_left = 7
	look.content_margin_right = 7
	label.add_theme_stylebox_override("normal", look)
	return label

## One answer: a dark row with its key, on the plate's right.
func _row(key: String, body: Control) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 50
	var look := StyleBoxFlat.new()
	look.bg_color = PhonePage.ROW
	look.set_corner_radius_all(14)
	look.content_margin_left = 14
	look.content_margin_right = 14
	look.content_margin_top = 11
	look.content_margin_bottom = 11
	row.add_theme_stylebox_override("panel", look)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_cap(key))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(body)
	row.add_child(line)
	_rows.append(row)
	_plate.add_child(row)
	return row

## The board's hover: the row goes cream and its words dark.
func _light(row: PanelContainer, on: bool) -> void:
	(row.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Brand.CREAM if on else PhonePage.ROW
	var ink := Brand.PLATE if on else Brand.CREAM
	for words in row.find_children("", "Label", true, false):
		if words.custom_minimum_size.x != 25.0: words.add_theme_color_override("font_color", ink)   # not the key caps
	if _field.get_parent() and _field.get_parent().get_parent() == row:
		_field.add_theme_color_override("font_color", ink)
		_field.add_theme_color_override("font_placeholder_color", Color("5C5642") if on else PhonePage.MUTED)

## The round portrait in its cream ring, the name tag and the line under it, breaking out of the plate's top edge.
func _build_face() -> void:
	var ring := Panel.new()
	var ring_look := StyleBoxFlat.new()
	ring_look.bg_color = Color("FAFAF8")
	ring_look.border_color = Brand.CREAM
	ring_look.set_border_width_all(4)
	ring_look.set_expand_margin_all(4)
	ring_look.set_corner_radius_all(99)
	ring_look.shadow_color = Color(0, 0, 0, 0.35)
	ring_look.shadow_size = 12
	ring_look.shadow_offset = Vector2(0, 11)
	ring.add_theme_stylebox_override("panel", ring_look)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = Vector2(28, -50)
	ring.size = Vector2.ONE * PORTRAIT
	_plate.add_child(ring)
	var circle := TextureRect.new()
	circle.texture = FACE
	circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	circle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	circle.size = Vector2.ONE * PORTRAIT
	circle.material = _round_mask()
	ring.add_child(circle)
	var tag := Label.new()
	tag.text = NAME
	tag.add_theme_font_override("font", Brand.FONT_BODY)
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color.BLACK)
	var tag_look := StyleBoxFlat.new()
	tag_look.bg_color = Brand.MAGENTA
	tag_look.border_color = Brand.CREAM
	tag_look.set_border_width_all(3)
	tag_look.set_expand_margin_all(3)
	tag_look.set_corner_radius_all(99)
	tag_look.content_margin_left = 14
	tag_look.content_margin_right = 14
	tag_look.content_margin_top = 4
	tag_look.content_margin_bottom = 4
	tag.add_theme_stylebox_override("normal", tag_look)
	tag.position = Vector2(39, 96)
	_plate.add_child(tag)
	var about := PhonePage.words(TAGLINE, 12, Brand.CREAM_MUTED, false)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_theme_constant_override("line_spacing", roundi(12 * 1.4 - Brand.FONT_BODY.get_height(12)))
	about.position = Vector2(39, 139)
	about.size.x = 124
	_plate.add_child(about)

## The rows down the plate's right, and the plate grown to hold them.
func _layout() -> void:
	var width := size.x - PLATE_MARGIN * 2.0
	var y := ROWS_AT.y
	for row in _rows:
		row.size = Vector2(width - ROWS_AT.x - INSET, 0)   # shrinks to its own height
		row.position = Vector2(ROWS_AT.x, y)
		y += row.size.y + ROW_GAP
	var h := maxf(PLATE_HEIGHT, y - ROW_GAP + INSET)
	_plate.size = Vector2(width, h)
	_plate.position = Vector2(PLATE_MARGIN, size.y - PLATE_ABOVE - h)

func _round_mask() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment() { COLOR.a *= step(length(UV - vec2(0.5)), 0.5); }"
	var m := ShaderMaterial.new()
	m.shader = shader
	return m

const CORNER_AT := Vector2(21, 229)    # px from the right, and down: under the map's place name

## The notice is the island's mentor moment now (Island): the corner is never seen, and each time it would show, the line goes to
## the island and the corner is put away again, so the next line shows too.
func _build_corner() -> void:
	_corner.modulate.a = 0.0
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corner.visible = false
	add_child(_corner)
	_corner.visibility_changed.connect(func():
		if not _corner.visible: return
		_corner.hide.call_deferred()
		if Island.up: Island.up.mentor_says(_heard))

func _on_event(e: Dictionary) -> void:
	if e.type != "MentorSays" or e.get("account") != client.player: return
	if _holding: _held.append(str(e.text))
	else: hear(str(e.text))

## Hold lines back while a moment plays, so the thing is met first and named second. Pass false when the moment ends.
func hold_lines(on: bool) -> void:
	_holding = on
	if not on and not _held.is_empty(): hear(_held.pop_back())

func hear(line: String) -> void:
	_heard = line
	if is_open:
		_type_out()
	else:
		if not speaks_up: return
		_corner_left = CORNER_FOR
		_corner.visible = true

func toggle() -> void:
	_screen.visible = not _screen.visible
	if _screen.visible:
		_corner.visible = false
		_layout()
		_rise()
		_type_out()
	else:
		_field.release_focus()

## The answers slide in after the line has started, one after another, as on the board.
func _rise() -> void:
	for i in _rows.size():
		var row := _rows[i]
		var x := row.position.x
		row.position.x = x + RISE
		row.modulate.a = 0.0
		var t := row.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(row, "position:x", x, 0.4).set_delay(0.3 + i * 0.08)
		t.tween_property(row, "modulate:a", 1.0, 0.4).set_delay(0.3 + i * 0.08)

## A long line is set smaller until it fits the plate: the board's size is for a short one.
func _type_out() -> void:
	_text.text = _heard
	var font := Brand.FONT_BODY
	var room := _plate.size.y - TEXT_AT.y - INSET
	var px := 27
	while px > 14 and font.get_multiline_string_size(_heard, HORIZONTAL_ALIGNMENT_LEFT, TEXT_WIDTH, px).y / font.get_height(px) * px * LINE > room:
		px -= 1
	_text.add_theme_font_size_override("font_size", px)
	_text.add_theme_constant_override("line_spacing", roundi(px * LINE - font.get_height(px)))
	_text.size = Vector2(TEXT_WIDTH, 0)
	_shown = 0.0
	_text.visible_characters = 0

## The board's block caret, blinking just after the last letter shown, sized with the line.
func _place_caret() -> void:
	var px := _text.get_theme_font_size("font_size")
	_caret.size = Vector2(9, 23) * px / 27.0
	var n := int(_shown)
	var at := TEXT_AT + Vector2(0, (px * LINE - _caret.size.y) * 0.5)
	if n > 0:
		var letter := _text.get_character_bounds(n - 1)
		at = TEXT_AT + Vector2(letter.end.x + 4, letter.get_center().y - _caret.size.y * 0.5)
	_caret.position = at
	_caret.visible = _blink < 0.5

func _ask(question: String) -> void:
	if question.strip_edges() == "": return
	client.send({"type": "AskMentor", "question": question})
	_field.text = ""
	_field.release_focus()

func _process(delta: float) -> void:
	if is_open:
		_shown = minf(_shown + delta * TYPE_RATE, _text.text.length())
		_text.visible_characters = int(_shown)
		_blink = fmod(_blink + delta, 1.0)
		_place_caret()
	if _corner.visible:
		_corner_left -= delta
		_corner.visible = _corner_left > 0.0
		_corner.reset_size()
		_corner.position = Vector2(size.x - _corner.size.x - CORNER_AT.x, CORNER_AT.y)

func _input(e: InputEvent) -> void:
	if not e is InputEventKey or PaperSheet.is_typing(self) and e.keycode != KEY_ESCAPE: return
	if not e.is_pressed() or e.is_echo(): return
	if e.keycode == KEY_H or (e.keycode == KEY_ESCAPE and is_open):   # Esc must always get out, from the text field too
		toggle()
	elif is_open and e.keycode >= KEY_1 and e.keycode < KEY_1 + PROMPTS.size():
		_ask(PROMPTS[e.keycode - KEY_1])
	elif is_open and e.keycode == KEY_1 + PROMPTS.size():
		_field.grab_focus()
	elif is_open and e.keycode == KEY_SPACE:
		_shown = _text.text.length()
	else:
		return
	get_viewport().set_input_as_handled()
