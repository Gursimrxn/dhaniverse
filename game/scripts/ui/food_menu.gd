class_name FoodMenu
extends Control
## The menu at the food counter, as on the design board (GameFood): the live price of each meal in USDC (it moves with every meal anyone
## buys) and which way it moved since yesterday, the most the meal ticket allows, and what eating the chosen thing now would do to your
## energy. The free community thali heads it, once a day. Enter pays from your wallet on chain (BuyMeal), or with a meal voucher (V); the
## ticket shows as pending until the chain says it was eaten (MealEaten) or why not (MealFailed). Everything shown is the server's. The
## counter puts the menu away when the meal comes.

const R := 1280.0 / 144.0          # px per board rem: boards are 1440 wide at 10 px a rem, the game 1280
const BAR := 20                    # energy in one of the HUD's five pips (EnergyPips)
const FULL := 100                  # the most energy the server lets you hold
const GAIN := Color("55C06C")
const OFF := Color(1.0, 0.973, 0.89, 0.15)
const LEADER := Color(1.0, 0.973, 0.89, 0.35)
const WARM := Color("FF9A5C")
const BEST := Color("BDEDD0")
const PLACE := "Tally Square"      # where the Common Table stands

var client: TownClient
var player: CharacterBody3D
var is_open: bool:
	get: return visible

var _cook := ""                   # who cooks here (Cast), or no one: then no quote
var _items := []                   # city.menu, in its order
var _pick := 0
var _now := 0                      # energy now and after, for the pips
var _after := 0
var _rows := VBoxContainer.new()
var _sel_name := _text("", Brand.FONT_BODY, 4.0)
var _energy := _text("", Brand.FONT_DISPLAY, 1.6)
var _pips := Control.new()
var _waste := _text("", Brand.FONT_BODY, 1.4, WARM)
var _price := _text("", Brand.FONT_DISPLAY, 3.2)
var _price_was := _text("", Brand.FONT_BODY, 1.3, Brand.CREAM_MUTED)
var _note := _text("", Brand.FONT_BODY, 1.4, WARM)
var _go := PanelContainer.new()
var _go_words := _text("", Brand.FONT_BODY, 1.8, Brand.PLATE)
var _quote := VBoxContainer.new()
var _said := _text("", Brand.FONT_BODY, 1.8)
var _box := StyleBoxFlat.new()
var _wallet := _text("", Brand.FONT_BODY, 1.4, Brand.CREAM_MUTED)
var _voucher := false              # V: pay with a meal voucher instead
var _sent := false                 # a BuyMeal or FreeMeal sent from here, no answer yet

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = PaperSheet.ABOVE_THE_WORLD
	client.you_changed.connect(_fill)
	client.city_changed.connect(_refresh)
	visible = false
	var g := Gradient.new()
	g.set_color(0, Color("33302a"))
	g.set_color(1, Color("1b1c1c"))
	g.add_point(0.55, Color("262727"))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.3, 0.3)
	tex.fill_to = Vector2(1.1, 0.3)
	var back := TextureRect.new()
	back.texture = tex
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	for id in Cast.PEOPLE:
		if Cast.PEOPLE[id].post == "food": _cook = id
	var counter := ""
	for site in MapData.SITES:
		if site.role == "food": counter = site.name

	var board := _column(6.4, 76.0, 2.4)
	var head := _stack(0.8)
	# the cook and the place, with no possessive: Bitroad has no apostrophe, and "MEIS KITCHEN" read as a typo
	head.add_child(_eyebrow(("%s · %s" % [Cast.PEOPLE[_cook].name, PLACE] if _cook != "" else PLACE).to_upper()))
	head.add_child(_text(counter, Brand.FONT_EDITORIAL_ITALIC, 8.0))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 0)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in ["Live prices: every meal in town moves them. ", true, " dearer than yesterday, ", false, " cheaper."]:
		if part is bool:
			var arrow := Control.new()
			arrow.custom_minimum_size = Vector2(R * 1.0, R * 1.5)
			_arrow_on(arrow, part, Brand.CREAM, R * 1.1)
			sub.add_child(arrow)
		else: sub.add_child(_text(part, Brand.FONT_BODY, 1.5, Brand.CREAM_MUTED))
	head.add_child(sub)
	board.add_child(head)
	_rows.add_theme_constant_override("separation", 0)
	board.add_child(_rows)

	var side := _column(-6.4 - 40.0, 40.0, 3.2)
	var what := _stack(0.8)
	what.add_child(_eyebrow("IF YOU EAT THIS NOW"))
	what.add_child(_sel_name)
	side.add_child(what)
	var energy := _stack(1.2)
	var line := HBoxContainer.new()
	var word := _text("Energy", Brand.FONT_BODY, 1.5)
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(word)
	line.add_child(_energy)
	energy.add_child(line)
	_pips.custom_minimum_size = Vector2(R * (5 * 2.8 + 4 * 0.6 + 2.0 + 1.6), R * 1.6)
	_pips.draw.connect(_draw_pips)
	energy.add_child(_pips)
	energy.add_child(_waste)
	side.add_child(energy)
	var price := _stack(0.4)
	price.add_child(_text("Price", Brand.FONT_BODY, 1.5))
	price.add_child(_price)
	price.add_child(_price_was)
	side.add_child(price)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Brand.CREAM
	pill.set_corner_radius_all(int(R * 99.0))
	pill.content_margin_left = R * 1.2
	pill.content_margin_right = R * 2.4
	_go.add_theme_stylebox_override("panel", pill)
	_go.custom_minimum_size.y = R * 5.6
	_go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_go.gui_input.connect(func(e: InputEvent): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: buy())
	var inside := HBoxContainer.new()
	inside.add_theme_constant_override("separation", int(R * 1.2))
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(_key("Enter", true))
	inside.add_child(_go_words)
	_go.add_child(inside)
	side.add_child(_go)
	side.add_child(_wallet)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = R * 40.0
	side.add_child(_note)

	_quote.add_theme_constant_override("separation", int(R * 0.8))
	_quote.custom_minimum_size.x = R * 40.0
	_quote.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_quote.offset_right = -R * 6.4
	_quote.offset_left = -R * (6.4 + 40.0)
	_quote.offset_bottom = -R * 5.6
	_quote.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_quote.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_quote.visible = _cook != ""
	if _cook != "":
		var by := _eyebrow(("%s · %s" % [Cast.PEOPLE[_cook].name, counter]).to_upper())
		by.modulate.a = 1.0
		by.add_theme_color_override("font_color", WARM)
		_quote.add_child(by)
		_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_said.custom_minimum_size.x = R * 40.0
		_said.add_theme_constant_override("line_spacing", int(R * 0.4))
		_quote.add_child(_said)
	add_child(_quote)

	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", int(R * 1.6))
	keys.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = R * 6.4
	keys.offset_bottom = -R * 5.6
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in [_key("↑"), _key("↓"), _text("Choose", Brand.FONT_BODY, 1.4, Brand.CREAM_MUTED), Control.new(), _key("V"), _text("Voucher", Brand.FONT_BODY, 1.4, Brand.CREAM_MUTED), Control.new(), _key("Esc"), _text("Leave", Brand.FONT_BODY, 1.4, Brand.CREAM_MUTED)]:
		keys.add_child(k)
	add_child(keys)

## food: the one he stands at, picked to start with, so E then Enter chooses it.
func open(food := "") -> void:
	_take_menu(food)
	if _items.is_empty(): return
	_note.text = ""
	_voucher = false
	_sent = false
	if not client.event.is_connected(_on_event):
		client.event.connect(_on_event)
		client.refused.connect(_on_refused)
	if _cook != "": _said.text = "\"%s\"" % Cast.line(_cook, {"milestones": _firsts()})
	visible = true
	player.frozen = true
	_fill()
	for i in _rows.get_child_count():
		var row: Control = _rows.get_child(i)
		var to := row.modulate.a
		row.modulate.a = 0.0
		create_tween().tween_property(row, "modulate:a", to, 0.5).set_delay(0.1 + i * 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func close() -> void:
	if not visible: return
	visible = false
	player.frozen = false
	player.rig.take_cursor_back()

func picked() -> String:
	return str(_items[_pick].name) if _pick < _items.size() else ""

## Enter: the free thali, or a meal ticket to the chain, paid from your wallet or with a voucher. The server says how it went.
func buy() -> void:
	if not visible or _sent or _items.is_empty(): return
	if client.you.get("meal_pending") != null:
		_say(Refusals.say({"type": "MealPending"}))
		return
	var m: Dictionary = _items[_pick]
	_sent = true
	if bool(m.get("free", false)):
		client.send({"type": "FreeMeal"})
		_say("Asking Mei for the thali…", false)
		return
	var c := {"type": "BuyMeal", "item": str(m.name)}
	if _voucher: c["voucher"] = true
	client.send(c)
	_say("Paying with a voucher…" if _voucher else "Paying %s from your wallet…" % Usdc.text(int(m.price)), false)

func _say(text: String, warm := true) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", WARM if warm else BEST)

func _on_event(e: Dictionary) -> void:
	if not visible or str(e.get("account", "")) != client.player: return
	match str(e.type):
		"VoucherUsed": _say("The town pays for it with your voucher…", false)
		"MealOrdered":
			_sent = false
			_say("Paid. Your ticket is on its way to the chain: at most %s. Waiting for it to be eaten…" % Usdc.text(int(e.get("max_usdc", 0))), false)
			_fill()
		"MealFailed":
			_sent = false
			_say("%s Nothing was paid." % Refusals.reason(e.get("reason")).trim_suffix(" Nothing was paid."))
			_fill()

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if not visible or not command.get("type") in ["BuyMeal", "FreeMeal"]: return
	_sent = false
	_say(Refusals.say(refusal, client.now_ms()))

func _input(e: InputEvent) -> void:
	if not visible or not e is InputEventKey or not e.pressed or e.echo: return
	match e.keycode:
		KEY_UP, KEY_W: _choose(_pick - 1)
		KEY_DOWN, KEY_S: _choose(_pick + 1)
		KEY_ENTER, KEY_KP_ENTER: buy()
		KEY_V: _toggle_voucher()
		KEY_ESCAPE: close()
		_: return
	get_viewport().set_input_as_handled()

func _choose(i: int) -> void:
	_pick = clampi(i, 0, _items.size() - 1)
	_note.text = ""
	_fill()

## A meal voucher (from a chest) pays for a thali: the town buys it into your wallet, then it's bought like any other.
func _toggle_voucher() -> void:
	if int(client.you.get("vouchers", 0)) <= 0:
		_voucher = false
		_say(Refusals.say({"type": "NoVoucher"}))
	elif picked() != "thali":
		_voucher = false
		_say("A voucher is good for a thali.")
	else:
		_voucher = not _voucher
		_note.text = ""
	_fill()

func _refresh() -> void:
	if not visible: return
	_take_menu(picked())
	_fill()

## The server's menu, with the free thali at its head, keeping the choice on the same food.
func _take_menu(food: String) -> void:
	_items = [{"name": "free", "free": true, "price": 0, "was": 0, "energy": int(client.city.get("free_meal_energy", 0))}]
	_items.append_array(client.city.get("menu", []))
	_pick = 0
	for i in _items.size():
		if _items[i].name == food: _pick = i

func _fill() -> void:
	if not visible or _items.is_empty(): return
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	var best := 1
	for i in range(1, _items.size()):
		if _per(_items[i]) < _per(_items[best]): best = i
	for i in _items.size(): _rows.add_child(_row(i, i == best))
	var m: Dictionary = _items[_pick]
	_now = int(client.you.get("energy", 0))
	_after = mini(FULL, _now + int(m.energy))
	_sel_name.text = _label(m)
	_energy.text = "%s → %s of 5" % [_bars(_now), _bars(_after)]
	_pips.queue_redraw()
	var wasted := _now + int(m.energy) - FULL
	_waste.visible = wasted > 0
	_waste.text = "You can only hold 5 bars. %s would go to waste." % _bars(wasted)
	var now := client.now_ms()
	var you := client.you
	var pending: bool = you.get("meal_pending") != null
	if bool(m.get("free", false)):
		var ready := TownState.free_meal_ready(you, now)
		_price.text = "Free"
		_price_was.text = "once a day, on the town" if ready else "ready again %s" % TownState.soon(TownState.left_ms(you.get("free_meal_at"), now))
		_go_words.text = "Take the free thali" if ready else "Not yet"
	else:
		_price.text = Usdc.text(int(m.price))
		var was := int(m.get("was", m.price))
		_price_was.text = "at most %s · %s" % [Usdc.text(int(m.get("max_usdc", m.price))), ("yesterday " + Usdc.text(was)) if was != int(m.price) else "the same as yesterday"]
		_go_words.text = "Pay with a voucher" if _voucher else "Pay %s" % Usdc.text(int(m.price))
	if pending: _go_words.text = "Waiting for the chain…"
	var usdc = you.get("usdc")
	var offline := str(client.city.get("chain", "offline")) == "offline"
	_wallet.text = ("Your wallet: %s" % Usdc.text(int(usdc)) if usdc != null else "Your wallet: not ready yet") + (" · rehearsal money" if offline else "") \
		+ (" · %d meal voucher%s (V)" % [int(you.get("vouchers", 0)), "" if int(you.get("vouchers", 0)) == 1 else "s"] if int(you.get("vouchers", 0)) > 0 else "")

func _row(i: int, best: bool) -> Control:
	var m: Dictionary = _items[i]
	var row := MarginContainer.new()
	row.add_theme_constant_override("margin_top", int(R * 1.2))
	row.add_theme_constant_override("margin_bottom", int(R * 1.2))
	row.add_theme_constant_override("margin_left", int(R * 3.2))
	row.modulate.a = 1.0 if i == _pick else 0.5
	row.gui_input.connect(func(e: InputEvent): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _choose(i))
	if i == _pick: row.draw.connect(func(): row.draw_circle(Vector2(R * 0.6, R * 3.2), R * 0.6, Brand.ORANGE))
	var col := _stack(0.4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_ := _text(_label(m), Brand.FONT_BODY, 3.2)
	name_.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(name_)
	var lead := Control.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.draw.connect(func():
		var y := lead.size.y - R * (0.9 + 0.15)
		var x := R * 1.6 + R * 0.15
		while x < lead.size.x - R * 1.6:
			lead.draw_circle(Vector2(x, y), R * 0.15, LEADER)
			x += R * 0.6)
	top.add_child(lead)
	var price := _text("Free" if bool(m.get("free", false)) else Usdc.text(int(m.price)), Brand.FONT_DISPLAY, 3.6)
	price.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(price)
	var moved := int(m.price) - int(m.get("was", m.price))
	if moved != 0:
		var trend := Control.new()
		trend.custom_minimum_size = Vector2(R * (0.4 + 1.4), R * 2.4)
		trend.size_flags_vertical = Control.SIZE_SHRINK_END
		_arrow_on(trend, moved > 0, Brand.CREAM, R * 1.5)
		top.add_child(trend)
	col.add_child(top)
	var sub := RichTextLabel.new()
	sub.fit_content = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_font_override("normal_font", Brand.FONT_BODY)
	sub.add_theme_font_size_override("normal_font_size", _px(1.5))
	sub.add_theme_color_override("default_color", Brand.CREAM_MUTED)
	sub.add_text("+%s energy" % _bars(int(m.energy)))
	if bool(m.get("free", false)):
		sub.add_text(" · once a day, on the town")
	elif int(m.energy) > 0:
		sub.add_text(" · ")
		sub.push_color(BEST if best else Brand.CREAM)
		sub.add_text("%s per energy bar" % Usdc.text(roundi(_per(m))))
		sub.pop()
	col.add_child(sub)
	row.add_child(col)
	return row

func _draw_pips() -> void:
	var w := R * 2.8
	var h := R * 1.6
	var gap := R * 0.6
	_box.set_corner_radius_all(int(R * 0.4))
	for k in 5:
		var at := Rect2(k * (w + gap), 0.0, w, h)
		var a := clampf(_now / float(BAR) - k, 0.0, 1.0)
		var b := clampf(_after / float(BAR) - k, 0.0, 1.0)
		if b > a: _paint(at.grow(R * 0.2), Brand.CREAM)
		_paint(at, Color("262727"))
		_paint(at, OFF)
		if b > 0.0: _paint(Rect2(at.position, Vector2(w * b, h)), GAIN)
		if a > 0.0: _paint(Rect2(at.position, Vector2(w * a, h)), Brand.GREEN)

func _paint(at: Rect2, colour: Color) -> void:
	_box.bg_color = colour
	_pips.draw_style_box(_box, at)

func _firsts() -> Dictionary:
	var had := {}
	for f in client.you.get("firsts", []): had[str(f.first)] = true
	return had

static func _label(m: Dictionary) -> String:
	if bool(m.get("free", false)): return "Community thali"
	return str(FoodCounter.LABELS.get(m.name, str(m.name).capitalize()))

## USDC base units for one pip of energy.
static func _per(m: Dictionary) -> float:
	return INF if int(m.energy) <= 0 or bool(m.get("free", false)) else float(int(m.price)) * BAR / int(m.energy)

static func _bars(energy: int) -> String:
	return _num(energy / float(BAR))

static func _num(x: float) -> String:
	return ("%.1f" % x).trim_suffix(".0")

## Bitroad has no arrows, so the board's ↑ and ↓ are drawn, centred on c.
static func _arrow_on(c: Control, up: bool, colour: Color, tall: float) -> void:
	c.draw.connect(func():
		var mid := c.size * 0.5
		var tip := mid + Vector2(0.0, tall * (-0.5 if up else 0.5))
		var w := maxf(1.5, tall * 0.13)
		var back := tall * (0.38 if up else -0.38)
		c.draw_line(mid * 2.0 - tip, tip, colour, w, true)
		c.draw_polyline(PackedVector2Array([tip + Vector2(-absf(back), back), tip, tip + Vector2(absf(back), back)]), colour, w, true))

static func _px(rem: float) -> int:
	return roundi(rem * R)

static func _text(t: String, font: Font, rem: float, colour := Brand.CREAM) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", _px(rem))
	l.add_theme_color_override("font_color", colour)
	return l

static func _eyebrow(t: String) -> Label:
	var spaced := FontVariation.new()
	spaced.base_font = Brand.FONT_DISPLAY
	spaced.spacing_glyph = roundi(0.12 * 1.4 * R)
	var l := _text(t, spaced, 1.4)
	l.modulate.a = 0.75
	return l

## A key as the board draws it: cream with a darker lip, or on the pill, dark with no lip.
static func _key(t: String, dark := false) -> Label:
	var l := _text("" if t in ["↑", "↓"] else t, Brand.FONT_DISPLAY, 1.4, Brand.CREAM if dark else Brand.PLATE)
	if t in ["↑", "↓"]: _arrow_on(l, t == "↑", Brand.PLATE, R * 1.2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(R * 2.8, R * 2.8)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cap := StyleBoxFlat.new()
	cap.bg_color = Brand.PLATE if dark else Brand.CREAM
	cap.set_corner_radius_all(int(R * 0.8))
	cap.content_margin_left = R * 0.8
	cap.content_margin_right = R * 0.8
	if not dark:
		cap.border_color = KeyHint.CAP_EDGE
		cap.border_width_bottom = int(R * 0.3)
		cap.expand_margin_bottom = R * 0.3
	l.add_theme_stylebox_override("normal", cap)
	return l

func _stack(gap_rem: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(R * gap_rem))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

## A column hung from the top: from the left edge, or (left_rem below 0) from the right.
func _column(left_rem: float, width_rem: float, gap_rem: float) -> VBoxContainer:
	var v := _stack(gap_rem)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	var from_right := left_rem < 0.0
	v.anchor_left = 1.0 if from_right else 0.0
	v.anchor_right = v.anchor_left
	v.offset_left = R * left_rem
	v.offset_right = R * (left_rem + width_rem)
	v.offset_top = R * 5.6
	add_child(v)
	return v
