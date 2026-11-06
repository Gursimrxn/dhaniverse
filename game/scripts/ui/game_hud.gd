class_name GameHud
extends Control
## The rest of the HUD on the design board, around the plates: the edge shading, the map, the town's ticker, the bar of things you
## carry, the keys, and a toast when the town changes. Shows what the server says.

const TICKER_KEEP := 3
const SLOT := 60.0
const LIFT := 7.0                # px the slot in use rises
const SLOT_OFF := Color("3a3b3b")
const LIFT_TIME := 0.52          # s the chosen slot takes to rise
const RING_TIME := 0.64          # s its ring takes to draw round it
const SETTLE := 0.3              # s a slot put away takes to settle
const SQUASH := 0.94             # a press
const RING_WAY := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]   # the ring's sides, clockwise from the top
const PLACE_ROLL := 16.0         # px the place name rolls
const PLACE_NEAR := 6.0          # m from a building's footprint: you're at it
const TOAST_AT := 78.0           # px from the top
const TOAST_FOR := 6.0           # s
const CAP_EDGE := Color("9d9477")
const SLOTS := [["wallet", "Your wallet", "wallet"], ["calendar", "Your quests", "quests"], ["pencil", "The town's feed", "feed"], ["calculator", "The town: goal, draw, boards", "town"], ["bulb", "Your mentor", "mentor"]]
const SHOCKS := {"festival": ["A festival fills the town", "Food costs more while it lasts"], "harvest": ["Harvest on the landing", "Food gets cheaper for a while"], "drought": ["Dry weather up the river", "Food costs more for a while"]}
const KEYS := [[["sprint"], "Run"], [["rotate_left", "rotate_right"], "Rotate"], [["camera_mode"], "View"]]   # what camera_rig and player really read


var client: TownClient
var phone: Phone
var mentor: MentorChat
var world: Node

var _ticker := VBoxContainer.new()
var _lines: Array[Array] = []
var _slots: Array[Button] = []
var _slot_name := Label.new()
var _on := -1
var _looks: Array[StyleBoxFlat] = []
var _lift := PackedFloat32Array()    # each slot: how far it has risen
var _ring := PackedFloat32Array()    # each slot: how much of its ring is drawn
var _raising: Array[Tween] = []
var _place_old := Label.new()        # the name rolling away
var _place_box := Control.new()
var _place_roll: Tween
var _toast := PanelContainer.new()
var _toast_title := Label.new()
var _toast_sub := Label.new()
var _toast_bar := Control.new()
var _toast_left := 0.0
var _last_shock := ""
var _place := Label.new()
var _map: Control
var _keys := VBoxContainer.new()
var _keys_said := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_edge_shade())
	_build_ticker()
	_build_bar()
	_build_keys()
	_build_toast()
	_build_map()
	client.you_changed.connect(_refresh)
	client.city_changed.connect(_refresh)
	client.synced.connect(_refresh)
	client.event.connect(_on_event)

## The board's darkened edges, which is what lets words sit on the scene.
func _edge_shade() -> Control:
	var g := Gradient.new()
	g.set_color(0, Color(0.149, 0.153, 0.153, 0.0))
	g.set_color(1, Color(0.149, 0.153, 0.153, 0.42))
	g.add_point(0.62, Color(0.149, 0.153, 0.153, 0.0))
	return _shade(g, Vector2(0.5, 0.5), Vector2(1.0, 1.0), Control.PRESET_FULL_RECT)

func _shade(g: Gradient, from: Vector2, to: Vector2, preset: int) -> TextureRect:
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 256
	tex.height = 144
	var shade := TextureRect.new()
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(preset)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = -1
	return shade

static func on_scene(label: Label, font: Font, font_size: int, colour := Brand.CREAM) -> Label:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The boards' keycap: cream, Bitroad, a darker lip under it.
static func key_cap(text: String, font_size := 12) -> Label:
	var cap := Label.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.CREAM
	look.border_color = CAP_EDGE
	look.border_width_bottom = 3
	look.set_corner_radius_all(7)
	look.content_margin_left = 7
	look.content_margin_right = 7
	cap.add_theme_stylebox_override("normal", look)
	cap.add_theme_font_override("font", Brand.FONT_DISPLAY)
	cap.add_theme_font_size_override("font_size", font_size)
	cap.add_theme_color_override("font_color", Brand.PLATE)
	cap.custom_minimum_size = Vector2(25, 25)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.text = text
	return cap

func _build_ticker() -> void:
	_ticker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_ticker.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ticker.position = Vector2(21, size.y - 21)
	_ticker.offset_left = 21
	_ticker.offset_bottom = -21
	_ticker.custom_minimum_size.x = 302
	_ticker.add_theme_constant_override("separation", 7)
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ticker)

func _say_on_ticker(text: String, gain := "") -> void:
	_lines.append([gain, text])
	if _lines.size() > TICKER_KEEP: _lines.pop_front()
	for old in _ticker.get_children():
		_ticker.remove_child(old)
		old.queue_free()
	for line in _lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		if line[0] != "":
			var g := on_scene(Label.new(), Brand.FONT_NUMBER, 13, Brand.MINT)
			g.text = line[0]
			row.add_child(g)
		var t := on_scene(Label.new(), Brand.FONT_BODY, 13)
		t.text = line[1]
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 260
		row.add_child(t)
		_ticker.add_child(row)

func _build_bar() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_bottom = -21
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 11)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	on_scene(_slot_name, Brand.FONT_BODY, 12)
	_slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_slot_name)
	var plate := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(21)
	s.set_content_margin_all(7)
	plate.add_theme_stylebox_override("panel", Brand.as_plate(s))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	for i in SLOTS.size():
		var b := _slot(i)
		_slots.append(b)
		row.add_child(b)
	plate.add_child(row)
	column.add_child(plate)
	add_child(column)
	for i in _slots.size(): _set_lift(0.0, i)
	_mark_slot(-1)

func _slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2.ONE * SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.icon = load("res://assets/ui/icons/%s.png" % SLOTS[i][0])
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 43)
	b.pressed.connect(use_slot.bind(i))
	b.mouse_entered.connect(func(): _slot_name.text = SLOTS[i][1])
	b.mouse_exited.connect(func(): if _on >= 0: _slot_name.text = SLOTS[_on][1])
	var n := Label.new()
	n.add_theme_font_override("font", Brand.FONT_DISPLAY)
	n.add_theme_font_size_override("font_size", 11)
	n.modulate.a = 0.85
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.text = str(i + 1)
	n.add_theme_color_override("font_color", Color.WHITE)    # coloured by modulate, as the slot rises
	b.add_child(n)
	var look := StyleBoxFlat.new()
	look.set_corner_radius_all(14)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, look)
	_looks.append(look)
	_lift.append(0.0)
	_ring.append(0.0)
	_raising.append(null)
	b.draw.connect(_draw_ring.bind(i))
	return b

## The slot's look, as on the board: the one in use is cream, lifted, with a green ring round it. The name over the bar always
## shows: the slot in use, or the last one named. A slot taken up rises and its ring draws round it; one put away settles back.
func _mark_slot(on: int) -> void:
	var was := _on
	_on = on
	if on >= 0 or _slot_name.text == "": _slot_name.text = SLOTS[maxi(on, 0)][1]
	if was == on: return
	for i in [was, on]:
		if i < 0: continue
		if _raising[i]: _raising[i].kill()
		var to := 1.0 if i == on else 0.0
		if not HudMotion.on:
			_set_lift(to, i)
			_set_ring(to, i)
			continue
		var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_method(_set_lift.bind(i), _lift[i], to, LIFT_TIME if to > 0.0 else SETTLE)
		t.tween_method(_set_ring.bind(i), _ring[i], to, RING_TIME if to > 0.0 else SETTLE).set_delay(0.12 if to > 0.0 else 0.0)
		_raising[i] = t

## The slot's face drawn LIFT higher as it rises (the container keeps its place), turning from dark to cream.
func _set_lift(v: float, i: int) -> void:
	_lift[i] = v
	var look := _looks[i]
	look.bg_color = SLOT_OFF.lerp(Brand.CREAM, v)
	look.expand_margin_top = LIFT * v
	look.expand_margin_bottom = -LIFT * v
	look.content_margin_bottom = LIFT * 2.0 * v
	var n: Label = _slots[i].get_child(0)
	n.position = Vector2(7, 4 - LIFT * v)
	n.modulate = Color(Brand.CREAM.lerp(Brand.PLATE, v), 0.85)
	_slots[i].queue_redraw()

func _set_ring(v: float, i: int) -> void:
	_ring[i] = v
	_slots[i].queue_redraw()

## The green ring outside the slot, drawn round it clockwise from the top left, as far as it has got: the board's stroke-dashoffset.
func _draw_ring(i: int) -> void:
	if _ring[i] <= 0.0: return
	var b := _slots[i]
	var r := 15.5                         # the ring's middle: 3 px wide, outside the slot's 14 px corners
	var side := SLOT + 3.0 - r * 2.0
	var left := _ring[i] * (side * 4.0 + TAU * r)
	var p := Vector2(-1.5 + r, -1.5 - LIFT * _lift[i])
	for k in 4:
		var way: Vector2 = RING_WAY[k]
		b.draw_line(p, p + way * minf(left, side), Brand.GREEN, 3.0, true)
		left -= side
		p += way * side
		if left <= 0.0: return
		var mid: Vector2 = p + RING_WAY[(k + 1) % 4] * r
		var from := -PI * 0.5 + k * PI * 0.5
		b.draw_arc(mid, r, from, from + minf(left / r, PI * 0.5), 8, Brand.GREEN, 3.0, true)
		left -= r * PI * 0.5
		p = mid + way * r
		if left <= 0.0: return

## A slot squashes under a press.
func _squash(i: int) -> void:
	if not HudMotion.on: return
	var b := _slots[i]
	b.pivot_offset = b.size * 0.5
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE * SQUASH, 0.04).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Press a slot, by key or mouse. Pressing what's open puts it away.
func use_slot(i: int) -> void:
	_squash(i)
	var what: String = SLOTS[i][2]
	if what == "mentor":
		if phone.is_open: phone.toggle()
		mentor.toggle()
		_mark_slot(i if mentor.is_open else -1)
		return
	if mentor.is_open: mentor.toggle()
	phone.open_page(what)
	_mark_slot(i if phone.is_open else -1)

## Bottom right, as on the board: the keys that do something out in the world, as they're bound now.
func _build_keys() -> void:
	_keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_keys.offset_right = -21
	_keys.offset_bottom = -21
	_keys.add_theme_constant_override("separation", 7)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keys)
	_write_keys()

func _write_keys() -> void:
	var said := ",".join(KEYS.map(func(k): return ",".join(k[0].map(_key_name))))
	if said == _keys_said: return
	_keys_said = said
	for old in _keys.get_children():
		_keys.remove_child(old)
		old.queue_free()
	for k in KEYS:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 7)
		for action in k[0]:
			row.add_child(key_cap(_key_name(action)))
		var what := on_scene(Label.new(), Brand.FONT_BODY, 12)
		what.text = k[1]
		row.add_child(what)
		_keys.add_child(row)

static func _key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode if e.keycode == KEY_NONE else e.keycode)
	return "?"

func _build_toast() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.ORANGE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(18)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 7
	s.content_margin_bottom = 0
	_toast.add_theme_stylebox_override("panel", Brand.as_plate(s))
	_toast.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW    # the timer bar, round the corners
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/ui/icons/siren.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	row.add_child(icon)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	for pair in [[_toast_title, 13], [_toast_sub, 12]]:
		var l: Label = pair[0]
		l.add_theme_font_override("font", Brand.FONT_BODY)
		l.add_theme_font_size_override("font_size", pair[1])
		l.add_theme_color_override("font_color", Color.BLACK)
		column.add_child(l)
	row.add_child(column)
	var padded := MarginContainer.new()   # the board's .8rem 2.4rem .8rem .8rem
	padded.add_theme_constant_override("margin_left", 7)
	padded.add_theme_constant_override("margin_right", 21)
	padded.add_theme_constant_override("margin_bottom", 7)
	padded.add_child(row)
	# the board's timer: a dark .4rem bar along the bottom, draining while the toast shows
	_toast_bar.custom_minimum_size.y = 4
	_toast_bar.draw.connect(func(): _toast_bar.draw_rect(Rect2(0, 0, _toast_bar.size.x * _toast_left / TOAST_FOR, 4), Color(0, 0, 0, 0.35)))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.add_child(padded)
	stack.add_child(_toast_bar)
	_toast.add_child(stack)
	_toast.visible = false
	add_child(_toast)

## The town has changed: the island says so now, as a town moment (Island); the toast's plate stays hidden.
func toast(title: String, sub: String) -> void:
	if Island.up: Island.up.town(title, sub)

func _build_map() -> void:
	if world == null: return
	_map = load("res://scripts/ui/minimap.gd").new()
	_map.world = world
	add_child(_map)
	_place_box.size = Vector2(300, 20)
	_place_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for l in [_place, _place_old]:
		on_scene(l, Brand.FONT_BODY, 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size = _place_box.size
		_place_box.add_child(l)
	add_child(_place_box)

## The minimap's gold marker: where your first quest's next step is (world x, z), or INF for nowhere.
func set_goal(at: Vector2) -> void:
	if _map: _map.goal = at

## A new place: its name rolls up into view as the last one rolls away.
func _roll_place(here: String) -> void:
	if _place_roll: _place_roll.kill()
	_place_old.text = _place.text
	_place.text = here
	if _place_old.text == "" or not HudMotion.on:
		_place_old.text = ""
		_place.position.y = 0.0
		_place.modulate.a = 1.0
		return
	_place_old.position.y = 0.0
	_place_old.modulate.a = 1.0
	_place.position.y = PLACE_ROLL
	_place.modulate.a = 0.0
	_place_roll = create_tween().set_parallel().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_place_roll.tween_property(_place_old, "position:y", -PLACE_ROLL, 0.4)
	_place_roll.tween_property(_place_old, "modulate:a", 0.0, 0.4)
	_place_roll.tween_property(_place, "position:y", 0.0, 0.4)
	_place_roll.tween_property(_place, "modulate:a", 1.0, 0.4)

func _refresh() -> void:
	_write_keys()    # a rebind in settings shows on the next word from the server
	var shock := str(client.city.get("shock", ""))
	if shock != _last_shock:
		_last_shock = shock
		if SHOCKS.has(shock): toast(SHOCKS[shock][0], SHOCKS[shock][1])

func _on_event(e: Dictionary) -> void:
	if e.type == "FeedPost": _say_on_ticker(str(e.text))

func _process(delta: float) -> void:
	if _toast.visible:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false
		_toast.reset_size()
		_toast.position = Vector2((size.x - _toast.size.x) * 0.5, TOAST_AT)
		_toast_bar.queue_redraw()
	if _map:
		# right-aligned under the map's plate, the board's 1.2rem below it
		_place_box.position = Vector2(size.x - 300.0 - 21.0, 21.0 + _map.PLATE + 11.0)
		var here := _where_am_i()
		if here != _place.text: _roll_place(here)

## The name of the place you're at: the landing, the square, or the building you're in or by (world.json's sites); else the town.
func _where_am_i() -> String:
	var p: Vector3 = world.player.global_position
	var at := Vector2(p.x, p.z)
	if at.distance_to(Vector2(Opening.JETTY_AT.x, Opening.JETTY_AT.z)) < PLACE_NEAR * 2.5: return "The Landing"
	if at.distance_to(Vector2(Tallyport.PLACES.square.x, Tallyport.PLACES.square.z)) < PLACE_NEAR * 2.0: return "Tally Square"
	var best := "Tallyport"
	var nearest := PLACE_NEAR
	for site in world.data.d.get("sites", []):
		var d := ((at - WorldData.v2(site.pos)).abs() - WorldData.v2(site.half)).max(Vector2.ZERO).length()   # 0 inside its footprint
		if d < nearest:
			nearest = d
			best = str(site.get("name", best))
	return best

func _unhandled_key_input(e: InputEvent) -> void:
	if not e.is_pressed() or e.is_echo(): return
	if e.keycode >= KEY_1 and e.keycode < KEY_1 + SLOTS.size():
		use_slot(e.keycode - KEY_1)
		get_viewport().set_input_as_handled()
