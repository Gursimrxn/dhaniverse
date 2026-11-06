class_name SpiceRun
extends Node3D
## The flagship sponsored quest's two stops past the harbourmaster (quests.toml, spice_run): the exchange kiosk on the landing, where the
## cargo money is swapped for the sponsor's spice on Uniswap from the player's own wallet (Swap), and the Spice Merchant's kiosk in the
## Market Hall (spice-merchant.tallyport.eth), where it's delivered (Deliver) and the quest pays. Both are real transactions: a pending
## stamp shows from QuestStepSent until the chain says QuestStepDone, or QuestStepFailed with why.
## The kiosk reads Uniswap's quote off the swap step (PROTOCOL.md, The exchange kiosk): what the cargo buys, the pool's fee, the slippage
## limit and the least the swap will take, and how long the quote stays good. Q asks for a new one (QuoteSwap), no oftener than the
## server allows; a swap on an old quote is refused (QuoteStale), so the kiosk asks again and the player looks before swapping.

const TOKEN := "MANGO"             # the sponsor's spice, until a quote names it (quote.symbol)
const KEEPER_LOOK := {"top": "0f8f88", "tee": "e8e2d4", "skin": "8a5a3c", "hair": "1d1a18", "bottom": "2a2a30", "shoes": "2a2a30", "open_top": true, "tall": 0.97}
const MERCHANT_LOOK := {"top": "b8473b", "tee": "f2c14e", "skin": "7a4a2e", "hair": "d8d8d8", "bottom": "3b3a4a", "shoes": "4b3a2c", "open_top": true, "tall": 1.04, "wide": 1.15, "beard": true, "cap": true, "hat": "f2c14e"}
const TICK := 0.5                  # s between redraws of the quote's clock

var client: TownClient
var player: CharacterBody3D
var tell := Callable()
var keeper: TownNpc
var merchant: TownNpc
var sheet := BoardSheet.new(780.0, "Swap")
var _swap_quest := ""              # the quest the sheet is swapping for
var _wallet_before = null          # the wallet's USDC when the sheet opened: the server's number, shown beside the new one after
var _swapped := {}                 # the quote the swap was made on, once it's done: shown against what the wallet paid
var _requote: PaperSheet.Pill
var _tick := 0.0
var _look_again := false           # the last quote went stale: the new one is to be read before swapping

## keeper_at, merchant_at: where each stands, by their kiosk, facing out.
func setup(ui: Control, keeper_at: Transform3D, merchant_at: Transform3D) -> void:
	keeper = TownNpc.new()
	keeper.player = player
	add_child(keeper)
	keeper.setup("The exchange", KEEPER_LOOK, ui)
	keeper.global_transform = keeper_at
	merchant = TownNpc.new()
	merchant.player = player
	add_child(merchant)
	merchant.setup("The Spice Merchant", MERCHANT_LOOK, ui)
	merchant.global_transform = merchant_at
	sheet.player = player
	ui.add_child(sheet)
	_requote = sheet.add_key(KEY_Q, "Q", "Get a new quote")
	sheet.key_pressed.connect(func(_k): ask_quote())
	sheet.chosen.connect(func(_i): _swap())
	client.event.connect(_on_event)
	client.you_changed.connect(func(): if sheet.is_open: _fill())
	client.refused.connect(_on_refused)

## The quest and its open step of this kind, if any: [quest, step].
func _open(kind: String) -> Array:
	for q in client.you.get("quests", []):
		for s in TownState.open_steps(q):
			if str(s.get("kind", "")) == kind: return [q, s]
	return []

func swap_hint() -> String:
	var p := _open("swap")
	if p.is_empty(): return ""
	return "Swapping on chain…" if bool(p[1].get("waiting", false)) else "Swap for the sponsor's spice"

func deliver_hint() -> String:
	var p := _open("deliver")
	if p.is_empty():
		return "Bring the spice: swap at the exchange first" if not _open("swap").is_empty() else ""
	return "Delivering on chain…" if bool(p[1].get("waiting", false)) else "Deliver the spice"

func open_swap() -> void:
	var p := _open("swap")
	if p.is_empty() or bool(p[1].get("waiting", false)): return
	keeper.greet()
	_swap_quest = str(p[0].quest)
	_wallet_before = client.you.get("usdc")
	_swapped = {}
	sheet.pick = 0
	_fill()
	sheet.open()
	if quote_left_ms(_step()) == 0: ask_quote()          # none yet, or an old one: a fresh one as the kiosk opens

## The swap step of the quest the sheet is for, as the server last said it.
func _step() -> Dictionary:
	for s in TownState.quest(client.you, _swap_quest).get("steps", []):
		if str(s.get("kind", "")) == "swap": return s
	return {}

## ms the step's quote stays good for (0: none, or too old to swap on).
func quote_left_ms(step: Dictionary) -> int:
	var q = step.get("quote")
	return TownState.left_ms(q.get("fresh_until"), client.now_ms()) if q is Dictionary else 0

## ms until the server takes another QuoteSwap.
func requote_in_ms(step: Dictionary) -> int:
	return TownState.left_ms(step.get("quote_ready_at"), client.now_ms())

## Q, or the kiosk opening on an old quote: ask Uniswap again, when the server allows.
func ask_quote() -> void:
	if not sheet.is_open or _swap_quest == "": return
	var step := _step()
	if step.is_empty() or bool(step.get("done", false)) or bool(step.get("waiting", false)): return
	var wait := requote_in_ms(step)
	if wait > 0:
		sheet.say("A new quote %s." % TownState.soon(wait), false)
		return
	client.send({"type": "QuoteSwap", "quest": _swap_quest})
	sheet.say("Asking the pool for a quote…", false)

func _process(delta: float) -> void:
	if not sheet.is_open: return
	_tick -= delta
	if _tick > 0.0: return
	_tick = TICK
	_fill()

## The quote in words, then each figure on its own line. Everything is the server's: amounts are only formatted.
static func quote_words(q: Dictionary) -> String:
	var sym := str(q.get("symbol", TOKEN))
	var dec := int(q.get("decimals", 18))
	return "%s buys about %s %s. The pool keeps %s. If the price moves, you'll still get at least %s %s, or the swap won't happen." % [
		Usdc.text(int(q.get("usdc_in", 0))), TokenAmount.about(str(q.get("amount_out", "0")), dec), sym, TokenAmount.fee(q.get("fee_bps", 0)),
		TokenAmount.at_least(str(q.get("min_out", "0")), dec), sym]

func _fill() -> void:
	var step := _step()
	var you := client.you
	var wallet := TownState.short_address(you.get("wallet"))
	var usdc = you.get("usdc")
	var q = step.get("quote")
	var done := bool(step.get("done", false)) or not _swapped.is_empty()
	var waiting := bool(step.get("waiting", false))
	var offline := str(client.city.get("chain", "offline")) == "offline"
	var rows := []
	var intro := ""
	if q is Dictionary:
		var sym := str(q.get("symbol", TOKEN))
		var dec := int(q.get("decimals", 18))
		intro = quote_words(q)
		var left := quote_left_ms(step)
		rows.append({"title": "You pay", "sub": "the cargo money, from your wallet %s" % wallet, "figure": Usdc.text(int(q.get("usdc_in", 0)))})
		rows.append({"title": "You get about", "sub": "%s, the sponsor's spice, at the pool's price now" % sym, "figure": "%s %s" % [TokenAmount.about(str(q.amount_out), dec), sym]})
		rows.append({"title": "The pool's fee", "sub": "the Uniswap pool keeps this share of what goes through it", "figure": TokenAmount.fee(q.get("fee_bps", 0))})
		rows.append({"title": "The least you'll take", "sub": "the swap may fill up to %s under the quote if the price moves, and no further" % TokenAmount.bps(q.get("slippage_bps", 0)),
			"figure": "%s %s" % [TokenAmount.at_least(str(q.min_out), dec), sym], "figure_sub": "at least"})
		if not done:
			rows.append({"title": "This quote", "sub": ("good for a swap for another %s" % TownState.clock(left)) if left > 0 else "is too old to swap on: Q gets a new one",
				"figure": TownState.clock(left), "figure_sub": "left", "dim": left == 0})
	else:
		intro = "The pool is being asked what the cargo money buys. The quote shows here in a moment."
	if done and not _swapped.is_empty():
		var dec2 := int(_swapped.get("decimals", 18))
		var sym2 := str(_swapped.get("symbol", TOKEN))
		var moved := (" Your wallet went from %s to %s." % [Usdc.text(int(_wallet_before)), Usdc.text(int(usdc))]) if _wallet_before != null and usdc != null and int(_wallet_before) != int(usdc) else ""
		if _swapped.has("received"):      # the chain said what arrived: show it against the quote
			rows.append({"title": "Swapped", "sub": "the quote said about %s %s, at least %s %s.%s" % [TokenAmount.about(str(_swapped.amount_out), dec2), sym2,
				TokenAmount.at_least(str(_swapped.min_out), dec2), sym2, moved], "figure": "%s %s" % [TokenAmount.about(str(_swapped.received), dec2), sym2], "figure_sub": "received"})
		else:
			rows.append({"title": "Swapped", "sub": "on the quote of about %s %s: the chain guaranteed at least %s %s.%s" % [TokenAmount.about(str(_swapped.amount_out), dec2), sym2,
				TokenAmount.at_least(str(_swapped.min_out), dec2), sym2, moved], "figure": "%s %s" % [TokenAmount.at_least(str(_swapped.min_out), dec2), sym2], "figure_sub": "at least, received"})
		sheet.pick = rows.size() - 1
	rows.append({"title": "Your wallet", "sub": "as the chain last said" + (", before this swap %s" % Usdc.text(int(_wallet_before)) if _wallet_before != null and usdc != null and int(_wallet_before) != int(usdc) else ""),
		"figure": Usdc.text(int(usdc)) if usdc != null else "—"})
	if offline: intro += " This town is a rehearsal: no chain, and the money is a rehearsal too."
	sheet.set_words("The landing · the exchange", "Swap the cargo money for %s" % (str(q.get("symbol", TOKEN)) if q is Dictionary else TOKEN), intro)
	sheet.set_rows(rows)
	var fresh := q is Dictionary and quote_left_ms(step) > 0
	sheet.set_go("" if waiting or done or step.is_empty() or not (q is Dictionary) else ("Swap" if fresh else "Swap (asks for a new quote first)"))
	var again := requote_in_ms(step)
	_requote.visible = not done and not waiting and not step.is_empty()
	BoardSheet.pill_words(_requote, "Get a new quote" if again == 0 else "New quote in %s" % TownState.clock(again))
	_requote.modulate.a = 1.0 if again == 0 else 0.45

func _swap() -> void:
	if _swap_quest == "": return
	var p := _open("swap")
	if p.is_empty() or str(p[0].quest) != _swap_quest or bool(p[1].get("waiting", false)): return
	if quote_left_ms(p[1]) == 0:      # an old quote: never swap on it; a new one first, and a look at it
		ask_quote()
		_look_again = true
		sheet.say("That quote was too old to swap on. A new one is coming: look at it again before you swap.")
		return
	_swapped = (p[1].quote as Dictionary).duplicate()
	client.send({"type": "Swap", "quest": _swap_quest})
	sheet.say("Sending the swap…", false)

func deliver() -> void:
	var p := _open("deliver")
	if p.is_empty():
		if not _open("swap").is_empty() and tell.is_valid(): tell.call("The Spice Merchant: \"No spice, no deal. The exchange on the landing sells it.\"")
		return
	if bool(p[1].get("waiting", false)): return
	merchant.greet()
	client.send({"type": "Deliver", "quest": str(p[0].quest)})

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"SwapQuoted":
			if sheet.is_open and str(e.get("quest", "")) == _swap_quest:
				_fill()
				sheet.say("A new quote. Look it over, then swap." if _look_again else "A new quote: %s" % quote_words(e), false)
				_look_again = false
		"QuoteFailed":
			if sheet.is_open and str(e.get("quest", "")) == _swap_quest:
				sheet.say("The pool couldn't quote: %s Press Q to ask again." % Refusals.reason(e.get("reason")))
		"QuestStepSent":
			if str(e.step) == "swap" and sheet.is_open: sheet.say("Sent to the chain. Swapping…", false)
			if str(e.step) == "deliver" and tell.is_valid(): tell.call("The Spice Merchant weighs it out. Waiting for the chain…")
		"QuestSwapped":
			if str(e.get("quest", "")) == _swap_quest and not _swapped.is_empty():
				_swapped["received"] = str(e.get("received", "0"))
		"QuestStepDone":
			if str(e.step) == "swap":
				if sheet.is_open:
					_fill()
					sheet.say("Swapped. Take the spice to the Spice Merchant in the Market Hall.", false)
					get_tree().create_timer(4.0).timeout.connect(sheet.close)
				elif tell.is_valid(): tell.call("Swapped. Take the spice to the Spice Merchant in the Market Hall.")
		"QuestStepFailed":
			if str(e.step) == "swap":
				_swapped = {}
				if sheet.is_open:
					sheet.say(Refusals.reason(e.get("reason")) + " Try again when you're ready.")
					_fill()
				elif tell.is_valid(): tell.call(Refusals.reason(e.get("reason")))
			elif str(e.step) == "deliver" and tell.is_valid(): tell.call(Refusals.reason(e.get("reason")))

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	match str(command.get("type", "")):
		"Swap":
			_swapped = {}
			if not sheet.is_open: return
			if str(refusal.get("type", "")) == "QuoteStale":
				ask_quote()
				_look_again = true
				sheet.say("That quote went stale before the swap. A new one is coming: look at it again before you swap.")
			else: sheet.say(Refusals.say(refusal, client.now_ms()))
		"QuoteSwap": if sheet.is_open: sheet.say(Refusals.say(refusal, client.now_ms()), str(refusal.get("type", "")) != "QuoteTooSoon")
		"Deliver": if tell.is_valid(): tell.call(Refusals.say(refusal, client.now_ms()))
