class_name PauseMenu
extends Control
## Esc in the town: the shot holds, the film bars close in, the camera eases aside and the menu sits in shadow on the left, in the
## same words as the title and Settings. The town carries on (it's shared); you just stop. Esc again, or Resume, goes back.

const OPEN_TIME := 0.45            # s
const EASE_ASIDE := -0.7           # m, the camera's horizontal offset: the town slides right of the menu

var world: Node
var cinema: Cinema
var settings: SettingsPanel
var is_open := false

var _shadow := TextureRect.new()
var _ui := Control.new()
var _list := VBoxContainer.new()
var _where := Label.new()
var _items: Array[Dictionary] = []
var _words: Array[MenuWord] = []
var _chosen := 0
var _to_settings := false          # Settings was opened from here: closing it comes back here

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 34
	visible = false
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.04, 0.04, 0.95))
	g.set_color(1, Color(0.04, 0.04, 0.04, 0.0))
	g.add_point(0.55, Color(0.04, 0.04, 0.04, 0.72))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	_shadow.texture = tex
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var kick := Label.new()
	kick.text = "PAUSED"
	kick.add_theme_font_override("font", Brand.FONT_DISPLAY)
	kick.add_theme_font_size_override("font_size", 14)
	kick.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	_list.add_child(kick)
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_theme_constant_override("separation", 2)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_list)
	_where.add_theme_font_override("font", Brand.FONT_BODY)
	_where.add_theme_font_size_override("font_size", 14)
	_where.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	_ui.add_child(_where)
	_items = [
		{"word": "Resume", "sub": "Back to the town", "do": close},
		{"word": "Settings", "sub": "Picture, sound, access", "do": _open_settings.bind(0)},
		{"word": "Controls", "sub": "Every key, and your own", "do": _open_settings.bind(2)},
		{"word": "Title", "sub": "The ferry and the menu", "do": _to_title},
	]
	if not OS.has_feature("web"):     # a browser tab can't be quit from inside it
		_items.append({"word": "Quit", "sub": "The town carries on without you", "do": func(): get_tree().quit()})
	for i in _items.size():
		var w := MenuWord.new()
		w.setup(_items[i].word, _items[i].sub, 41)
		w.hovered.connect(_choose.bind(i))
		w.pressed.connect(_go.bind(i))
		_list.add_child(w)
		_words.append(w)
	settings.closed.connect(func():
		if _to_settings:
			_to_settings = false
			open())

func _layout() -> void:
	var s := size
	_shadow.position = Vector2.ZERO
	_shadow.size = Vector2(s.x * 0.62, s.y)
	_ui.size = s
	_list.position = Vector2(80, 60)
	_list.size = Vector2(520, s.y - 160)
	_where.position = Vector2(80, s.y - 70)

func open() -> void:
	if is_open: return
	is_open = true
	visible = true
	_layout()
	_where.text = _where_line()
	cinema.bars_in()
	_shadow.modulate.a = 0.0
	_ui.modulate.a = 0.0
	_ui.position.x = -40.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_shadow, "modulate:a", 1.0, OPEN_TIME)
	t.tween_property(_ui, "modulate:a", 1.0, OPEN_TIME)
	t.tween_property(_ui, "position:x", 0.0, OPEN_TIME)
	var cam := get_viewport().get_camera_3d()
	if cam and not Access.reduce_motion: t.tween_property(cam, "h_offset", EASE_ASIDE, OPEN_TIME + 0.3)
	_chosen = 0
	for k in _words.size(): _words[k].set_on(k == 0)

## Back to the town. Leaving for Settings keeps the bars and the camera where they are.
func close(for_settings := false) -> void:
	if not is_open: return
	is_open = false
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_shadow, "modulate:a", 0.0, 0.25)
	t.tween_property(_ui, "modulate:a", 0.0, 0.2)
	if not for_settings:
		cinema.bars_out()
		var cam := get_viewport().get_camera_3d()
		if cam: t.tween_property(cam, "h_offset", 0.0, 0.45)
	await t.finished
	if not is_open: visible = false

func _choose(i: int) -> void:
	_chosen = i
	for k in _words.size(): _words[k].set_on(k == i)

func _go(i: int) -> void:
	_items[i].do.call()

func _open_settings(tab: int) -> void:
	_to_settings = true
	close(true)
	settings.open_at(tab)

func _to_title() -> void:
	TitleScreen.skip_once = false
	get_tree().reload_current_scene()

## Where you are and when, under the menu: the place, the town's day and the time.
func _where_line() -> String:
	var place: String = world.hud.place_name() if world.hud else ""
	var c: Dictionary = world.client.city if world.client else {}
	var day := "Day %d" % int(c.get("day", 0)) if c.has("day") else ""
	return "  ·  ".join([place, day].filter(func(x): return x != ""))

func _input(e: InputEvent) -> void:
	if not e is InputEventKey or not e.pressed or e.is_echo(): return
	if not is_open:
		if e.keycode == KEY_ESCAPE and not settings.is_open and world.settings_may_open():
			open()
			get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_ESCAPE: close()
		KEY_UP, KEY_W: _choose(posmod(_chosen - 1, _items.size()))
		KEY_DOWN, KEY_S: _choose(posmod(_chosen + 1, _items.size()))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E: _go(_chosen)
		_: return
	get_viewport().set_input_as_handled()
