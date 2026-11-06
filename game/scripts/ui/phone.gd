class_name Phone
extends Control
## Your phone: the town's feed, your quest log, your wallet, the town together (its goal, the weekly draw, the Rush boards) and your card.
## Tab takes it out and puts it away. Nothing pauses: you can walk with it in your hand. While it's out the mouse should be free, for
## pressing things on it: `toggled` says when.

signal toggled(out: bool)

const SIZE := Vector2(340, 600)   # the most it grows to
const MARGIN := 21.0
## What it keeps clear of, on the 1280x720 canvas every screen is drawn at (canvas_items, expand): the island at the top, the minimap's
## column on the right (its plate and the place name under it, with the keys below them), and the slot bar at the bottom.
const CLEAR_TOP := 104.0
const CLEAR_RIGHT := 21.0 + 167.0 + 3.0 + 40.0    # the minimap's edge, its plate, its rim, room for the tilt
const CLEAR_BOTTOM := 16.0         # the slot bar fades while the phone is out: its pages are on the phone's own tabs
const TILT := -2.0                 # degrees: held in the hand, not pinned to the screen
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
	var look := StyleBoxFlat.new()     # the body: dark, a cream ring, as every plate
	look.bg_color = Color("111111")
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_corner_radius_all(44)
	look.set_content_margin_all(10)
	look.shadow_color = Color(0, 0, 0, 0.45)
	look.shadow_size = 26
	look.shadow_offset = Vector2(0, 14)
	_frame.add_theme_stylebox_override("panel", look)
	_frame.custom_minimum_size = SIZE
	var screen := PanelContainer.new()  # the screen: the landing's light look
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color("FBFBF9")
	glass.set_corner_radius_all(35)
	glass.content_margin_left = 14
	glass.content_margin_right = 14
	glass.content_margin_top = 14
	glass.content_margin_bottom = 12
	screen.add_theme_stylebox_override("panel", glass)
	_frame.add_child(screen)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_theme_constant_override("separation", 2)
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	var tray := PanelContainer.new()    # the tabs sit in a soft tray at the top, as on the design
	var tray_look := StyleBoxFlat.new()
	tray_look.bg_color = Color(0, 0, 0, 0.06)
	tray_look.set_corner_radius_all(99)
	tray_look.set_content_margin_all(4)
	tray.add_theme_stylebox_override("panel", tray_look)
	tray.add_child(_tabs)
	column.add_child(tray)
	column.add_child(_scroll)
	screen.add_child(column)
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
		var c := PhonePage.chip("%d %s" % [i + 1, _names[i]], i == _current)
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
	_frame.pivot_offset = at.size * 0.5
	_frame.rotation_degrees = TILT
	var shown := at.position
	var hidden := Vector2(shown.x, size.y + MARGIN)
	if _tween: _tween.kill()
	_tween = create_tween()
	_frame.position = hidden if is_open else _frame.position
	_tween.tween_property(_frame, "position", shown if is_open else hidden, SLIDE * 1.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
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
