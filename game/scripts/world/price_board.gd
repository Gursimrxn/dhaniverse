class_name PriceBoard
extends Node3D
## The Price Call board in the square: a chalkboard with today's food price and three slots, up, flat and down. Before the city day closes,
## call where tomorrow's price goes (PriceCall); it settles when the next city day opens (PriceCallSettled), and a right call earns
## tickets for the weekly draw. Your call is chalked on the board. The price and the result are the server's.

const SIZE := Vector2(2.0, 1.3)
const FEET := 0.8
const CALLS := ["up", "flat", "down"]
const CALL_WORDS := {"up": "Up", "flat": "Flat", "down": "Down"}

var client: TownClient
var player: CharacterBody3D
var sheet := BoardSheet.new(640.0, "Call it")
var _price: Label3D
var _call: Label3D
var _slots := {}                   # call -> Label3D

func setup(ui: Control) -> void:
	_build()
	sheet.player = player
	ui.add_child(sheet)
	sheet.chosen.connect(_call_it)
	client.city_changed.connect(_chalk)
	client.you_changed.connect(_chalk)
	client.synced.connect(_chalk)
	client.refused.connect(func(command: Dictionary, refusal: Dictionary):
		if command.get("type") == "PriceCall" and sheet.is_open: sheet.say(Refusals.say(refusal, client.now_ms())))
	client.replied.connect(func(command: Dictionary, _reply: Dictionary):
		if command.get("type") != "PriceCall" or not sheet.is_open: return
		sheet.say("Called: %s. It settles when the next city day opens." % str(CALL_WORDS.get(command.call, command.call)).to_lower(), false)
		_fill()
		get_tree().create_timer(1.6).timeout.connect(sheet.close))

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Brand.TIMBER
	var slate := StandardMaterial3D.new()
	slate.albedo_color = Color("22323d")
	slate.roughness = 0.9
	for x in [-SIZE.x * 0.5 + 0.1, SIZE.x * 0.5 - 0.1]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.08, FEET + SIZE.y, 0.08)
		leg.mesh = lm
		leg.material_override = wood
		leg.position = Vector3(x, (FEET + SIZE.y) * 0.5, -0.05)
		add_child(leg)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE.x, SIZE.y, 0.06)
	board.mesh = bm
	board.material_override = slate
	board.position = Vector3(0, FEET + SIZE.y * 0.5, 0)
	add_child(board)
	var head := _chalk_text("PRICE CALL", Brand.FONT_DISPLAY, 64, Vector3(0, FEET + SIZE.y - 0.16, 0.035))
	head.modulate = Brand.CREAM
	_price = _chalk_text("", Brand.FONT_BODY, 40, Vector3(0, FEET + SIZE.y - 0.4, 0.035))
	for i in CALLS.size():
		_slots[CALLS[i]] = _chalk_text(CALL_WORDS[CALLS[i]], Brand.FONT_DISPLAY, 56, Vector3(-0.6 + i * 0.6, FEET + 0.5, 0.035))
	_call = _chalk_text("", Brand.FONT_BODY, 34, Vector3(0, FEET + 0.17, 0.035))
	var collide := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, FEET + SIZE.y, 0.25)
	cs.shape = box
	cs.position.y = (FEET + SIZE.y) * 0.5
	collide.add_child(cs)
	add_child(collide)

func _chalk_text(t: String, font: Font, size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.font = font
	l.font_size = size
	l.pixel_size = 0.0022
	l.modulate = Color(1, 1, 1, 0.85)
	l.outline_size = 0
	l.position = at
	l.visibility_range_end = 25.0
	add_child(l)
	return l

func _mine() -> String:
	var c = client.you.get("price_call")
	return str(c.get("call", "")) if c is Dictionary else ""

func _chalk() -> void:
	_price.text = "Food today %s" % Usdc.text(int(client.city.get("price", 0)))
	var mine := _mine()
	for c in _slots: (_slots[c] as Label3D).modulate = Color("F0C33A") if c == mine else Color(1, 1, 1, 0.55)
	_call.text = "Your call: %s" % str(CALL_WORDS[mine]).to_lower() if mine != "" else "Call tomorrow's price"
	if sheet.is_open: _fill()

func hint() -> String:
	if client.you.is_empty(): return ""
	return "Call tomorrow's food price" if _mine() == "" else "Your price call"

func open() -> void:
	sheet.pick = 0
	_fill()
	sheet.open()

func _fill() -> void:
	var city := client.city
	var left := int(city.get("day_ms", 0)) - int(city.get("day_elapsed_ms", 0))
	var mine := _mine()
	var open_price := int(city.get("open_price", 0))
	var intro := "Food costs %s now%s. Call where it goes by tomorrow: a move under half a percent is flat. A right call earns tickets for the weekly draw. The city day closes in %s." % [
		Usdc.text(int(city.get("price", 0))), (", from %s at the open" % Usdc.text(open_price)) if open_price > 0 else "", TownState.clock(left)]
	sheet.set_words("Tally Square · Price Call · day %d" % int(city.get("day", 0)), "Up, flat or down?" if mine == "" else "You called it %s." % str(CALL_WORDS[mine]).to_lower(), intro)
	var rows := []
	for c in CALLS:
		rows.append({"title": CALL_WORDS[c], "sub": {"up": "Tomorrow's food costs more", "flat": "Within half a percent of today's", "down": "Tomorrow's food costs less"}[c],
			"badge": "your call" if c == mine else "", "dim": mine != "" and c != mine})
	sheet.set_rows(rows)
	sheet.set_go("Call it" if mine == "" else "")

func _call_it(i: int) -> void:
	if _mine() != "": return
	client.send({"type": "PriceCall", "call": CALLS[i]})
