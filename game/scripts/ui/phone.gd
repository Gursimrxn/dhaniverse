class_name Phone
extends Control
## Your phone (ux10): your wallet, your quests, the town's feed and the town together (its goal, the weekly draw, the Rush boards), on
## the tabs in the order of the pocket's keys 1 to 4. Tab takes it out and puts it away. Nothing pauses: you can walk with it in your
## hand. While it's out the mouse should be free, for pressing things on it: `toggled` says when.

signal toggled(out: bool)

## Where the board holds it, on the 1280x720 canvas (ux10's 392 x 790 at 120 px from the right and 70 from the top, scaled): in your
## hand, running off the bottom of the screen. The island, the map and the pocket step away while it's out (GameHud).
const SIZE := Vector2(348, 702)
const RIGHT := 107.0
const TOP := 62.0
const BELOW := 44.0                # px of it under the screen's bottom edge: its pages keep this much clear at their end
const MARGIN := 21.0
const TILT := -3.0                 # degrees: held in the hand, not pinned to the screen
const SLIDE := 0.18              # s

var client: TownClient
var is_open := false
var town_pass := Callable()        # asks for a Town Pass link: the wallet page's button

var _frame := PanelContainer.new()
var _scroll := ScrollContainer.new()
var _tabs := HBoxContainer.new()
var _pages: Array[PhonePage] = [PhoneWallet.new(), PhoneQuests.new(), PhoneFeed.new(), PhoneTown.new()]
var _names := ["Wallet", "Quests", "Feed", "Town"]
const PAGES := {"wallet": 0, "quests": 1, "feed": 2, "town": 3}
var _shade := TextureRect.new()    # the board's darkening towards the screen's right, behind the phone
var _current := 0
var _tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := StyleBoxFlat.new()     # the body: dark, a cream ring, as every plate
	look.bg_color = Color("111111")
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_corner_radius_all(48)
	look.set_content_margin_all(11)
	look.shadow_color = Color(0, 0, 0, 0.45)
	look.shadow_size = 26
	look.shadow_offset = Vector2(0, 14)
	_frame.add_theme_stylebox_override("panel", look)
	_frame.custom_minimum_size = SIZE
	var screen := PanelContainer.new()  # the screen: the landing's light look
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color("FBFBF9")
	glass.set_corner_radius_all(39)
	glass.content_margin_left = 16
	glass.content_margin_right = 16
	glass.content_margin_top = 18
	glass.content_margin_bottom = 12 + BELOW
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
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.35))
	g.add_point(0.45, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	_shade.texture = tex
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.modulate.a = 0.0
	add_child(_shade)
	_frame.visible = false
	add_child(_frame)
	for page in _pages:
		page.client = client
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(_pages[PAGES.feed] as PhoneFeed).listen()
	(_pages[PAGES.town] as PhoneTown).listen()
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
	(_pages[PAGES.wallet] as PhoneWallet).town_pass = town_pass
	is_open = not is_open
	if is_open:
		_pages[_current].refresh()
		_frame.visible = true
	toggled.emit(is_open)
	_slide()

## A page, to hand it what it needs from the town (the guide, the crate).
func page(name: String) -> PhonePage:
	return _pages[PAGES[name]]

## Where it sits when out, as on the board; on a screen made smaller by a bigger text size, the phone shrinks with it to stay in hand.
func frame_rect(screen: Vector2) -> Rect2:
	var k := clampf(screen.y / 720.0, 0.6, 1.0)
	_frame.scale = Vector2.ONE * k
	return Rect2(Vector2(screen.x - (RIGHT + SIZE.x) * k, TOP * k), SIZE)

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
	create_tween().tween_property(_shade, "modulate:a", 1.0 if is_open else 0.0, SLIDE * 1.6)

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
		if not is_open and not Screens.free_to_open(): return     # never over the board, a sheet or the pause menu
		toggle()
	else:
		return
	get_viewport().set_input_as_handled()

## Show one page ("wallet", "quests", "feed", "town"): take the phone out if it's away, and put it away if that page is already
## showing.
func open_page(page: String) -> void:
	if not is_open and not Screens.free_to_open(): return
	var i: int = PAGES[page]
	if is_open and i == _current:
		toggle()
		return
	_show_page(i)
	if not is_open: toggle()
