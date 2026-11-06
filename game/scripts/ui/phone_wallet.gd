class_name PhoneWallet
extends PhonePage
## Your wallet: its address, its USDC as the chain last said, your name (sam.tallyport.eth), your Town Pass (and the way to get it), meal
## vouchers, what the town owes you and why it's waiting, and this session's money that moved, each with a link to the chain's explorer
## (city.chain). A rehearsal town (offline) has no chain: it says so, and links nothing.

const WAITING := {"town_pass": "waiting for your Town Pass", "budget": "the town's budget is spent today: it's paid tomorrow", "chain": "the chain refused it: tried again tomorrow"}
const WHAT := {"meal": "A meal", "weekly draw": "The weekly draw"}

var town_pass := Callable()        # asks for a Town Pass link (TownPassDesk.ask)

func refresh() -> void:
	clear_page()
	add_theme_constant_override("separation", 10)
	var you := client.you
	var chain := str(client.city.get("chain", "offline"))
	add_child(words("Your wallet", 22))
	var usdc = you.get("usdc")
	add_child(words(Usdc.text(int(usdc)) if usdc != null else "Your wallet is on its way from the chain", 26 if usdc != null else 15, Brand.CREAM))
	if chain == "offline":
		add_child(words("A rehearsal town: no chain, and this is rehearsal money.", 13, Brand.ORANGE))
	else:
		add_child(words("On %s." % chain.capitalize(), 13, MUTED))
	var wallet = you.get("wallet")
	if wallet != null:
		add_child(_link_line("Address", TownState.short_address(wallet), TownState.address_link(chain, wallet)))
	add_child(_fact("Name", str(you.ens) if you.get("ens") != null else "comes with the Town Pass"))
	if str(you.get("sign", "")) != "": add_child(_fact("Shop sign", str(you.sign)))
	add_child(_fact("Meal vouchers", str(int(you.get("vouchers", 0)))))
	add_child(_pass(you))
	var pending: Array = you.get("pending_rewards", [])
	if not pending.is_empty():
		add_child(words("Owed to you", 16))
		for p in pending:
			var r := row()
			var c := VBoxContainer.new()
			c.add_child(_fact(str(p.get("why", "")).capitalize(), Usdc.text(int(p.get("amount", 0)))))
			c.add_child(words(WAITING.get(str(p.get("waiting", "")), "waiting"), 12, MUTED))
			r.add_child(c)
			add_child(r)
	add_child(words("Recent", 16))
	if client.payments.is_empty():
		add_child(words("Nothing has moved yet this session.", 13, MUTED))
	for p in client.payments:
		var link := TownState.tx_link(chain, p.get("tx"))
		var what: String = WHAT.get(str(p.what), str(p.what).capitalize())
		if str(p.what) == "meal": what = str(FoodCounter.LABELS.get(str(p.get("item", "")), "A meal"))
		var amount := int(p.usdc)
		add_child(_link_line(what, ("+" if amount > 0 else "") + Usdc.text(amount), link))

func _pass(you: Dictionary) -> Control:
	var r := row()
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 6)
	if bool(you.get("human", false)):
		c.add_child(words("Town Pass: yours. The town can pay you.", 14, Brand.MINT))
	else:
		c.add_child(words("No Town Pass yet. It proves you're one real person (World ID), and the town pays nothing without it.", 13, Brand.CREAM))
		var b := chip("Get my Town Pass")
		b.pressed.connect(func(): if town_pass.is_valid(): town_pass.call())
		c.add_child(b)
	r.add_child(c)
	return r

func _fact(what: String, value: String) -> Control:
	var line := HBoxContainer.new()
	var label := words(what, 14, MUTED, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	line.add_child(words(value, 14, Brand.CREAM, false))
	return line

## A line whose value opens the explorer, when there's one to open.
func _link_line(what: String, value: String, url: String) -> Control:
	var line := HBoxContainer.new()
	var label := words(what, 14, MUTED, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	if url == "":
		line.add_child(words(value, 14, Brand.CREAM, false))
	else:
		var b := LinkButton.new()
		b.text = value + " · view"
		b.add_theme_font_override("font", Brand.FONT_BODY)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Color("9fd3ff"))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): OS.shell_open(url))
		line.add_child(b)
	return line
