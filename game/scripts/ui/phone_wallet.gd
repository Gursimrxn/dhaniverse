class_name PhoneWallet
extends PhonePage
## Your wallet, as the landing draws "the bank of Dhaniverse": the card (your address where a card number would be, your name under it),
## the balance, what's held for you and why, your Town Pass, and this session's transactions, each linked to the chain's explorer
## (city.chain). A rehearsal town (offline) has no chain: it says so, and links nothing.

const WAITING := {"town_pass": "waiting for your Town Pass", "budget": "the town's budget is spent today: paid tomorrow", "chain": "the chain refused it: tried again tomorrow"}
const WHAT := {"meal": "A meal", "weekly draw": "The weekly draw"}
const CARD := Vector2(292, 172)
const BLOOM := [Color("FFECBD"), Color("FF6600"), Color("E52EFE"), Color("7079FF"), Color("74BCDE"), Color("A1FFB4")]   # the card's gradient, from the landing's SVG
const LOGO := preload("res://assets/ui/bank/logo.svg")
const MARK := preload("res://assets/ui/bank/mark.svg")

var town_pass := Callable()        # asks for a Town Pass link (TownPassDesk.ask)

func refresh() -> void:
	clear_page()
	add_theme_constant_override("separation", 12)
	var you := client.you
	var chain := str(client.city.get("chain", "offline"))
	add_child(_card(you, chain))
	add_child(_balance(you, chain))
	add_child(_pass(you))
	var pending: Array = you.get("pending_rewards", [])
	if not pending.is_empty():
		add_child(caps("Held for you"))
		for p in pending:
			var r := row()
			var c := VBoxContainer.new()
			c.add_child(_fact(str(p.get("why", "")).capitalize(), "$" + Usdc.amount(int(p.get("amount", 0)))))
			c.add_child(words(WAITING.get(str(p.get("waiting", "")), "waiting"), 12, MUTED))
			r.add_child(c)
			add_child(r)
	add_child(caps("Transactions"))
	if client.payments.is_empty():
		add_child(words("Nothing has moved yet this session.", 13, MUTED))
	for p in client.payments:
		add_child(_transaction(p, chain))

## The landing's bank card: white, the bloom in its corner, light capitals, the address spaced out, the name in Mondwest's stand-in.
func _card(you: Dictionary, chain: String) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = CARD
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var look := StyleBoxFlat.new()
	look.bg_color = Color.WHITE
	look.set_corner_radius_all(24)
	look.shadow_color = Color(0, 0, 0, 0.08)
	look.shadow_size = 10
	look.shadow_offset = Vector2(0, 5)
	card.add_theme_stylebox_override("panel", look)
	for spot in [[Vector2(120, 60), 230.0, 0.55], [Vector2(190, 110), 200.0, 0.7]]:
		var bloom := TextureRect.new()
		bloom.texture = _bloom()
		bloom.position = spot[0]
		bloom.size = Vector2(spot[1], spot[1])
		bloom.modulate.a = spot[2]
		bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bloom)
	var title := caps("The bank of Dhaniverse")
	title.add_theme_font_size_override("font_size", 15)
	title.position = Vector2(20, 18)
	card.add_child(title)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(36, 26)
	logo.position = Vector2(CARD.x - 56, 14)
	card.add_child(logo)
	var wallet = you.get("wallet")
	var number := Label.new()
	number.text = _spaced(TownState.short_address(wallet)) if wallet != null else "· · · ·   · · · ·"
	var spaced := FontVariation.new()
	spaced.base_font = FONT_LIGHT
	spaced.spacing_glyph = 4
	number.add_theme_font_override("font", spaced)
	number.add_theme_font_size_override("font_size", 15)
	number.add_theme_color_override("font_color", Color.BLACK)
	number.position = Vector2(20, 66)
	card.add_child(number)
	var note := Label.new()
	note.text = ("town pass  ✓" if bool(you.get("human", false)) else "no town pass yet") + ("    rehearsal" if chain == "offline" else "    " + chain)
	note.add_theme_font_override("font", FONT_LIGHT)
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color.BLACK)
	note.position = Vector2(20, CARD.y - 56)
	card.add_child(note)
	var name := Label.new()
	name.text = str(you.ens) if you.get("ens") != null else str(you.get("name", client.player))
	name.add_theme_font_override("font", Brand.FONT_DISPLAY)
	name.add_theme_font_size_override("font_size", 15)
	name.add_theme_color_override("font_color", Color.BLACK)
	name.position = Vector2(20, CARD.y - 36)
	card.add_child(name)
	var mark := TextureRect.new()
	mark.texture = MARK
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size = Vector2(22, 22)
	mark.position = Vector2(CARD.x - 42, CARD.y - 38)
	card.add_child(mark)
	if wallet != null and chain != "offline":
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: OS.shell_open(TownState.address_link(chain, wallet)))
	return card

## A soft round bloom in the card's colours, standing in for the landing's blurred gradient.
static func _bloom() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([Color(BLOOM[2], 0.9), Color(BLOOM[3], 0.7), Color(BLOOM[1], 0.35), Color(BLOOM[0], 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

static func _spaced(text: String) -> String:
	return text.replace("…", " · · · ")

func _balance(you: Dictionary, chain: String) -> Control:
	var r := row()
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	c.add_child(caps("Account balance · USDC"))
	var usdc = you.get("usdc")
	var amount := words("$" + Usdc.amount(int(usdc)) if usdc != null else "on its way from the chain", 38 if usdc != null else 15, INK, false)
	c.add_child(amount)
	var held := 0
	for p in you.get("pending_rewards", []): held += int(p.get("amount", 0))
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 6)
	if held > 0: pills.add_child(_pill("held $" + Usdc.amount(held), Color("FFF8E3"), INK))
	if int(you.get("pending", 0)) > 0: pills.add_child(_pill("at the chain", Color("FFF1C2"), Color("6b5200")))
	if chain == "offline": pills.add_child(_pill("rehearsal money", Color("FFE7D6"), WARN))
	if pills.get_child_count() > 0: c.add_child(pills)
	r.add_child(c)
	return r

func _pill(text: String, back: Color, ink: Color) -> Control:
	var p := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = back
	look.set_corner_radius_all(99)
	look.content_margin_left = 9
	look.content_margin_right = 9
	look.content_margin_top = 3
	look.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", look)
	p.add_child(words(text, 11, ink, false))
	return p

func _pass(you: Dictionary) -> Control:
	if bool(you.get("human", false)): return Control.new()
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	c.add_child(words("No Town Pass yet. It proves you're one real person with World ID, and the town pays nothing without it.", 13, MUTED))
	var b := action("Get my Town Pass")
	b.pressed.connect(func(): if town_pass.is_valid(): town_pass.call())
	c.add_child(b)
	return c

func _transaction(p: Dictionary, chain: String) -> Control:
	var r := row()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var what: String = WHAT.get(str(p.what), str(p.what).capitalize())
	if str(p.what) == "meal": what = str(FoodCounter.LABELS.get(str(p.get("item", "")), "A meal"))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(words(what, 14, INK, false))
	var link := TownState.tx_link(chain, p.get("tx"))
	if link != "":
		var b := LinkButton.new()
		b.text = "view on the explorer ↗"
		b.add_theme_font_override("font", FONT_REGULAR)
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", MUTED)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): OS.shell_open(link))
		text.add_child(b)
	line.add_child(text)
	var amount := int(p.usdc)
	line.add_child(words(("+" if amount > 0 else "−") + "$" + Usdc.amount(absi(amount)), 15, GOOD if amount > 0 else INK, false))
	r.add_child(line)
	return r

func _fact(what: String, value: String) -> Control:
	var line := HBoxContainer.new()
	var label := words(what, 14, MUTED, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	line.add_child(words(value, 14, INK, false))
	return line
