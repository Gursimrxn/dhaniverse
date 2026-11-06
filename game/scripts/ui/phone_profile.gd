class_name PhoneProfile
extends PhonePage
## Your card, as anyone can see it (PROTOCOL.md, profiles): your name and the ENS name it's written on, your title and the titles and
## stamps you've earned (stamps are written on your name too), your shop sign, your reputation and days in town, your best run, and the
## firsts you've earned. Nothing here says what anyone paid or holds.

const STAMP_WORDS := {"spice-run": "Spice Run", "grandmas-ledger": "Grandma's Ledger", "steady-hand": "Hold the Line", "town-pass": "Town Pass", "sign": "Shop sign"}

var _card := {}                    # the server's public card for you, asked for when the page opens
var _asked := -INF

func listen() -> void:
	client.profiled.connect(func(card: Dictionary):
		if str(card.get("name", "")) != client.player: return
		_card = card
		if is_visible_in_tree(): _draw_page())

func refresh() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t - _asked > 10.0:
		_asked = t
		client.ask_profile(client.player)
	_draw_page()

func _draw_page() -> void:
	clear_page()
	add_theme_constant_override("separation", 10)
	var you := client.you
	add_child(words(str(you.get("name", "")), 30))
	if you.get("ens") != null: add_child(words(str(you.ens), 14, Brand.MAGENTA))
	if str(you.get("title", "")) != "": add_child(words(str(you.title), 16, MUTED))
	if str(you.get("sign", "")) != "": add_child(words("\"%s\"" % str(you.sign), 15, Brand.CREAM))
	add_child(_fact("Reputation", str(_card.get("reputation", "New in town"))))
	add_child(_fact("Days in town", str(int(_card.get("days_active", 0)))))
	add_child(_fact("Best Market Rush", str(int(you.get("best_run", 0)))))
	add_child(_fact("Town Pass", "yes" if bool(you.get("human", false)) else "not yet"))
	add_child(_chips("Titles", you.get("titles", []), {}))
	add_child(_chips("Stamps", you.get("stamps", []), STAMP_WORDS))
	var firsts: Array = you.get("firsts", [])
	add_child(words("Firsts: %d of %d" % [firsts.size(), MilestoneBlast.FIRSTS.size()], 14, MUTED))
	var names := HFlowContainer.new()
	names.add_theme_constant_override("h_separation", 5)
	names.add_theme_constant_override("v_separation", 5)
	names.custom_minimum_size.x = WIDTH
	for f in firsts:
		var c := chip(str(MilestoneBlast.FIRSTS.get(f.first, [f.first])[0]))
		c.disabled = true
		names.add_child(c)
	add_child(names)

func _chips(what: String, items: Array, names_of: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.add_child(words("%s: %d" % [what, items.size()], 14, MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	flow.custom_minimum_size.x = WIDTH
	for it in items:
		var c := chip(str(names_of.get(str(it), str(it).capitalize().replace("-", " "))), true)
		c.disabled = true
		flow.add_child(c)
	if items.is_empty(): flow.add_child(words("None yet: quests earn them.", 13, MUTED, false))
	column.add_child(flow)
	return column

func _fact(what: String, value: String) -> Control:
	var line := HBoxContainer.new()
	var label := words(what, 15, MUTED, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	line.add_child(words(value, 15, Brand.CREAM, false))
	return line
