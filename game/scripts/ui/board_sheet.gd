class_name BoardSheet
extends Control
## A sheet held up from something in the world, when what's on it earns the screen: the Bounty Board's cards, the exchange kiosk's swap,
## the Price Call, the sign you write on your name, what was in your chest. Printed paper (PaperSheet) with a kicker, a headline, a few
## lines, rows to choose between with the arrow keys, a note for what the server said back, and the keys under it. Nothing pauses behind
## it; the player stands still while it's up. Enter does the chosen row (`chosen`), Esc puts it away.

signal chosen(i: int)
signal closed
signal key_pressed(keycode: int)   # one of the keys added with add_key()

const DOT := Color("FF6600")
static var _open := 0               # how many are up: world.gd keeps the mouse free while any is

var player: CharacterBody3D
var pick := 0
var is_open: bool:
	get: return _sheet.visible
var keys_free := false              # a text field on it takes the letters (the sign)

var _sheet: PaperSheet
var _kicker: Label
var _head: Label
var _intro: Label
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()   # the rows, when there are more than the screen holds
var _extra := VBoxContainer.new()   # anything a caller puts under the rows
var _note: Label
var _items: Array = []
var _go: PaperSheet.Pill
var _rows_on := true
var _keys := {}                     # keycode -> true: keys of the sheet's own, beside Enter and Esc

static func any_open() -> bool:
	return _open > 0

func _init(width := 760.0, go_words := "Choose") -> void:
	_sheet = PaperSheet.new(width)
	var w := _sheet.text_width()
	_kicker = PaperSheet.caption("")
	_head = PaperSheet.words("", Brand.FONT_EDITORIAL, 44, w)
	_intro = PaperSheet.words("", Brand.FONT_PROSE, 18, w)
	_note = PaperSheet.words("", Brand.FONT_BODY, 16, w)
	_note.add_theme_color_override("font_color", Color("c44d00"))
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for part in [_kicker, _head, _intro]: top.add_child(part)
	_rows.add_theme_constant_override("separation", 2)
	_extra.add_theme_constant_override("separation", 10)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_rows)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part in [top, _scroll, _extra, _note]: _sheet.page.add_child(part)
	_go = PaperSheet.Pill.new("Enter", go_words)
	_sheet.actions.add_child(_go)
	_sheet.actions.add_child(PaperSheet.Pill.new("Esc", "Leave", true))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	add_child(_sheet)

func set_words(kicker: String, head: String, intro := "") -> void:
	_kicker.text = kicker.to_upper()
	_head.text = head
	_intro.text = intro
	_intro.visible = intro != ""

func set_go(words: String) -> void:
	(_go.get_child(0).get_child(1) as Label).text = words
	_go.visible = words != ""

## Another key under the sheet, between Enter's and Esc's: pressing it sends key_pressed. Returns its pill, for its words.
func add_key(keycode: int, cap: String, words: String) -> PaperSheet.Pill:
	var pill := PaperSheet.Pill.new(cap, words, true)
	_sheet.actions.add_child(pill)
	_sheet.actions.move_child(pill, 1)
	_keys[keycode] = true
	return pill

static func pill_words(pill: PaperSheet.Pill, words: String) -> void:
	(pill.get_child(0).get_child(1) as Label).text = words

func extra() -> VBoxContainer:
	return _extra

func say(text: String, warm := true) -> void:
	_note.text = text
	_note.visible = text != ""
	_note.add_theme_color_override("font_color", Color("c44d00") if warm else Brand.GREEN)

## items: {title, sub, figure, figure_sub, badge, dim}. The choice stays on the same row where it can.
func set_rows(items: Array) -> void:
	_items = items
	_rows_on = not items.is_empty()
	pick = clampi(pick, 0, maxi(items.size() - 1, 0))
	_draw_rows()

func open() -> void:
	if not _sheet.visible: _open += 1
	_extra.visible = _extra.get_child_count() > 0
	_sheet.open()
	if player: player.frozen = true
	say("")

func close() -> void:
	if not _sheet.visible: return
	_open -= 1
	_sheet.close()
	if player:
		player.frozen = false
		if player.rig: player.rig.take_cursor_back()
	closed.emit()

func _exit_tree() -> void:
	if _sheet and _sheet.visible: _open -= 1

func _input(e: InputEvent) -> void:
	if not _sheet.visible or not e is InputEventKey or not e.pressed or e.echo: return
	if keys_free and not e.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]: return
	if _keys.has(e.keycode):
		key_pressed.emit(e.keycode)
		get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_UP, KEY_W: _choose(pick - 1)
		KEY_DOWN, KEY_S: _choose(pick + 1)
		KEY_ENTER, KEY_KP_ENTER: chosen.emit(pick)
		KEY_ESCAPE: close()
		_: return
	get_viewport().set_input_as_handled()

func _choose(i: int) -> void:
	if _items.is_empty(): return
	pick = clampi(i, 0, _items.size() - 1)
	say("")
	_draw_rows()

func _draw_rows() -> void:
	for old in _rows.get_children():
		_rows.remove_child(old)
		old.queue_free()
	_scroll.visible = _rows_on
	var w := _sheet.text_width()
	for i in _items.size():
		var it: Dictionary = _items[i]
		var row := MarginContainer.new()
		row.add_theme_constant_override("margin_left", 22)
		row.add_theme_constant_override("margin_right", 16)     # clear of the scroll bar
		row.add_theme_constant_override("margin_top", 7)
		row.add_theme_constant_override("margin_bottom", 7)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.modulate.a = 1.0 if i == pick else (0.35 if it.get("dim", false) else 0.6)
		if i == pick: row.draw.connect(func(): row.draw_circle(Vector2(7, 19), 5.0, DOT))
		row.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if pick == i and e.double_click: chosen.emit(i)
				else: _choose(i))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 2)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(PaperSheet.words(str(it.get("title", "")), Brand.FONT_BODY, 21))
		if str(it.get("badge", "")) != "": title_row.add_child(_badge(str(it.badge)))
		left.add_child(title_row)
		var told := str(it.get("sub", ""))
		if i == pick and str(it.get("story", "")) != "": told += ("\n" if told != "" else "") + str(it.story)     # the chosen one tells its story
		if told != "":
			var sub := PaperSheet.words(told, Brand.FONT_BODY, 14, w - 230.0)
			sub.add_theme_color_override("font_color", PaperSheet.MUTED)
			left.add_child(sub)
		line.add_child(left)
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 0)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fig := PaperSheet.words(str(it.get("figure", "")), Brand.FONT_DISPLAY, 22)
		fig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(fig)
		if str(it.get("figure_sub", "")) != "":
			var fs := PaperSheet.words(str(it.figure_sub), Brand.FONT_BODY, 13)
			fs.add_theme_color_override("font_color", PaperSheet.MUTED)
			fs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(fs)
		line.add_child(right)
		row.add_child(line)
		_rows.add_child(row)
	_fit_rows.call_deferred()

## The rows scroll past about half the screen's height, the chosen one kept in view.
func _fit_rows() -> void:
	var most := get_viewport_rect().size.y * 0.5
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, most)
	if pick < _rows.get_child_count(): _scroll.ensure_control_visible(_rows.get_child(pick))

## A small stamp beside a row's title: "on Arkiv", "taken", "pending".
static func _badge(text: String) -> Label:
	var l := PaperSheet.words(text.to_upper(), PaperSheet.spaced(Brand.FONT_BODY, 10, 0.08), 10)
	var look := StyleBoxFlat.new()
	look.bg_color = Color.TRANSPARENT
	look.border_color = Brand.GREEN if text != "pending" else Color("c44d00")
	look.set_border_width_all(2)
	look.set_corner_radius_all(5)
	look.content_margin_left = 6
	look.content_margin_right = 6
	look.content_margin_top = 1
	look.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", look)
	l.add_theme_color_override("font_color", look.border_color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l
