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

var _mode := ""                    # "", "deposit" or "withdraw": the panel open under the balance
var _to := ""                      # the withdraw form's fields, kept across the page's rebuilds
var _amount := ""
var _status := ""                  # what the last withdrawal is doing, in words
var _status_tone := MUTED
var _listening := false

func refresh() -> void:
	if not _listening:
		_listening = true
		client.event.connect(_on_event)
		client.refused.connect(_on_refused)
	clear_page()
	add_theme_constant_override("separation", 12)
	var you := client.you
	var chain := str(client.city.get("chain", "offline"))
	add_child(_card(you, chain))
	add_child(_balance(you, chain))
	if you.get("wallet") != null: add_child(_moves(you, chain))
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
		add_child(words("Nothing yet this session. Pay, meals, the crate and withdrawals land here as they happen.", 13, MUTED))
	for p in client.payments:
		add_child(_transaction(p, chain))
	var history := TownState.address_link(chain, you.get("wallet"))
	if history != "":     # everything this wallet ever did, on the chain's explorer: opened only on a press
		var all := action("All transactions on the explorer ↗", false)
		all.pressed.connect(func(): OS.shell_open(history))
		add_child(all)

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

## Deposit and Withdraw, the landing's pill pair, and the panel for whichever is open.
func _moves(you: Dictionary, chain: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	var deposit := action("Deposit", _mode == "deposit" or _mode == "")
	var withdraw := action("Withdraw", _mode == "withdraw" or _mode == "")
	deposit.pressed.connect(func(): _open_mode("deposit"))
	withdraw.pressed.connect(func(): _open_mode("withdraw"))
	pair.add_child(deposit)
	pair.add_child(withdraw)
	column.add_child(pair)
	if _mode == "deposit": column.add_child(_deposit(you, chain))
	elif _mode == "withdraw": column.add_child(_withdraw(you, chain))
	return column

func _open_mode(mode: String) -> void:
	_mode = "" if _mode == mode else mode
	refresh()

## Your address to send USDC to, with copy and the explorer. On a rehearsal town there's no chain to send on.
func _deposit(you: Dictionary, chain: String) -> Control:
	var r := row()
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	c.add_child(caps("Deposit USDC" + ("" if chain == "offline" else " on " + chain.capitalize())))
	var address := str(you.wallet)
	var shown := words(address, 12, INK)
	shown.add_theme_font_override("font", Brand.FONT_NUMBER)
	c.add_child(shown)
	if chain == "offline":
		c.add_child(words("This is a rehearsal town: nothing on a chain reaches it. Use the test panel's Fund (F1).", 12, WARN))
	else:
		c.add_child(words("Send USDC on %s to this address from any wallet. It shows here once the chain has it. Test USDC comes free from faucet.circle.com." % chain.capitalize(), 12, MUTED))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var copy := chip("Copy address")
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(address)
		copy.text = "Copied")
	buttons.add_child(copy)
	if chain != "offline":
		var view := chip("Explorer ↗")
		view.pressed.connect(func(): OS.shell_open(TownState.address_link(chain, address)))
		buttons.add_child(view)
	c.add_child(buttons)
	r.add_child(c)
	return r

## Send USDC out: an address, an amount (or all of it), and Send. The server checks both; the chain moves it.
func _withdraw(you: Dictionary, chain: String) -> Control:
	var r := row()
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	c.add_child(caps("Withdraw USDC"))
	var to := _field("0x… the address it goes to", _to)
	to.text_changed.connect(func(t: String): _to = t.strip_edges())
	c.add_child(to)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var amount := _field("Amount in USDC", _amount)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.text_changed.connect(func(t: String): _amount = t.strip_edges())
	line.add_child(amount)
	var most := chip("Max")
	most.pressed.connect(func():
		_amount = Usdc.amount(int(you.get("usdc", 0)))
		amount.text = _amount)
	line.add_child(most)
	c.add_child(line)
	var send := action("Send" + (" rehearsal money" if chain == "offline" else ""))
	send.pressed.connect(_send)
	c.add_child(send)
	if _status != "": c.add_child(words(_status, 12, _status_tone))
	r.add_child(c)
	return r

func _field(hint: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.text = value
	e.add_theme_font_override("font", FONT_REGULAR)
	e.add_theme_font_size_override("font_size", 13)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", MUTED)
	e.add_theme_color_override("caret_color", INK)
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0, 0, 0, 0.04)
	look.border_color = LINE
	look.set_border_width_all(1)
	look.set_corner_radius_all(10)
	look.content_margin_left = 10
	look.content_margin_right = 10
	look.content_margin_top = 8
	look.content_margin_bottom = 8
	e.add_theme_stylebox_override("normal", look)
	var focus := look.duplicate()
	focus.border_color = INK
	e.add_theme_stylebox_override("focus", focus)
	return e

## "1.5" -> 1500000. Anything that isn't a plain amount is 0, which the server refuses in words.
static func _units(text: String) -> int:
	if not text.is_valid_float(): return 0
	return int(round(text.to_float() * Usdc.UNITS))

func _send() -> void:
	_status = "Sending…"
	_status_tone = MUTED
	client.send({"type": "Withdraw", "to": _to, "amount": _units(_amount)})
	refresh()

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.get("type", "")):
		"WithdrawSent":
			_status = "On its way: %s to %s. Waiting for the chain…" % ["$" + Usdc.amount(int(e.amount)), TownState.short_address(e.to)]
			_status_tone = MUTED
		"Withdrawn":
			_status = "Sent: %s landed at %s." % ["$" + Usdc.amount(int(e.amount)), TownState.short_address(e.to)]
			_status_tone = GOOD
			_amount = ""
		"WithdrawFailed":
			_status = "The chain refused it, so nothing left your wallet. (%s)" % str(e.get("reason", ""))
			_status_tone = WARN
		_: return

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") != "Withdraw": return
	_status = Refusals.say(refusal, client.now_ms())
	_status_tone = WARN
	refresh()

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
	if int(p.get("less", 0)) > 0:     # the payout paid back the cargo advance first
		text.add_child(words("%s payout, less your %s advance" % [Usdc.text(int(p.usdc) + int(p.less)), Usdc.text(int(p.less))], 11, MUTED, false))
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
