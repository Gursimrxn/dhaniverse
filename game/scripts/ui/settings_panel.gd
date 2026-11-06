class_name SettingsPanel
extends Control
## Settings, over the game: Esc holds the shot, the film bars close in, the camera eases aside, and a shadow falls across the right of the
## frame with the choices on it. Nothing pauses, and every change happens to the real game as you make it. Kept in the game's settings.

signal closed

const COLUMN_NAV := 200.0
const COLUMN_PAGE := 400.0
const RIGHT := 50.0
const EASE_ASIDE := 0.7            # the camera's horizontal offset, in metres
const OPEN_TIME := 0.6             # s
const SECTIONS := ["Picture", "Sound", "Controls", "Game"]
const FOV_BASE := 75
const REBIND := [["Walk forward", "move_forward"], ["Walk back", "move_back"], ["Walk left", "move_left"], ["Walk right", "move_right"], ["Run", "sprint"], ["Use", "interact"], ["Change camera", "camera_mode"]]
const FIXED_KEYS := {"Phone": "Tab", "Your mentor": "H", "The paper": "N", "Scooter": "F", "Settings": "Esc"}
const KEYBOARD := [["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], ["Caps", "A", "S", "D", "F", "G", "H", "J", "K", "L"], ["Shift", "Z", "X", "C", "V", "B", "N", "M"], ["Space"]]

var world: Node
var cinema: Cinema
var is_open := false

var _shadow := TextureRect.new()
var _ui := Control.new()
var _nav := VBoxContainer.new()
var _words: Array[MenuWord] = []
var _page := VBoxContainer.new()
var _tab := 0
var _compare := Button.new()
var _sample := Label.new()
var _key_cells := {}               # a key's name -> its Label
var _waiting_for := ""             # the action whose new key is awaited
var _lit: Array = []
var _action_buttons := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 35
	visible = false
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.04, 0.04, 0.0))
	g.set_color(1, Color(0.04, 0.04, 0.04, 0.95))
	g.add_point(0.32, Color(0.04, 0.04, 0.04, 0.78))
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
	_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	_nav.add_theme_constant_override("separation", 2)
	_nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_nav)
	_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_page.add_theme_constant_override("separation", 6)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_page)
	var kick := _small("SETTINGS", Brand.CREAM_MUTED, Brand.FONT_DISPLAY, 14)
	_nav.add_child(kick)
	for i in SECTIONS.size():
		var w := MenuWord.new()
		w.setup(SECTIONS[i], "", 41)
		w.pressed.connect(_show.bind(i))
		w.hovered.connect(func(): pass)
		_nav.add_child(w)
		_words.append(w)
	var back := Button.new()
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.text = "Esc   Back"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.add_theme_font_override("font", Brand.FONT_BODY)
	back.add_theme_font_size_override("font_size", 14)
	back.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	back.pressed.connect(close)
	_nav.add_child(back)
	_compare.text = "Hold   Compare with before"
	_compare.focus_mode = Control.FOCUS_NONE
	_compare.add_theme_font_override("font", Brand.FONT_BODY)
	_compare.add_theme_font_size_override("font_size", 13)
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_corner_radius_all(99)
	look.content_margin_left = 16
	look.content_margin_right = 16
	look.content_margin_top = 8
	look.content_margin_bottom = 8
	for state in ["normal", "hover", "pressed"]: _compare.add_theme_stylebox_override(state, look)
	_compare.button_down.connect(func(): _apply_picture(true))
	_compare.button_up.connect(func(): _apply_picture(false))
	add_child(_compare)
	_sample.text = "Morning. I've something for you."
	_sample.add_theme_font_override("font", Brand.FONT_BODY)
	_sample.add_theme_color_override("font_color", Brand.CREAM)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Brand.PLATE
	plate.border_color = Brand.CREAM
	plate.set_border_width_all(3)
	plate.set_corner_radius_all(99)
	plate.content_margin_left = 20
	plate.content_margin_right = 20
	plate.content_margin_top = 6
	plate.content_margin_bottom = 6
	_sample.add_theme_stylebox_override("normal", plate)
	_sample.visible = false
	add_child(_sample)
	apply_saved()

## What was chosen last time, on the real game. Called once at start, open or not.
func apply_saved() -> void:
	_apply_picture(false)
	_apply_sound()
	for pair in REBIND:
		var code := int(world._setting("key_" + pair[1], 0))
		if code != 0: _bind(pair[1], code)
	KeyHint.enabled = bool(world._setting("hints", true))
	MentorChat.speaks_up = bool(world._setting("mentor_speaks", true))
	HudMotion.on = bool(world._setting("hud_motion", true))
	Cinema.say_scale = float(world._setting("subtitle_size", 100)) / 100.0
	world.rays_on = bool(world._setting("rays", true))
	world.cinematic_on = bool(world._setting("cinematic", true))

func _layout() -> void:
	var s := size
	_shadow.position = Vector2(s.x * 0.26, 0)
	_shadow.size = Vector2(s.x * 0.74, s.y)
	var left := s.x - RIGHT - COLUMN_PAGE - COLUMN_NAV - 40.0
	_ui.position = Vector2.ZERO
	_ui.size = s
	_nav.position = Vector2(left, 46)
	_nav.size = Vector2(COLUMN_NAV, s.y - 92)
	_page.position = Vector2(left + COLUMN_NAV + 40.0, 46)
	_page.size = Vector2(COLUMN_PAGE, s.y - 92)
	_compare.position = Vector2(50, s.y - 110)
	_sample.position = Vector2(50, s.y - 120)

func open() -> void:
	if is_open: return
	is_open = true
	visible = true
	_layout()
	cinema.bars_in()
	_shadow.modulate.a = 0.0
	_ui.modulate.a = 0.0
	_ui.position.x = 60.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_shadow, "modulate:a", 1.0, OPEN_TIME)
	t.tween_property(_ui, "modulate:a", 1.0, OPEN_TIME)
	t.tween_property(_ui, "position:x", 0.0, OPEN_TIME)
	var cam := get_viewport().get_camera_3d()
	if cam: t.tween_property(cam, "h_offset", EASE_ASIDE, OPEN_TIME + 0.3)
	_show(_tab)

func close() -> void:
	if not is_open: return
	is_open = false
	_waiting_for = ""
	_apply_picture(false)
	cinema.bars_out()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_shadow, "modulate:a", 0.0, 0.3)
	t.tween_property(_ui, "modulate:a", 0.0, 0.25)
	t.tween_property(_compare, "modulate:a", 0.0, 0.2)
	var cam := get_viewport().get_camera_3d()
	if cam: t.tween_property(cam, "h_offset", 0.0, 0.5)
	await t.finished
	if not is_open:
		visible = false
		_compare.modulate.a = 1.0
	closed.emit()

func _show(i: int) -> void:
	_tab = i
	for k in _words.size(): _words[k].set_on(k == i)
	for old in _page.get_children():
		_page.remove_child(old)
		old.queue_free()
	_compare.visible = i == 0
	_sample.visible = i == 3
	_key_cells.clear()
	_action_buttons.clear()
	match i:
		0: _picture()
		1: _sound()
		2: _controls()
		3: _game()
	for n in _page.get_child_count():
		var part: Control = _page.get_child(n)
		part.modulate.a = 0.0
		var t := create_tween()
		t.tween_interval(n * 0.035)
		t.tween_property(part, "modulate:a", 1.0, 0.3)

# --- the pieces of a page --------------------------------------------------------------------------------------------
func _small(text: String, colour: Color, font: Font = Brand.FONT_BODY, font_size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _lead(text: String) -> void:
	var l := _small(text, Color("C9C1A6"), Brand.FONT_BODY, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = COLUMN_PAGE
	_page.add_child(l)

## A bare line you can drag anywhere along, with a big serif number. Whole numbers.
func _slider(label: String, key: String, from: int, to: int, fallback: int, unit: String, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	var name_l := _small(label, Brand.CREAM, Brand.FONT_BODY, 15)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var value := int(world._setting(key, fallback))
	var number := _small("%d%s" % [value, unit], Brand.CREAM, Brand.FONT_EDITORIAL, 34)
	top.add_child(number)
	row.add_child(top)
	var s := HSlider.new()
	s.min_value = from
	s.max_value = to
	s.step = 1
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.add_theme_stylebox_override("slider", _track(Color(Brand.CREAM, 0.2)))
	s.add_theme_stylebox_override("grabber_area", _track(Brand.ORANGE))
	s.add_theme_stylebox_override("grabber_area_highlight", _track(Brand.ORANGE))
	var grab := _grabber()
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", grab)
	s.value_changed.connect(func(v: float):
		number.text = "%d%s" % [int(v), unit]
		world._save_setting(key, int(v))
		on_change.call(int(v)))
	row.add_child(s)
	_page.add_child(row)

func _track(colour: Color) -> StyleBoxFlat:
	var t := StyleBoxFlat.new()
	t.bg_color = colour
	t.set_corner_radius_all(2)
	t.content_margin_top = 2
	t.content_margin_bottom = 2
	return t

func _grabber() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Brand.CREAM)
	g.set_color(1, Color(Brand.CREAM, 0.0))
	g.add_point(0.9, Brand.CREAM)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 16
	tex.height = 16
	return tex

## A whole line you click, its state a word.
func _toggle(label: String, hint: String, key: String, fallback: bool, on_change: Callable) -> void:
	var line := Button.new()
	line.flat = true
	line.focus_mode = Control.FOCUS_NONE
	line.custom_minimum_size = Vector2(COLUMN_PAGE, 46)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_small(label, Brand.CREAM, Brand.FONT_BODY, 15))
	if hint != "": words.add_child(_small(hint, Color("C9C1A6"), Brand.FONT_BODY, 12))
	row.add_child(words)
	var on := bool(world._setting(key, fallback))
	var state := _small("", Brand.CREAM, Brand.FONT_EDITORIAL_ITALIC, 30)
	var paint := func(v: bool):
		state.text = "On" if v else "Off"
		state.add_theme_color_override("font_color", Brand.ORANGE if v else Color(Brand.CREAM, 0.42))
	paint.call(on)
	row.add_child(state)
	line.add_child(row)
	line.pressed.connect(func():
		var v := not bool(world._setting(key, fallback))
		world._save_setting(key, v)
		paint.call(v)
		state.pivot_offset = state.size * 0.5
		state.scale = Vector2.ONE * 0.8
		create_tween().tween_property(state, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		on_change.call(v))
	_page.add_child(line)

# --- pages --------------------------------------------------------------------------------------------------------------
func _picture() -> void:
	_lead("The game's still running. Everything you touch happens to it right now.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	var now := str(world.quality)
	for pair in [["Full", "high"], ["Low", "low"]]:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = pair[0]
		b.add_theme_font_override("font", Brand.FONT_EDITORIAL_ITALIC if pair[1] == now else Brand.FONT_EDITORIAL)
		b.add_theme_font_size_override("font_size", 34)
		b.add_theme_color_override("font_color", Brand.CREAM if pair[1] == now else Color(Brand.CREAM, 0.42))
		b.add_theme_color_override("font_hover_color", Brand.CREAM)
		if pair[1] != now:
			b.pressed.connect(func():
				world._save_setting("chosen_quality", pair[1])
				TitleScreen.skip_once = true
				get_tree().reload_current_scene())
		row.add_child(b)
	_page.add_child(row)
	_slider("Brightness", "brightness", 70, 130, 100, "", func(_v): _apply_picture(false))
	_slider("Colour", "colour", 50, 150, 100, "", func(_v): _apply_picture(false))
	_slider("Field of view", "fov_bonus", -15, 25, 0, "°", func(_v): _apply_picture(false))
	_toggle("Light rays", "", "rays", true, func(v: bool): world.rays_on = v)
	_toggle("Cinematic camera", "The big shots, and the drift when you stand still", "cinematic", true, func(v: bool): world.cinematic_on = v)
	_toggle("Steady frames", "When the screen's rate is out of reach, an even half of it", "steady_frames", true, func(v: bool): world.steady_frames = v)

func _sound() -> void:
	_lead("Listen to the town while you set it.")
	for row in [["Music", "volume_music"], ["The town", "volume_town"], ["Chimes and bells", "volume_effects"]]:
		_slider(row[0], row[1], 0, 100, 80, "", func(_v): _apply_sound())

func _controls() -> void:
	_lead("Point at an action to find its key. Click it, then press the new one.")
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 4)
	for keys in KEYBOARD:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		for k in keys:
			var cell := _key_cell(k)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_stretch_ratio = 6.0 if k == "Space" else (1.7 if k.length() > 1 else 1.0)
			row.add_child(cell)
			_key_cells[k] = cell
		board.add_child(row)
	_page.add_child(board)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 0)
	for pair in REBIND:
		var b := _action_button(pair[0], _key_of(pair[1]))
		b.pressed.connect(_start_rebind.bind(pair[1], b))
		b.mouse_entered.connect(_light.bind([_key_of(pair[1])]))
		_action_buttons[pair[1]] = b
		grid.add_child(b)
	for what in FIXED_KEYS:
		var b := _action_button(what, FIXED_KEYS[what])
		b.disabled = true
		b.mouse_entered.connect(_light.bind([FIXED_KEYS[what]]))
		grid.add_child(b)
	_page.add_child(grid)
	_paint_board()

func _key_cell(k: String) -> Label:
	var l := _small(k, Color(Brand.CREAM, 0.34), Brand.FONT_DISPLAY, 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 32)
	var look := StyleBoxFlat.new()
	look.bg_color = Color(Brand.CREAM, 0.07)
	look.set_corner_radius_all(6)
	l.add_theme_stylebox_override("normal", look)
	return l

func _action_button(what: String, key: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = "%s   %s" % [what, key]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(190, 28)
	b.add_theme_font_override("font", Brand.FONT_BODY)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	b.add_theme_color_override("font_hover_color", Brand.CREAM)
	b.add_theme_color_override("font_disabled_color", Color(Brand.CREAM_MUTED, 0.6))
	return b

func _key_of(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			return OS.get_keycode_string(code)
	return "?"

func _light(keys: Array) -> void:
	_lit = keys
	_paint_board()

func _paint_board() -> void:
	var used := FIXED_KEYS.values()
	for pair in REBIND: used.append(_key_of(pair[1]))
	for k in _key_cells:
		var cell: Label = _key_cells[k]
		var look: StyleBoxFlat = cell.get_theme_stylebox("normal")
		var on: bool = k in _lit
		look.bg_color = Brand.ORANGE if on else (Color(Brand.CREAM, 0.24) if k in used else Color(Brand.CREAM, 0.07))
		cell.add_theme_color_override("font_color", Color.BLACK if on else (Brand.CREAM if k in used else Color(Brand.CREAM, 0.34)))

func _start_rebind(action: String, button: Button) -> void:
	_waiting_for = action
	button.text = "Press a key…"

func _bind(action: String, code: int) -> void:
	InputMap.action_erase_events(action)
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	InputMap.action_add_event(action, e)

func _game() -> void:
	_lead("How much the town helps you along.")
	_toggle("Key hints", "They fade once you've learned them", "hints", true, func(v: bool): KeyHint.enabled = v)
	_toggle("Your mentor speaks up", "Off means only when you ask", "mentor_speaks", true, func(v: bool): MentorChat.speaks_up = v)
	_toggle("Moving HUD", "Off shows each change at once, without the rolls and slides", "hud_motion", true, func(v: bool): HudMotion.on = v)
	_slider("Subtitle size", "subtitle_size", 80, 160, 100, "", func(v: int):
		Cinema.say_scale = v / 100.0
		_show_sample())
	_show_sample()

func _show_sample() -> void:
	_sample.add_theme_font_size_override("font_size", int(20.0 * float(world._setting("subtitle_size", 100)) / 100.0))
	_sample.reset_size()

# --- on the real game ---------------------------------------------------------------------------------------------------
func _apply_picture(as_before: bool) -> void:
	var bright := 100 if as_before else int(world._setting("brightness", 100))
	var colour := 100 if as_before else int(world._setting("colour", 100))
	world.set_picture(bright / 100.0, colour / 100.0)
	if world.rig: world.rig.fov_bonus = float(world._setting("fov_bonus", 0))

func _apply_sound() -> void:
	if world.sound == null: return
	world.sound.set_volumes(int(world._setting("volume_music", 80)) / 100.0, int(world._setting("volume_town", 80)) / 100.0, int(world._setting("volume_effects", 80)) / 100.0)

func _input(e: InputEvent) -> void:
	if not e is InputEventKey or not e.pressed or e.is_echo(): return
	if _waiting_for != "":
		var action := _waiting_for
		_waiting_for = ""
		if e.keycode != KEY_ESCAPE:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			_bind(action, code)
			world._save_setting("key_" + action, code)
		_show(2)
		_light([_key_of(action)])
		get_viewport().set_input_as_handled()
		return
	if e.keycode != KEY_ESCAPE: return
	if is_open:
		close()
		get_viewport().set_input_as_handled()
	elif world.settings_may_open():
		open()
		get_viewport().set_input_as_handled()
