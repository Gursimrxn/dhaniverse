class_name TownMap
extends Control
## The town map (ux08, M): the whole town in the minimap's own colours and image, the places named on it, a pin for every quest (its
## board badge; the one you run as the gold diamond; an urgent crate in orange) and you as the cream arrow. Down the left, on a plate,
## the list: the quests you're on first, the one you run ringed in gold, then what the board offers, each with how far it is.
## W and S choose, E runs the chosen quest (one you're on), F shows it on the map, M or Esc closes. Nothing pauses.

const PANEL := Rect2(28, 28, 320, 664)
const PANEL_GAP := 24.0
const GOLD := Color("F0C33A")
const NOTE := Color("C9C1A6")
const BG := Color("161717")
const SHOWN := 9                   # rows that fit the plate; the list scrolls with the choice

var world: Node
var client: TownClient
var is_open := false
var _rows: Array = []              # {kind, word, colour, ink, title, sub, at: Vector2 (world x, z), quest, on, tracked}
var _pick := 0
var _flash := 0.0                  # F: the chosen pin pulses
var _map: Control                  # the minimap, whose painted town this draws
var _list := VBoxContainer.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	visible = false
	_list.position = PANEL.position + Vector2(22, 104)
	_list.custom_minimum_size.x = PANEL.size.x - 44.0
	_list.add_theme_constant_override("separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)

func open() -> void:
	if is_open or not Screens.free_to_open(): return
	is_open = true
	visible = true
	_map = world.hud._map
	_read()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25 if HudMotion.on else 0.01)

func close() -> void:
	if not is_open: return
	is_open = false
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2 if HudMotion.on else 0.01)
	t.tween_callback(func(): if not is_open: visible = false)

## The rows: what you're on (the one you run first), then the board's offers that have a place.
func _read() -> void:
	_rows.clear()
	var town: Dhaniverse = world.dhaniverse
	var guide: Guide = town.guide
	var crate: Dictionary = world.loot.current() if world.loot else {}
	if not crate.is_empty():
		var at3: Vector3 = world.loot.where()
		_rows.append({"word": "now", "colour": Brand.ORANGE, "ink": Brand.PLATE, "title": "loot crate", "sub": "%s · %s" % [Usdc.text(int(crate.prize)), world.loot.place_words()],
			"at": Vector2(at3.x, at3.z), "quest": "", "on": false, "tracked": false})
	var quests: Array = client.you.get("quests", [])
	quests.sort_custom(func(a, b): return str(a.quest) == guide.tracked and str(b.quest) != guide.tracked)
	for q in quests:
		var step := TownState.next_step(q)
		var place := str(step.get("place", ""))
		var o := {"by": "sponsored" if q.get("campaign") != null else "errand", "title": str(q.title), "card": {"template": "spice_run" if str(q.get("cargo_usdc", 0)) != "0" else ""}}
		var badge: Array = BountyBoard.badge(o)
		var look: Array = BountyBoard.BADGES.get(badge[0], BountyBoard.BADGES.errand)
		var at := Vector2.INF
		if town.knows(place):
			var p3: Vector3 = town.place_at(place)
			at = Vector2(p3.x, p3.z)
		_rows.append({"word": badge[1], "colour": look[0], "ink": look[1], "title": str(q.title).to_lower(), "sub": TownState.step_says(q, step) if not step.is_empty() else "at the chain",
			"at": at, "quest": str(q.quest), "on": true, "tracked": str(q.quest) == guide.tracked})
	for o in TownState.offers(client.you, client.city):
		var place := str(o.get("place", ""))
		if bool(o.on) or not town.knows(place): continue
		var badge: Array = BountyBoard.badge(o)
		var look: Array = BountyBoard.BADGES.get(badge[0], BountyBoard.BADGES.errand)
		var p3: Vector3 = town.place_at(place)
		_rows.append({"word": badge[1], "colour": look[0], "ink": look[1], "title": str(o.title).to_lower(), "sub": "take it at the Bounty Board" + (" · done today" if guide.done_today(str(o.quest)) else ""),
			"at": Vector2(p3.x, p3.z), "quest": str(o.quest), "on": false, "tracked": false})
	_pick = clampi(_pick, 0, maxi(_rows.size() - 1, 0))
	_write_list()

func _write_list() -> void:
	for old in _list.get_children():
		_list.remove_child(old)
		old.queue_free()
	var me: Vector3 = world.player.global_position
	var first := clampi(_pick - SHOWN / 2, 0, maxi(_rows.size() - SHOWN, 0))
	for i in range(first, mini(first + SHOWN, _rows.size())):
		var r: Dictionary = _rows[i]
		var row := PanelContainer.new()
		var look := StyleBoxFlat.new()
		look.bg_color = Color("1a1b1b") if r.tracked or i == _pick else Color(0, 0, 0, 0)
		look.border_color = GOLD if r.tracked else (Brand.CREAM if i == _pick else Color(0, 0, 0, 0))
		look.set_border_width_all(2)
		look.set_corner_radius_all(12)
		look.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", look)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 9)
		var chip := Label.new()
		chip.text = str(r.word)
		chip.add_theme_font_override("font", Brand.FONT_DISPLAY)
		chip.add_theme_font_size_override("font_size", 10)
		chip.add_theme_color_override("font_color", r.ink)
		var chip_look := StyleBoxFlat.new()
		chip_look.bg_color = r.colour
		chip_look.set_corner_radius_all(8)
		chip_look.content_margin_left = 6
		chip_look.content_margin_right = 6
		chip.add_theme_stylebox_override("normal", chip_look)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(chip)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		for part in [[str(r.title), 14, Brand.CREAM], [str(r.sub) + (" · tracked" if r.tracked else ""), 11, NOTE]]:
			var l := Label.new()
			l.text = part[0]
			l.add_theme_font_override("font", Brand.FONT_BODY)
			l.add_theme_font_size_override("font_size", part[1])
			l.add_theme_color_override("font_color", part[2])
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 170.0
			words.add_child(l)
		line.add_child(words)
		var far := Label.new()
		far.text = "%d m" % roundi(Vector2(r.at.x - me.x, r.at.y - me.z).length()) if r.at != Vector2.INF else ""
		far.add_theme_font_override("font", Brand.FONT_DISPLAY)
		far.add_theme_font_size_override("font_size", 12)
		far.add_theme_color_override("font_color", GOLD if r.tracked else NOTE)
		line.add_child(far)
		row.add_child(line)
		_list.add_child(row)

func _process(delta: float) -> void:
	if not is_open: return
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()

## world x, z -> the screen, in the map's area right of the panel, the whole painted town fitted in.
func _area() -> Rect2:
	var room := Rect2(PANEL.end.x + PANEL_GAP, 20.0, size.x - PANEL.end.x - PANEL_GAP - 20.0, size.y - 40.0)
	var ms: Vector2 = _map._msize
	var k := minf(room.size.x / ms.x, room.size.y / ms.y)
	var s := ms * k
	return Rect2(room.position + (room.size - s) * 0.5, s)

func _to_screen(w: Vector2) -> Vector2:
	var a := _area()
	return a.position + (w - _map._origin) / _map._msize * a.size

func _draw() -> void:
	if not is_open or _map == null: return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var a := _area()
	draw_texture_rect(_map._tex, a, false)
	var body: Font = Brand.FONT_BODY
	var label := func(w: Vector2, words: String, ink: Color):
		var p := _to_screen(w)
		var tw := body.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(body, p + Vector2(-tw * 0.5 + 1, 1), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.6))
		draw_string(body, p + Vector2(-tw * 0.5, 0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
	var rooms: Array = world.all_rooms()
	for i in mini(GameHud.ROOM_NAMES.size(), rooms.size()):
		var mid: Vector3 = (rooms[i][0] + rooms[i][1]) * 0.5
		label.call(Vector2(mid.x, mid.z), GameHud.ROOM_NAMES[i], Brand.CREAM)
	label.call(Vector2(Dhaniverse.PLACES.square.x, Dhaniverse.PLACES.square.z), "Tally Square", Brand.CREAM)
	label.call(Vector2(Opening.JETTY_AT.x, Opening.JETTY_AT.z), "the landing", NOTE)
	# the pins: each quest's badge, the one you run as the gold diamond
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if r.at == Vector2.INF: continue
		var p := _to_screen(r.at)
		if r.tracked:
			var k := 9.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -k), p + Vector2(k, 0), p + Vector2(0, k), p + Vector2(-k, 0)]), GOLD)
		else:
			draw_circle(p, 7.0, Brand.CREAM)
			draw_circle(p, 5.0, r.colour)
		if i == _pick and _flash > 0.0:
			draw_arc(p, lerpf(30.0, 10.0, _flash), 0.0, TAU, 32, Color(Brand.CREAM, _flash), 2.0, true)
	# you
	var me: Vector3 = world.player.global_position
	var fy: float = world.player._vis.rotation.y
	var dir := Vector2(sin(fy), cos(fy))
	var side := Vector2(-dir.y, dir.x)
	var mp := _to_screen(Vector2(me.x, me.z))
	draw_colored_polygon(PackedVector2Array([mp + dir * 9.0, mp - dir * 7.0 + side * 7.0, mp - dir * 3.0, mp - dir * 7.0 - side * 7.0]), Brand.CREAM)
	# the panel
	var plate := StyleBoxFlat.new()
	plate.bg_color = Brand.PLATE
	plate.border_color = Brand.CREAM
	plate.set_border_width_all(3)
	plate.set_corner_radius_all(27)
	plate.shadow_color = Color(0, 0, 0, 0.45)
	plate.shadow_size = 24
	draw_style_box(plate, PANEL)
	var ed: Font = Brand.FONT_EDITORIAL
	draw_string(ed, PANEL.position + Vector2(22, 54), "dhaniverse", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Brand.CREAM)
	var city := client.city
	draw_string(body, PANEL.position + Vector2(22, 84), "day %d · %d quest%s here" % [int(city.get("day", 1)), _rows.size(), "" if _rows.size() == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, NOTE)
	var keys := [["E", "Run it"], ["F", "Show on map"], ["M", "Close"]]
	var x := PANEL.position.x + 22.0
	for k in keys:
		var cap := StyleBoxFlat.new()
		cap.bg_color = Brand.CREAM
		cap.set_corner_radius_all(6)
		var w := 22.0
		draw_style_box(cap, Rect2(x, PANEL.end.y - 40.0, w, 22.0))
		draw_string(Brand.FONT_DISPLAY, Vector2(x + 7.0, PANEL.end.y - 24.0), k[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Brand.PLATE)
		draw_string(body, Vector2(x + w + 6.0, PANEL.end.y - 24.0), k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Brand.CREAM)
		x += w + 12.0 + body.get_string_size(k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0

func _input(e: InputEvent) -> void:
	if not e is InputEventKey or not e.pressed or e.echo or PaperSheet.is_typing(self): return
	if not is_open:
		if e.keycode == KEY_M:
			open()
			if is_open: get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_M, KEY_ESCAPE: close()
		KEY_W, KEY_UP: _choose(_pick - 1)
		KEY_S, KEY_DOWN: _choose(_pick + 1)
		KEY_F: _flash = 1.0
		KEY_E:
			if _pick < _rows.size() and bool(_rows[_pick].on):
				world.dhaniverse.guide.track(str(_rows[_pick].quest))
				_read()
		_: return
	get_viewport().set_input_as_handled()

func _choose(i: int) -> void:
	if _rows.is_empty(): return
	_pick = posmod(i, _rows.size())
	_write_list()
