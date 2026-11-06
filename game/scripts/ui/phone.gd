class_name Phone
extends Control
## Your phone: the town's feed, your quest log, your wallet, the town together (its goal, the weekly draw, the Rush boards) and your card.
## Tab takes it out and puts it away. Nothing pauses: you can walk with it in your hand. While it's out the mouse should be free, for
## pressing things on it: `toggled` says when.

signal toggled(out: bool)

const SIZE := Vector2(348, 590)   # the most it grows to
const MARGIN := 21.0
## What it keeps clear of, on the 1280x720 canvas every screen is drawn at (canvas_items, expand): the island at the top, the minimap's
## column on the right (its plate and the place name under it, with the keys below them), and the slot bar at the bottom.
const CLEAR_TOP := 100.0
const CLEAR_RIGHT := 21.0 + 167.0 + 3.0 + 14.0    # the minimap's edge, its plate, its rim, a gap
const CLEAR_BOTTOM := 21.0 + 102.0 + 13.0         # the bar's edge, the bar with its name over it, a gap
const SLIDE := 0.18              # s

var client: TownClient
var is_open := false
var town_pass := Callable()        # asks for a Town Pass link: the wallet page's button

var _frame := PanelContainer.new()
var _scroll := ScrollContainer.new()
var _tabs := HBoxContainer.new()
var _pages: Array[PhonePage] = [PhoneFeed.new(), PhoneQuests.new(), PhoneWallet.new(), PhoneTown.new(), PhoneProfile.new()]
var _names := ["Feed", "Quests", "Wallet", "Town", "Me"]
const PAGES := {"feed": 0, "quests": 1, "wallet": 2, "town": 3, "me": 4}
var _current := 0
var _tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_corner_radius_all(26)
	look.content_margin_left = 18
	look.content_margin_right = 18
	look.content_margin_top = 16
	look.content_margin_bottom = 14
	look.shadow_color = Color(0, 0, 0, 0.3)
	look.shadow_size = 16
	look.shadow_offset = Vector2(0, 8)
	_frame.add_theme_stylebox_override("panel", look)
	_frame.custom_minimum_size = SIZE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_theme_constant_override("separation", 3)
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_scroll)
	column.add_child(_tabs)
	_frame.add_child(column)
	_frame.visible = false
	add_child(_frame)
	for page in _pages:
		page.client = client
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(_pages[0] as PhoneFeed).listen()
	(_pages[3] as PhoneTown).listen()
	(_pages[4] as PhoneProfile).listen()
	if client:
		client.you_changed.connect(_refresh)
		client.city_changed.connect(_refresh)
		client.synced.connect(_refresh)
	_build_tabs()
	_show_page(0)

func _build_tabs() -> void:
	for old in _tabs.get_children():
		_tabs.remove_child(old)
		old.queue_free()
	for i in _names.size():
		var c := PhonePage.chip(_names[i], i == _current)
		c.pressed.connect(_show_page.bind(i))
		_tabs.add_child(c)

func _show_page(i: int) -> void:
	if _scroll.get_child_count() > 0: _scroll.remove_child(_scroll.get_child(0))
	_current = i
	_scroll.add_child(_pages[i])
	_build_tabs()
	_pages[i].refresh()

func _refresh() -> void:
	if is_open and not PaperSheet.is_typing(self): _pages[_current].refresh()     # never from under someone writing

func toggle() -> void:
	(_pages[2] as PhoneWallet).town_pass = town_pass
	is_open = not is_open
	if is_open:
		_pages[_current].refresh()
		_frame.visible = true
	toggled.emit(is_open)
	_slide()

## Where it sits when out: left of the minimap's column, between the island and the slot bar, as tall as that leaves.
func frame_rect(screen: Vector2) -> Rect2:
	var h := minf(SIZE.y, screen.y - CLEAR_TOP - CLEAR_BOTTOM)
	return Rect2(Vector2(screen.x - CLEAR_RIGHT - SIZE.x, screen.y - CLEAR_BOTTOM - h), Vector2(SIZE.x, h))

func _slide() -> void:
	var at := frame_rect(size)
	_frame.custom_minimum_size = at.size
	_frame.size = at.size
	var shown := at.position
	var hidden := Vector2(shown.x, size.y + MARGIN)
	if _tween: _tween.kill()
	_tween = create_tween()
	_frame.position = hidden if is_open else _frame.position
	_tween.tween_property(_frame, "position", shown if is_open else hidden, SLIDE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not is_open: _tween.tween_callback(func(): _frame.visible = false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_open and _frame:
		var at := frame_rect(size)
		_frame.custom_minimum_size = at.size
		_frame.size = at.size
		_frame.position = at.position

func _input(e: InputEvent) -> void:
	if not e is InputEventKey or PaperSheet.is_typing(self) and e.keycode != KEY_ESCAPE: return
	if not e.is_pressed() or e.is_echo(): return
	if e.keycode == KEY_TAB or (e.keycode == KEY_ESCAPE and is_open):
		toggle()
	else:
		return
	get_viewport().set_input_as_handled()

## Show one page ("feed", "quests", "wallet", "town", "me"): take the phone out if it's away, and put it away if that page is already
## showing.
func open_page(page: String) -> void:
	var i: int = PAGES[page]
	if is_open and i == _current:
		toggle()
		return
	_show_page(i)
	if not is_open: toggle()
