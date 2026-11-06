class_name ShiftScreen
extends Control
## A Market Rush run, laid out as the design board's stall shift (GameShift): your best run, the orders served this run, the order up on
## the chalkboard, Kofi's word, what's in your hands and the key that hands it over. Up only during a run, and it takes the HUD's corners
## while it is. Rules: StallShift; the count: the server's OrderServed. Board values are rem at 1440, so x 8.89 px here.

const CastScript := preload("res://scripts/life/cast.gd")
const COIN := preload("res://assets/ui/coin_mark.svg")
const MINT := Color("BDEDD0")
const GOLD := Color("F0C33A")
const GO := Color("55C06C")
const GO_INK := Color("10220f")
const CHALK := Color("22323d")
const WOOD := Color("b8874f")
const WOOD_LIGHT := Color("d6a86a")
const WOOD_DARK := Color("8d6434")
const PATIENCE := Color("FF9a5c")
const EDGE := 21.0               # 2.4rem
const CARD_W := 240.0            # 27rem
const BASKET := Vector2(320, 187)
const WEAVE := 320.0 / 360.0     # the basket's svg, 360 x 140, at 36rem
const POP := 0.9                 # s

var stall: MarketStall
var client: TownClient

var _best := Label.new()
var _best_words := Label.new()
var _served := Label.new()
var _keeper := PanelContainer.new()
var _keeper_line := Label.new()
var _card := PanelContainer.new()
var _order_no := Label.new()
var _want_row := HBoxContainer.new()
var _want_icon := TextureRect.new()
var _want := Label.new()
var _tick := Label.new()
var _patience := ProgressBar.new()
var _held := Control.new()
var _held_icon := TextureRect.new()
var _packed := Label.new()
var _hand := PanelContainer.new()
var _count := 0                  # this run's orders, as the server counted them
var _left := Label.new()         # the server's clock on the run: rush_ends_at, counted down
var _combo := Label.new()        # orders handed over in quick succession: how it feels, not what it scores
var _combo_n := 0
var _last_serve := -INF
const COMBO_WITHIN := 6.0        # s between two orders that keep a combo going
var _covered: Array = []         # [plate, its alpha]: the HUD's, hidden while the shift's own are up

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_best()
	_build_served()
	_build_keeper()
	_build_card()
	_build_basket()
	_build_hand()
	for n in find_children("*", "Control", true, false): (n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	client.event.connect(_on_event)

func _plate(radius: int, left: int, right: int, vertical: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.content_margin_left = left
	s.content_margin_right = right
	s.content_margin_top = vertical
	s.content_margin_bottom = vertical
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 9)
	return s

func _text(label: Label, font: Font, font_size: int, colour := Brand.CREAM) -> Label:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _bar(bar: ProgressBar, track: Color, fill: Color) -> ProgressBar:
	for part in [["background", track], ["fill", fill]]:
		var s := StyleBoxFlat.new()
		s.bg_color = part[1]
		s.set_corner_radius_all(99)
		bar.add_theme_stylebox_override(part[0], s)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = 5
	return bar

func _key_cap(key: String, face: Color, ink: Color) -> Label:
	var cap := _text(Label.new(), Brand.FONT_DISPLAY, 12, ink)
	var s := StyleBoxFlat.new()
	s.bg_color = face
	s.set_corner_radius_all(7)
	s.content_margin_left = 7
	s.content_margin_right = 7
	cap.add_theme_stylebox_override("normal", s)
	cap.text = key
	cap.custom_minimum_size = Vector2(25, 25)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return cap

## Top left, in the energy plate's place: your best run this season.
func _build_best() -> void:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _plate(99, 7, 21, 7))
	plate.position = Vector2.ONE * EDGE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	var disc := Panel.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.BLUE
	look.set_corner_radius_all(99)
	disc.add_theme_stylebox_override("panel", look)
	disc.custom_minimum_size = Vector2(36, 36)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark := TextureRect.new()
	mark.texture = COIN
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.position = Vector2(9, 9)
	mark.size = Vector2(18, 18)
	disc.add_child(mark)
	row.add_child(disc)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_text(_best, Brand.FONT_NUMBER, 25))
	column.add_child(_text(_best_words, Brand.FONT_BODY, 12, MINT))
	row.add_child(column)
	plate.add_child(row)
	add_child(plate)

## Top right, where the board counts a streak: the game has no streak, so just the orders this run.
func _build_served() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.offset_right = -EDGE
	column.offset_top = EDGE
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	GameHud.on_scene(_served, Brand.FONT_NUMBER, 71, GOLD)
	_served.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_served.add_theme_constant_override("line_spacing", -8)
	column.add_child(_served)
	var words := GameHud.on_scene(Label.new(), Brand.FONT_BODY, 13)
	words.text = "served this run"
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(words)
	GameHud.on_scene(_left, Brand.FONT_NUMBER, 34)
	_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_left)
	GameHud.on_scene(_combo, Brand.FONT_DISPLAY, 18, MINT)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_combo)
	add_child(column)

## Kofi, in his cream speech bubble: his line from the cast.
func _build_keeper() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.CREAM
	s.set_corner_radius_all(14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 9)
	_keeper.add_theme_stylebox_override("panel", s)
	_keeper.anchor_left = 0.24
	_keeper.anchor_top = 0.21
	_keeper.custom_minimum_size.x = CARD_W
	_text(_keeper_line, Brand.FONT_BODY, 13, Brand.PLATE)
	_keeper_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keeper_line.add_theme_constant_override("line_spacing", 1)
	_keeper.add_child(_keeper_line)
	_keeper.draw.connect(func():
		var x := _keeper.size.x * 0.62
		var y := _keeper.size.y
		_keeper.draw_colored_polygon(PackedVector2Array([Vector2(x - 9, y), Vector2(x + 9, y), Vector2(x, y + 10)]), Brand.CREAM))
	add_child(_keeper)

## The order at the counter, up on the chalkboard, with how long they'll still wait.
func _build_card() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = CHALK
	s.border_color = WOOD
	s.set_border_width_all(7)
	s.set_corner_radius_all(7)
	s.set_content_margin_all(21)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 14)
	_card.add_theme_stylebox_override("panel", s)
	_card.anchor_left = 0.76
	_card.anchor_top = 0.21
	_card.custom_minimum_size.x = CARD_W
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	column.add_child(_text(_order_no, Brand.FONT_DISPLAY, 18))
	_want_row.add_theme_constant_override("separation", 9)
	_want_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_want_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_want_icon.custom_minimum_size = Vector2(27, 27)
	_want_row.add_child(_want_icon)
	_text(_want, Brand.FONT_BODY, 15)
	_want.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_want_row.add_child(_want)
	_want_row.add_child(_text(_tick, Brand.FONT_NUMBER, 13))
	column.add_child(_want_row)
	column.add_child(_bar(_patience, Color(Brand.CREAM, 0.2), PATIENCE))
	var words := _text(Label.new(), Brand.FONT_BODY, 11)
	words.text = "customer's patience"
	words.modulate.a = 0.8
	column.add_child(words)
	_card.add_child(column)
	add_child(_card)

## Bottom centre: the basket, and what's in your hands in it.
func _build_basket() -> void:
	var basket := Control.new()
	basket.anchor_left = 0.5
	basket.anchor_right = 0.5
	basket.anchor_top = 1.0
	basket.anchor_bottom = 1.0
	basket.offset_left = -BASKET.x * 0.5
	basket.offset_right = BASKET.x * 0.5
	basket.offset_top = -BASKET.y
	_held.position = Vector2((BASKET.x - 64.0) * 0.5, 89.0 - 64.0)
	_held_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_held_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_held_icon.size = Vector2(64, 64)
	_held.add_child(_held_icon)
	var badge := _text(Label.new(), Brand.FONT_NUMBER, 12)
	var ring := StyleBoxFlat.new()
	ring.bg_color = Brand.PLATE
	ring.border_color = Brand.CREAM
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(99)
	badge.add_theme_stylebox_override("normal", ring)
	badge.text = "×1"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.size = Vector2(25, 25)
	badge.position = Vector2(64 - 25 + 4, -4)
	_held.add_child(badge)
	basket.add_child(_held)
	var weave := Control.new()
	weave.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weave.draw.connect(_draw_basket.bind(weave))
	basket.add_child(weave)
	GameHud.on_scene(_packed, Brand.FONT_DISPLAY, 43, MINT)
	_packed.text = "PACKED!"
	_packed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_packed.size = Vector2(BASKET.x, 60)
	_packed.position.y = -36
	_packed.visible = false
	basket.add_child(_packed)
	add_child(basket)

func _draw_basket(on: Control) -> void:
	var top := BASKET.y - 140.0 * WEAVE
	var at := func(x: float, y: float) -> Vector2: return Vector2(x, y) * WEAVE + Vector2(0, top)
	on.draw_colored_polygon(PackedVector2Array([at.call(10, 20), at.call(350, 20), at.call(320, 140), at.call(40, 140)]), WOOD)
	on.draw_colored_polygon(PackedVector2Array([at.call(10, 20), at.call(350, 20), at.call(350, 38), at.call(14, 38)]), WOOD_LIGHT)
	for l in [[26, 60, 334, 60], [36, 88, 324, 88], [44, 116, 316, 116], [80, 38, 92, 140], [140, 38, 146, 140], [200, 38, 196, 140], [260, 38, 250, 140], [320, 38, 300, 140]]:
		on.draw_line(at.call(l[0], l[1]), at.call(l[2], l[3]), WOOD_DARK, 4.0 * WEAVE)

## Right of the basket: the key that hands it over, lit when what you hold is what they want.
func _build_hand() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = GO
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(99)
	s.content_margin_left = 11
	s.content_margin_right = 21
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 9)
	_hand.add_theme_stylebox_override("panel", s)
	_hand.anchor_left = 0.5
	_hand.anchor_top = 1.0
	_hand.anchor_bottom = 1.0
	_hand.offset_left = 178
	_hand.offset_top = -86
	_hand.offset_bottom = -36
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	row.add_child(_key_cap(MarketStall.KEY, GO_INK, GO))
	var words := _text(Label.new(), Brand.FONT_BODY, 16, GO_INK)
	words.text = "Hand it over"
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	_hand.add_child(row)
	add_child(_hand)

func _process(_delta: float) -> void:
	if stall.in_rush != visible: _show(stall.in_rush)
	if not visible: return
	_write_best()
	var ms := TownState.rush_left(client.you, client.now_ms())
	_left.text = "%s left" % TownState.clock(ms)
	_left.add_theme_color_override("font_color", Brand.ORANGE if ms < 10000 else Brand.CREAM)
	_combo.visible = _combo_n >= 2 and Time.get_ticks_msec() / 1000.0 - _last_serve < COMBO_WITHIN
	var shift := stall.shift
	var front: MarketCustomer = stall._queue[0] if not stall._queue.is_empty() else null
	_card.visible = front != null and shift.wanted() != ""
	if _card.visible:
		var item := shift.wanted()
		var ok := shift.held == item
		_order_no.text = "ORDER #%d" % int(shift.orders[0].id)
		_want_icon.texture = MarketStall.ITEM_ICONS[item]
		_want.text = "1× " + str(MarketStall.ITEM_NAMES[item])
		_tick.text = "✓" if ok else "0/1"
		_want_row.modulate.a = 0.55 if ok else 1.0
		_patience.value = front.patience / maxf(float(front.get_meta("patience", front.patience)), 0.001)
	_held.visible = shift.held != ""
	if _held.visible: _held_icon.texture = MarketStall.ITEM_ICONS[shift.held]
	_hand.modulate.a = 1.0 if shift.action("") == StallShift.Do.SERVE else 0.5

func _show(on: bool) -> void:
	visible = on
	if not on:
		_uncover()
		return
	_count = 0
	_combo_n = 0
	_served.text = "0"
	_write_best()
	_write_keeper()
	for n in get_parent().get_children():
		if n is EnergyPlate or n is GameHud:
			_covered.append([n, n.modulate.a])
			n.modulate.a = 0.0

func _uncover() -> void:
	for c in _covered:
		if is_instance_valid(c[0]): c[0].modulate.a = c[1]
	_covered.clear()

func _exit_tree() -> void:
	_uncover()

## The server's best run, and this one if it's already better: the board's own number catches up when the run ends.
func _write_best() -> void:
	var best := maxi(int(client.you.get("best_run", 0)), _count)
	_best.text = str(best)
	_best_words.text = ("your best this season · today %d" % int(client.you.get("best_today", 0))) if best > 0 else "no runs yet this season"

func _write_keeper() -> void:
	var firsts := {}
	for f in client.you.get("firsts", []): firsts[str(f.get("first", ""))] = true
	_keeper_line.text = "%s: %s" % [CastScript.PEOPLE.kofi.name, CastScript.line("kofi", {"milestones": firsts})]

func _on_event(e: Dictionary) -> void:
	if not visible or str(e.get("account", "")) != client.player: return
	match e.type:
		"OrderServed":
			_count = int(e.get("served", _count + 1))
			_served.text = str(_count)
			var now := Time.get_ticks_msec() / 1000.0
			_combo_n = _combo_n + 1 if now - _last_serve < COMBO_WITHIN else 1
			_last_serve = now
			_combo.text = "COMBO x%d" % _combo_n
			_write_best()
			_packed.visible = true
			_packed.modulate.a = 1.0
			var t := create_tween()
			t.tween_interval(POP * 0.75)
			t.tween_property(_packed, "modulate:a", 0.0, POP * 0.25)
		"FirstEarned": _write_keeper()
