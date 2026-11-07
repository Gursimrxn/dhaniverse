class_name GameHud
extends Control
## The HUD around the plates, as on the design board (ux02, scaled from 1440x810 to the 1280x720 canvas): the minimap with the
## place inside it, the mentor's plate under it when the mentor has something to say, the quest tracker under your wallet (an urgent
## crate first, then the quest you're tracking with its next step, then the others), and the pocket of five pages at the bottom,
## keys 1 to 5. The phone takes the screen's right when it's out, and these step away for it (ux10).

const SLOT := 41.0               # the pocket's slots, each its own plate
const SLOT_R := 12
const SLOT_GAP := 14.0
const POCKET_BOTTOM := 41.0      # px from the screen's bottom to the slots' bottom; their names hang under them
const ICON := 20.0
const LIFT := 6.0                # px the slot in use rises
const LIFT_TIME := 0.52          # s the chosen slot takes to rise
const RING_TIME := 0.64          # s its green ring takes to draw round it
const SETTLE := 0.3              # s a slot put away takes to settle
const SQUASH := 0.94             # a press
const RING_WAY := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]   # the ring's sides, clockwise from the top
const NOTE := Color("C9C1A6")    # the board's small print
const CAP_EDGE := Color("9d9477")
const PLACE_NEAR := 6.0          # m from a building's footprint: you're at it
const MENTOR_AT := 193.0         # px from the top: under the minimap
const MENTOR_W := 258.0
const MENTOR_FOR := 9.0          # s the mentor's line stays up
const TRACKER_W := 267.0         # as wide as the plates over it
const TRACKER_OTHERS := 3        # the quests not tracked, listed under it
const TRACKER_EVERY := 0.25      # s between rewrites
const ROOM_NAMES := ["The Bank", "Market Hall", "Common Table", "Arrival Hall", "The Homes"]   # world.gd's ROOMS, in their order
# key, page, the name under the slot
const SLOTS := [["wallet", "WALLET"], ["quests", "QUESTS"], ["feed", "FEED"], ["town", "TOWN"], ["mentor", "MENTOR"]]

var client: TownClient
var phone: Phone
var mentor: MentorChat
var world: Node

var _marks := WorldMarks.new()
var _pocket := HBoxContainer.new()
var _slots: Array[Button] = []
var _looks: Array[StyleBoxFlat] = []
var _count := Label.new()        # on Quests: how many you're on
var _on := -1
var _lift := PackedFloat32Array()    # each slot: how far it has risen
var _ring := PackedFloat32Array()    # each slot: how much of its ring is drawn
var _raising: Array[Tween] = []
var _map: Control
var _right := Control.new()       # the mentor's plate, under the map: what the phone puts away
var _mentor := PanelContainer.new()
var _mentor_line := Label.new()
var _mentor_left := 0.0
var _mentor_fade: Tween
var _tracker := PanelContainer.new()
var _tracker_rows := VBoxContainer.new()
var _tracker_in := 0.0
var _tracker_said := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.world = world     # ux07: badges and the goal over the town, under the plates
	_marks.client = client
	add_child(_marks)
	var slips := JobSlip.new()     # ux03: the job slip a quest prints, and a receipt for every cent
	slips.client = client
	slips.wallet_at = func(): return world.energy_plate.global_position + Vector2(20, 100) if world and world.energy_plate else Vector2(40, 110)
	add_child(slips)
	_build_pocket()
	_build_map()
	_build_mentor()
	_build_tracker()
	if phone: phone.toggled.connect(_phone_out)
	if mentor: mentor.said.connect(_mentor_says)
	client.you_changed.connect(_refresh)
	client.synced.connect(_refresh)

## The phone is out (ux10): it has the right of the screen and its own tabs, so the map, the mentor and the pocket step away.
func _phone_out(out: bool) -> void:
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for part in [_pocket, _map, _right, _tracker, _marks]:
		if part: t.tween_property(part, "modulate:a", 0.0 if out else 1.0, 0.2)
	if world and world.energy_plate: world.energy_plate.phone_out(out)

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

## The key an action is bound to now, as its cap prints it.
static func _key_name(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode if e.keycode == KEY_NONE else e.keycode)
	return "?"

# --- the pocket ----------------------------------------------------------------------------------------------------------

## Five slots in a row at the bottom middle, each a small dark plate in a cream ring, its key in the corner and its name under it.
func _build_pocket() -> void:
	_pocket.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_pocket.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pocket.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pocket.offset_bottom = -POCKET_BOTTOM
	_pocket.add_theme_constant_override("separation", SLOT_GAP)
	_pocket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in SLOTS.size():
		var b := _slot(i)
		_slots.append(b)
		_pocket.add_child(b)
	add_child(_pocket)
	for i in _slots.size(): _set_lift(0.0, i)
	_count.add_theme_font_override("font", Brand.FONT_DISPLAY)
	_count.add_theme_font_size_override("font_size", 10)
	_count.add_theme_color_override("font_color", Brand.PLATE)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Brand.CREAM
	pill.set_corner_radius_all(9)
	pill.content_margin_left = 4
	pill.content_margin_right = 4
	_count.add_theme_stylebox_override("normal", pill)
	_count.custom_minimum_size = Vector2(18, 18)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.visible = false
	_slots[1].add_child(_count)

func _slot(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2.ONE * SLOT
	b.focus_mode = Control.FOCUS_NONE
	b.icon = load("res://assets/ui/icons/pocket_%s.svg" % SLOTS[i][0])
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", int(ICON))
	b.pressed.connect(use_slot.bind(i))
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(2)
	look.set_expand_margin_all(2)      # the ring sits outside the slot, as the board's box-shadow does
	look.set_corner_radius_all(SLOT_R)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, look)
	_looks.append(look)
	var n := Label.new()               # its key, in the corner
	n.add_theme_font_override("font", Brand.FONT_DISPLAY)
	n.add_theme_font_size_override("font_size", 9)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.text = str(i + 1)
	n.position = Vector2(4, 1)
	b.add_child(n)
	var cap := Label.new()             # its name, under it on the scene
	cap.text = SLOTS[i][1]
	cap.add_theme_font_override("font", Brand.FONT_DISPLAY)
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Brand.CREAM)
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	cap.add_theme_constant_override("shadow_offset_y", 1)
	cap.add_theme_constant_override("shadow_outline_size", 3)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.position = Vector2(-14, SLOT + 5)
	cap.size = Vector2(SLOT + 28, 14)
	b.add_child(cap)
	_lift.append(0.0)
	_ring.append(0.0)
	_raising.append(null)
	b.draw.connect(_draw_ring.bind(i))
	return b

## The slot in use rises, turns cream and a green ring draws round it; one put away settles back.
func _mark_slot(on: int) -> void:
	var was := _on
	_on = on
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

## The slot's face drawn LIFT higher as it rises (the row keeps its place), from dark to cream, its ink turning with it.
func _set_lift(v: float, i: int) -> void:
	_lift[i] = v
	var look := _looks[i]
	look.bg_color = Brand.PLATE.lerp(Brand.CREAM, v)
	look.expand_margin_top = 2.0 + LIFT * v
	look.expand_margin_bottom = 2.0 - LIFT * v
	var b := _slots[i]
	var ink := Brand.CREAM.lerp(Brand.PLATE, v)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: b.add_theme_color_override(state, ink)
	b.add_theme_constant_override("icon_max_width", int(ICON))
	var n: Label = b.get_child(0)
	n.position = Vector2(4, 1 - LIFT * v)
	n.add_theme_color_override("font_color", NOTE.lerp(Brand.PLATE, v))
	b.queue_redraw()

func _set_ring(v: float, i: int) -> void:
	_ring[i] = v
	_slots[i].queue_redraw()

## The green ring over the cream one, drawn round the slot clockwise from the top left, as far as it has got.
func _draw_ring(i: int) -> void:
	if _ring[i] <= 0.0: return
	var b := _slots[i]
	var r := SLOT_R + 1.0                  # the ring's middle, 2 px outside the slot's corners
	var side := SLOT + 2.0 - r * 2.0
	var left := _ring[i] * (side * 4.0 + TAU * r)
	var p := Vector2(-1.0 + r, -1.0 - LIFT * _lift[i])
	for k in 4:
		var way: Vector2 = RING_WAY[k]
		b.draw_line(p, p + way * minf(left, side), Brand.GREEN, 2.5, true)
		left -= side
		p += way * side
		if left <= 0.0: return
		var mid: Vector2 = p + RING_WAY[(k + 1) % 4] * r
		var from := -PI * 0.5 + k * PI * 0.5
		b.draw_arc(mid, r, from, from + minf(left / r, PI * 0.5), 8, Brand.GREEN, 2.5, true)
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
	if not phone.is_open and not mentor.is_open and not Screens.free_to_open(): return     # the pause menu, a sheet or a film has the screen
	_squash(i)
	var what: String = SLOTS[i][0]
	if what == "mentor":
		if phone.is_open: phone.toggle()
		mentor.toggle()
		_mark_slot(i if mentor.is_open else -1)
		return
	if mentor.is_open: mentor.toggle()
	phone.open_page(what)
	_mark_slot(i if phone.is_open else -1)

# --- the map and the mentor ----------------------------------------------------------------------------------------------

func _build_map() -> void:
	if world == null: return
	_map = load("res://scripts/ui/minimap.gd").new()
	_map.world = world
	add_child(_map)

## The minimap's gold marker: where your first quest's next step is (world x, z), or INF for nowhere.
func set_goal(at: Vector2) -> void:
	if _map: _map.goal = at

## The place shown inside the minimap.
func place_name() -> String:
	return _map.place if _map else ""

## Under the minimap: the mentor's line in the serif italic and "H Ask the mentor", for a while after something real happened.
func _build_mentor() -> void:
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_expand_margin_all(3)
	look.set_corner_radius_all(18)
	look.content_margin_left = 12
	look.content_margin_right = 12
	look.content_margin_top = 11
	look.content_margin_bottom = 11
	_mentor.add_theme_stylebox_override("panel", Brand.as_plate(look))
	_mentor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mentor.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mentor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mentor.offset_right = -21
	_mentor.offset_top = MENTOR_AT
	_mentor.custom_minimum_size.x = MENTOR_W
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mentor_line.add_theme_font_override("font", Brand.FONT_EDITORIAL_ITALIC)
	_mentor_line.add_theme_font_size_override("font_size", 16)
	_mentor_line.add_theme_color_override("font_color", Brand.CREAM)
	_mentor_line.add_theme_constant_override("line_spacing", roundi(16 * 1.25 - Brand.FONT_EDITORIAL_ITALIC.get_height(16)))
	_mentor_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mentor_line.custom_minimum_size.x = MENTOR_W - 24.0
	column.add_child(_mentor_line)
	var ask := HBoxContainer.new()
	ask.add_theme_constant_override("separation", 7)
	ask.add_child(key_cap("H", 11))
	var words := Label.new()
	words.text = "Ask the mentor"
	words.add_theme_font_override("font", Brand.FONT_BODY)
	words.add_theme_font_size_override("font_size", 11)
	words.add_theme_color_override("font_color", NOTE)
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ask.add_child(words)
	column.add_child(ask)
	_mentor.add_child(column)
	_mentor.visible = false
	_right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(_mentor)
	add_child(_right)

func _mentor_says(line: String) -> void:
	_mentor_line.text = "“%s”" % line.strip_edges()
	_mentor_left = MENTOR_FOR
	_show_mentor(true)

func _show_mentor(on: bool) -> void:
	if _mentor_fade: _mentor_fade.kill()
	if on:
		if not _mentor.visible: _mentor.modulate.a = 0.0
		_mentor.visible = true
		_mentor.reset_size()
	_mentor_fade = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN)
	_mentor_fade.tween_property(_mentor, "modulate:a", 1.0 if on else 0.0, 0.3 if HudMotion.on else 0.01)
	if not on: _mentor_fade.tween_callback(_mentor.hide)

# --- the quest tracker ----------------------------------------------------------------------------------------------------

func _build_tracker() -> void:
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_expand_margin_all(3)
	look.set_corner_radius_all(18)
	look.content_margin_left = 14
	look.content_margin_right = 14
	look.content_margin_top = 11
	look.content_margin_bottom = 12
	_tracker.add_theme_stylebox_override("panel", Brand.as_plate(look))
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.custom_minimum_size.x = TRACKER_W
	_tracker_rows.add_theme_constant_override("separation", 6)
	_tracker_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.add_child(_tracker_rows)
	_tracker.visible = false
	add_child(_tracker)

## What's running, rewritten only when its words change: the crate (orange, counting down), the tracked quest (a gold diamond, its
## steps done, its next step and how far), then the others, quieter.
func _write_tracker() -> void:
	if world == null or world.dhaniverse == null: return
	var guide: Guide = world.dhaniverse.guide
	var you := client.you
	var lines: Array = []                 # [kind, words, right]
	var crate: Dictionary = world.loot.current() if world.loot else {}
	if not crate.is_empty():
		var left := TownState.clock(TownState.left_ms(crate.ends_at, client.now_ms()))
		lines.append(["urgent", "URGENT · LOOT CRATE", left])
		lines.append(["crate", "%s · %s" % [Usdc.text(int(crate.prize)), world.loot.place_words()], ""])
	var quests: Array = you.get("quests", [])
	var tracked := TownState.quest(you, guide.tracked)
	if not tracked.is_empty():
		if not lines.is_empty(): lines.append(["gap", "", ""])
		lines.append(["head", "QUEST", "%d/%d" % [TownState.steps_done(tracked), tracked.get("steps", []).size()]])
		lines.append(["title", str(tracked.get("title", "")), ""])
		var step := TownState.next_step(tracked)
		if not step.is_empty():
			var far := guide.next_distance() if crate.is_empty() else INF
			lines.append(["next", TownState.step_says(tracked, step) + (" · %d m" % roundi(far) if far != INF else ""), ""])
	var others := quests.filter(func(q): return str(q.get("quest", "")) != guide.tracked)
	for i in mini(others.size(), TRACKER_OTHERS):
		if i == 0: lines.append(["gap", "", ""])
		lines.append(["other", str(others[i].get("title", "")), "%d/%d" % [TownState.steps_done(others[i]), others[i].get("steps", []).size()]])
	var said := str(lines)
	if said == _tracker_said: return
	_tracker_said = said
	for old in _tracker_rows.get_children():
		_tracker_rows.remove_child(old)
		old.queue_free()
	for line in lines: _tracker_rows.add_child(_tracker_line(line))
	var show := not lines.is_empty()
	if show != _tracker.visible:
		_tracker.visible = show
		if show and HudMotion.on:
			_tracker.modulate.a = 0.0
			create_tween().tween_property(_tracker, "modulate:a", 1.0 if not (phone and phone.is_open) else 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tracker.reset_size()

func _tracker_line(line: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if line[0] == "gap":
		row.custom_minimum_size.y = 2
		return row
	var words := Label.new()
	words.text = line[1]
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# a wrapping label needs its width given, or it wraps a letter a line: the plate, less its padding, the diamond and the number
	words.custom_minimum_size.x = TRACKER_W - 28.0 - (20.0 if line[0] in ["title", "crate"] else 0.0) - (44.0 if line[2] != "" else 0.0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = Brand.FONT_BODY
	var px := 12
	var ink := Brand.CREAM_MUTED
	match line[0]:
		"urgent", "head":
			font = Brand.FONT_DISPLAY
			px = 10
			ink = Brand.ORANGE if line[0] == "urgent" else NOTE
		"crate":
			px = 14
			ink = Brand.CREAM
		"title":
			px = 15
			ink = Brand.CREAM
		"next": ink = Color("F0C33A")
		"other": ink = NOTE
	words.add_theme_font_override("font", font)
	words.add_theme_font_size_override("font_size", px)
	words.add_theme_color_override("font_color", ink)
	if line[0] == "title" or line[0] == "crate":
		var diamond := Control.new()     # the gold diamond the guide puts over the place
		diamond.custom_minimum_size = Vector2(12, 12)
		diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := Brand.ORANGE if line[0] == "crate" else Color("F0C33A")
		diamond.draw.connect(func():
			var pts := PackedVector2Array([Vector2(6, 0), Vector2(12, 6), Vector2(6, 12), Vector2(0, 6)])
			diamond.draw_colored_polygon(pts, fill))
		row.add_child(diamond)
	row.add_child(words)
	if line[2] != "":
		var right := Label.new()
		right.text = line[2]
		right.add_theme_font_override("font", Brand.FONT_BODY if line[0] == "urgent" else Brand.FONT_DISPLAY)     # Bitroad has no colon: the countdown is in Satoshi
		right.add_theme_font_size_override("font_size", 12 if line[0] == "urgent" else 11)
		right.add_theme_color_override("font_color", Brand.ORANGE if line[0] == "urgent" else NOTE)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(right)
	return row

# --- each frame ----------------------------------------------------------------------------------------------------------

func _refresh() -> void:
	var n: int = client.you.get("quests", []).size()
	_count.visible = n > 0
	_count.text = str(n)
	_count.reset_size()
	_count.position = Vector2(SLOT - _count.size.x + 6.0, -6.0)

func _process(delta: float) -> void:
	if _map: _map.place = _where_am_i()
	_tracker_in -= delta
	if _tracker_in <= 0.0:
		_tracker_in = TRACKER_EVERY
		_write_tracker()
	var under: Control = world.energy_plate if world else null
	if under: _tracker.position = Vector2(21.0, under.position.y + under.size.y + 14.0)
	if _mentor_left > 0.0:
		_mentor_left -= delta
		if mentor.is_open: _mentor_left = 0.0     # H: the chat has it now
		if _mentor_left <= 0.0: _show_mentor(false)

## The name of the place you're at: the landing, the square, or the building you're in or by; else the town.
func _where_am_i() -> String:
	var p: Vector3 = world.player.global_position
	var at := Vector2(p.x, p.z)
	if at.distance_to(Vector2(Opening.JETTY_AT.x, Opening.JETTY_AT.z)) < PLACE_NEAR * 2.5: return "The Landing"
	if at.distance_to(Vector2(Dhaniverse.PLACES.square.x, Dhaniverse.PLACES.square.z)) < PLACE_NEAR * 2.0: return "Tally Square"
	var best := "Dhaniverse"
	var nearest := PLACE_NEAR
	var rooms: Array = world.all_rooms()
	for i in mini(ROOM_NAMES.size(), rooms.size()):
		var lo: Vector3 = rooms[i][0]
		var hi: Vector3 = rooms[i][1]
		var d := Vector2(maxf(lo.x - at.x, at.x - hi.x), maxf(lo.z - at.y, at.y - hi.z)).max(Vector2.ZERO).length()   # 0 inside its footprint
		if d < nearest:
			nearest = d
			best = ROOM_NAMES[i]
	return best

func _unhandled_key_input(e: InputEvent) -> void:
	if not e.is_pressed() or e.is_echo(): return
	if e.keycode >= KEY_1 and e.keycode < KEY_1 + SLOTS.size():
		use_slot(e.keycode - KEY_1)
		get_viewport().set_input_as_handled()
