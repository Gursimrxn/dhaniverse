class_name TitleScreen
extends Control
## The title, over the real town at dawn. Out of the logo the ferry comes up the river to the jetty, and only then the name across the sky,
## a menu of plain words, and what the town is doing right now. Everything on it is live, and it holds the camera until the player chooses.

signal finished                    # the game can begin

const NAME_SIZE := 152
const MENU_AT := Vector2(57, 100)  # from the left, and up from the bottom
const PLATE_WIDTH := 276.0
const FILM_FOV := 36.0
const DRIFT_TIME := 60.0           # s for the camera's slow drift back along the end of the film shot, there and back
const DRIFT_BACK := 0.25           # how far back along the shot it drifts
const SKIP_SHOWS_AFTER := 1.5      # s of the ride before it says it can be skipped
const KEEP_PRICES := 40
const BAR := 46.0                  # px, the film bars

static var skip_once := false      # coming back after "a new life": straight to the ferry

var world: Node
var client: TownClient
var cinema: Cinema
var director: Director
var opening: Opening
var settings: SettingsPanel
var bar: GameHud
var active := false                # the menu is taking keys
var is_up := false
var mode_before := ""              # the time of day under the title's dawn

var _arriving := false             # the ferry is still on its way in
var _may_skip := false
var _items: Array[Dictionary] = []
var _words: Array[MenuWord] = []
var _chosen := 0
var _name := Label.new()
var _menu := VBoxContainer.new()
var _plate := PanelContainer.new()
var _food := Label.new()
var _day := Label.new()
var _people := Label.new()
var _line := Control.new()
var _prices: Array[float] = []
var _news := Label.new()
var _news_x := 0.0
var _legend := HBoxContainer.new()
var _t := 0.0
var _was_at := Vector3.ZERO
var _sure_new := false

## Only for a person starting the game: bots, captures and the return from a new life skip it.
static func wanted() -> bool:
	if skip_once: return false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snap") or a.begins_with("--shots") or a in ["--arrive", "--no-title", "--game"]: return false
		if a == "--world=quarter": return false
	return true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	add_child(_shade())
	add_child(_grain())
	_name.text = "Dhaniverse"
	_name.add_theme_font_override("font", Brand.FONT_BODY)
	_name.add_theme_font_size_override("font_size", NAME_SIZE)
	_name.add_theme_constant_override("line_spacing", 0)
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.32))
	_name.add_theme_constant_override("shadow_offset_y", 5)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sweep := ShaderMaterial.new()
	sweep.shader = preload("res://shaders/ui/logo_sweep.gdshader")
	_name.material = sweep
	_name.modulate.a = 0.0
	add_child(_name)
	_menu.add_theme_constant_override("separation", 2)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu.offset_left = MENU_AT.x
	_menu.offset_bottom = -MENU_AT.y
	add_child(_menu)
	_build_plate()
	_build_news()
	_build_legend()
	visible = false

func _shade() -> Control:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.45))
	g.set_color(1, Color(0, 0, 0, 0.72))
	g.add_point(0.42, Color(0, 0, 0, 0.0))
	g.add_point(0.62, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	var shade := TextureRect.new()
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shade

func _grain() -> Control:
	var grain := ColorRect.new()
	var look := ShaderMaterial.new()
	look.shader = preload("res://shaders/ui/film_grain.gdshader")
	grain.material = look
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return grain

func _build_plate() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(18)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	_plate.add_theme_stylebox_override("panel", s)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.custom_minimum_size.x = PLATE_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var title := _small("Tallyport, live", Brand.CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_people = _small("", Brand.CREAM_MUTED)
	top.add_child(_people)
	column.add_child(top)
	_line.custom_minimum_size = Vector2(0, 48)
	_line.draw.connect(_draw_line)
	column.add_child(_line)
	var numbers := HBoxContainer.new()
	numbers.add_child(_number("Food today", _food, HORIZONTAL_ALIGNMENT_LEFT))
	numbers.add_child(_number("Day in town", _day, HORIZONTAL_ALIGNMENT_RIGHT))
	column.add_child(numbers)
	_plate.add_child(column)
	_plate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_plate.offset_right = -57
	_plate.offset_bottom = -100
	_plate.modulate.a = 0.0
	add_child(_plate)

func _small(text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Brand.FONT_BODY)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", colour)
	return l

func _number(what: String, value: Label, align: int) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	var head := _small(what, Brand.CREAM_MUTED)
	head.horizontal_alignment = align
	value.add_theme_font_override("font", Brand.FONT_BODY)
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", Brand.CREAM)
	value.horizontal_alignment = align
	column.add_child(head)
	column.add_child(value)
	return column

func _build_news() -> void:
	_news.add_theme_font_override("font", Brand.FONT_BODY)
	_news.add_theme_font_size_override("font_size", 13)
	_news.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	_news.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_news.z_index = 45
	_news.modulate.a = 0.0
	add_child(_news)

func _build_legend() -> void:
	_legend.position = Vector2(57, 11)
	_legend.z_index = 45
	_legend.add_theme_constant_override("separation", 8)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.modulate.a = 0.0
	add_child(_legend)

func _say_keys(pairs: Array) -> void:
	for old in _legend.get_children(): old.free()
	for pair in pairs:
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_font_override("font", Brand.FONT_DISPLAY)
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Brand.PLATE)
		var cap := StyleBoxFlat.new()
		cap.bg_color = Brand.CREAM
		cap.set_corner_radius_all(5)
		cap.content_margin_left = 7
		cap.content_margin_right = 7
		cap.content_margin_top = 1
		cap.content_margin_bottom = 1
		key.add_theme_stylebox_override("normal", cap)
		_legend.add_child(key)
		var words := _small(pair[1], Brand.CREAM_MUTED)
		words.custom_minimum_size.x = 56
		_legend.add_child(words)

## Sets the shot up under the logo opening. Nothing of the menu shows until enter().
func begin() -> void:
	is_up = true
	visible = true
	mode_before = world.mode
	_was_at = world.player.global_position
	world._lapsing = true
	world.set_time_mode("dawn", true)
	opening._place_on_deck()
	opening.aboard = true
	opening.ride_held = true           # the ride starts when the logo's burst has opened onto it (enter)
	_arriving = true
	_game_keys(false)
	world.player.frozen = true
	for p in opening.plates: p.modulate.a = 0.0
	director.cam.fov = FILM_FOV
	_place_camera()
	director.cam.make_current()
	client.city_changed.connect(_read_town)
	client.synced.connect(_read_town)
	client.presence.connect(func(players: Array): if is_up: _people.text = "%d in town" % players.size())
	client.event.connect(func(e: Dictionary): if is_up and e.type == "FeedPost": _say_news(str(e.text)))
	_build_menu()
	_read_town()

func _build_menu() -> void:
	for old in _menu.get_children(): old.queue_free()
	_words.clear()
	var saved := str(world._setting("player_name", ""))
	_items.clear()
	if saved != "": _items.append({"word": "Continue", "sub": "as %s" % saved, "do": _continue})
	_items.append({"word": "A new life", "sub": "Step off the ferry", "do": _new_life})
	_items.append({"word": "Settings", "sub": "Over the town", "do": _settings})
	if not OS.has_feature("web"):     # a browser tab can't be quit from inside it
		_items.append({"word": "Leave", "sub": "The town carries on without you", "do": func(): get_tree().quit()})
	for i in _items.size():
		var w := MenuWord.new()
		w.setup(_items[i].word, _items[i].sub)
		w.hovered.connect(_choose.bind(i))
		w.pressed.connect(func():
			if active: _go(i))
		w.modulate.a = 0.0
		_menu.add_child(w)
		_words.append(w)

## The town is showing: film the ferry in, and bring the title in when it's there.
func enter() -> void:
	cinema.bars_in()
	cinema.card("Tallyport", "", "", Opening.FILM - 2.2)
	_may_skip = true
	get_tree().create_timer(BootIntro.WIPE_TIME).timeout.connect(func(): opening.ride_held = false)   # called as the burst's wipe starts
	opening.alongside.connect(_menu_in, CONNECT_ONE_SHOT)
	_say_keys([["Any key", "Skip"]])
	var hint := create_tween()
	hint.tween_interval(SKIP_SHOWS_AFTER)
	hint.tween_property(_legend, "modulate:a", 1.0, 0.8)

## Through the mark to the ferry at the jetty.
func _skip_ride() -> void:
	_may_skip = false
	await cinema.wipe_closed()
	opening.come_in_now()
	await cinema.wipe_open()

func _menu_in() -> void:
	_arriving = false
	_may_skip = false
	_t = 0.0
	_legend.modulate.a = 0.0
	_say_keys([["↑↓", "Choose"], ["Enter", "Go"]])
	await get_tree().create_timer(0.5).timeout
	var name_in := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	name_in.tween_property(_name, "modulate:a", 1.0, 1.1)
	_name.reset_size()
	var at := Vector2((size.x - _name.size.x) * 0.5, 54.0)
	_name.position = at + Vector2(0, 16)
	name_in.tween_property(_name, "position", at, 1.2)
	await get_tree().create_timer(0.3).timeout
	for i in _words.size():
		var w := _words[i]
		var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_interval(i * 0.09)
		t.tween_property(w, "modulate:a", 1.0, 0.6)
	active = true
	_chosen = -1
	_choose(0)
	await get_tree().create_timer(0.4).timeout
	for part in [_plate, _legend, _news]: create_tween().tween_property(part, "modulate:a", 1.0, 0.8)

func _choose(i: int) -> void:
	if i == _chosen or not active: return
	_chosen = i
	_sure_new = false
	for k in _words.size(): _words[k].set_on(k == i)

func _go(i: int) -> void:
	_items[i].do.call()

## Back to the town as it was, through the mark.
func _continue() -> void:
	active = false
	await _leave_shot()
	world.set_time_mode(mode_before, true)
	world._lapsing = false
	opening._moor()
	world.player.global_position = _was_at
	world.player.frozen = false
	for p in opening.plates: create_tween().tween_property(p, "modulate:a", 1.0, 0.8)
	director.cut()
	cinema.wipe_open()
	is_up = false
	_game_keys(true)
	finished.emit()

## A first life starts straight away. Over an existing one, ask once, then start the game again with no name.
func _new_life() -> void:
	var saved := str(world._setting("player_name", ""))
	if saved != "":
		if not _sure_new:
			_sure_new = true
			_words[_chosen].set_sub("Press again. %s stays in town." % saved)
			return
		world._save_setting("player_name", "")
		world._save_setting("player_secret", "")
		world._save_setting(Opening.READ, false)
		TitleScreen.skip_once = true
		get_tree().reload_current_scene()
		return
	active = false
	await create_tween().tween_property(self, "modulate:a", 0.0, 0.5).finished
	visible = false
	is_up = false
	_game_keys(true)
	finished.emit()

## The phone, the mentor and the bar stay out of it while the title's up.
func _game_keys(on: bool) -> void:
	for part in [world.phone, world.mentor, bar]:
		part.set_process_input(on)
		part.set_process_unhandled_input(on)

func _settings() -> void:
	active = false
	var hide_for := create_tween().set_parallel()
	for part in [_menu, _name, _plate]: hide_for.tween_property(part, "modulate:a", 0.0, 0.25)
	settings.closed.connect(func():
		var back := create_tween().set_parallel()
		for part in [_menu, _name, _plate]: back.tween_property(part, "modulate:a", 1.0, 0.4)
		active = true, CONNECT_ONE_SHOT)
	settings.open()

func _leave_shot() -> void:
	var fade := create_tween().set_parallel()
	for part in [_menu, _name, _plate, _legend, _news]: fade.tween_property(part, "modulate:a", 0.0, 0.35)
	cinema.bars_out()
	await cinema.wipe_closed()
	visible = false

func _read_town() -> void:
	if not is_up or client.city.is_empty(): return
	var price := int(client.city.get("price", 0))
	_food.text = Usdc.text(price)
	_day.text = str(int(client.city.get("day", 0)))
	if price > 0:
		_prices.append(float(price))
		if _prices.size() > KEEP_PRICES: _prices.pop_front()
		_line.queue_redraw()
	var paper = client.city.get("paper")
	if _news.text == "" and paper != null: _say_news(str(paper.headline))

func _say_news(text: String) -> void:
	_news.text = text if _news.text == "" else _news.text + "          " + text
	_news.reset_size()

func _draw_line() -> void:
	var r := _line.size
	if _prices.size() < 2:
		_line.draw_line(Vector2(0, r.y * 0.5), Vector2(r.x, r.y * 0.5), Color(Brand.ORANGE, 0.5), 2.0, true)
		return
	var low: float = _prices.min()
	var high: float = maxf(_prices.max(), low + 1.0)
	var points := PackedVector2Array()
	for i in _prices.size():
		points.append(Vector2(r.x * i / float(_prices.size() - 1), r.y - 4.0 - (r.y - 8.0) * (_prices[i] - low) / (high - low)))
	_line.draw_polyline(points, Brand.ORANGE, 2.5, true)

func _place_camera() -> void:
	var u: float = opening._ride_u if _arriving else 1.0 - DRIFT_BACK * (0.5 - 0.5 * cos(_t / DRIFT_TIME * TAU))
	var shot: Array = opening._film_shot(u)
	director.cam.look_at_from_position(shot[0], shot[1])

func _process(delta: float) -> void:
	if not is_up: return
	_t += delta
	if director.cam.current: _place_camera()
	if _news.text != "":
		_news_x -= delta * 46.0
		if _news_x < -_news.size.x: _news_x = size.x
		_news.position = Vector2(_news_x, size.y - BAR * 0.5 - 10.0)

func _input(e: InputEvent) -> void:
	if _may_skip and e.is_pressed() and not e.is_echo() and (e is InputEventKey or e is InputEventMouseButton):
		_skip_ride()
		get_viewport().set_input_as_handled()
		return
	if not active or not e is InputEventKey or not e.pressed or e.is_echo(): return
	match e.keycode:
		KEY_UP, KEY_W: _choose(posmod(_chosen - 1, _items.size()))
		KEY_DOWN, KEY_S: _choose(posmod(_chosen + 1, _items.size()))
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E: _go(_chosen)
		_: pass
	get_viewport().set_input_as_handled()
