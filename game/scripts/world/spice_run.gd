class_name SpiceRun
extends Node3D
## The flagship sponsored quest's two stops past the harbourmaster (quests.toml, spice_run): the exchange kiosk on the landing, where the
## cargo money is swapped for the sponsor's spice on Uniswap from the player's own wallet (Swap), and the Spice Merchant's kiosk in the
## Market Hall (spice-merchant.tallyport.eth), where it's delivered (Deliver) and the quest pays. Both are real transactions: a pending
## stamp shows from QuestStepSent until the chain says QuestStepDone, or QuestStepFailed with why.
## The exchange is in the world (ux12): Uniswap's live quote on a board over the kiosk (ExchangeBoard), the camera up to it, hold E to pull
## the lever. It reads Uniswap's quote off the swap step (PROTOCOL.md, The exchange kiosk): what the cargo buys, the pool's fee, the slippage
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
var sheet := ExchangeBoard.new()   # the quote board over the kiosk, and its keys while you're at it
var director: Director
var _swap_quest := ""              # the quest the sheet is swapping for
var _wallet_before = null          # the wallet's USDC when the sheet opened: the server's number, shown beside the new one after
var _swapped := {}                 # the quote the swap was made on, once it's done: shown against what the wallet paid
var _tick := 0.0
var _look_again := false           # the last quote went stale: the new one is to be read before swapping

## keeper_at, merchant_at: where each stands, by their kiosk, facing out.
func setup(ui: Control, keeper_at: Transform3D, merchant_at: Transform3D, exchange_at: Transform3D) -> void:
	keeper = TownNpc.new()
	keeper.player = player
	add_child(keeper)
	keeper.setup("The exchange", KEEPER_LOOK, ui)
	keeper.offers = "swaps on Uniswap"
	keeper.global_transform = keeper_at
	merchant = TownNpc.new()
	merchant.player = player
	add_child(merchant)
	merchant.setup("The Spice Merchant", MERCHANT_LOOK, ui)
	merchant.offers = "buys MANGO"
	merchant.global_transform = merchant_at
	sheet.player = player
	sheet.director = director
	add_child(sheet)
	sheet.setup(exchange_at, "Uniswap v4")
	_fill()
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
	var q: Dictionary = p[0]
	sheet.set_card(str(q.get("title", "the spice run")).to_lower(), "step %d of %d · %s" % [TownState.steps_done(q) + 1, q.get("steps", []).size(), TownState.step_says(q, p[1])])
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
	var chain := str(client.city.get("chain", "offline"))
	sheet._chain.text = "Uniswap v4 · Sepolia" if chain == "sepolia" else ("Uniswap v4 · this town's chain" if chain == "anvil" else "Uniswap · a rehearsal pool")
	var p := _open("swap")
	var step: Dictionary = _step() if _swap_quest != "" else (p[1] if not p.is_empty() else {})
	var q = step.get("quote")
	if not q is Dictionary:
		var idle := "Take the Spice Run at the board: swap here" if p.is_empty() else "E at the counter: a quote from the pool"
		sheet.show_quote([["Uniswap: a pool of two tokens sets the price,", ""], ["and anyone can swap. Here: USDC for MANGO.", ""], ["", ""], ["", ""]], idle)
		return
	var sym := str(q.get("symbol", TOKEN))
	var dec := int(q.get("decimals", 18))
	var left := quote_left_ms(step)
	var rows := [["You pay", Usdc.text(int(q.get("usdc_in", 0)))],
		["You get, about", "%s %s" % [TokenAmount.about(str(q.amount_out), dec), sym]],
		["The pool keeps", "%s fee" % TokenAmount.fee(q.get("fee_bps", 0))],
		["The least you'll take", "%s · %s slippage" % [TokenAmount.at_least(str(q.min_out), dec), TokenAmount.bps(q.get("slippage_bps", 0))]]]
	var again := requote_in_ms(step)
	var clock := ("quote good for %s · " % TownState.clock(left) if left > 0 else "too old to swap on · ") + ("Q for a new one" if again == 0 else "a new one in %s" % TownState.clock(again))
	if bool(step.get("waiting", false)):
		sheet.show_quote(rows, "sent: waiting for the chain", "chain")
	elif bool(step.get("done", false)) or _swapped.has("received"):
		var got := TokenAmount.about(str(_swapped.get("received", _swapped.get("amount_out", "0"))), dec)
		sheet.show_quote(rows, "swapped: take it to the Spice Merchant", "done", "SWAPPED · %s %s" % [got, sym])
	else:
		sheet.show_quote(rows, clock)

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
