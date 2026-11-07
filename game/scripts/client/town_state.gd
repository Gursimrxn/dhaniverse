class_name TownState
## Reading what the server last said (`you` and `city`, PROTOCOL.md v3) the way every part of the client needs it: how long until
## something is ready on the real clock, which step of a quest is next and what does it, which campaigns are on the Bounty Board, where
## a transaction can be looked at. Nothing here works out a price, an amount or a reward: it only reads the server's numbers.

## How a step gets done (PROTOCOL.md, Quests): the client reports it, or a command of its own does, or the chain or the server does it.
const BY_STEP := {"talk": "step", "visit": "step", "paper": "step", "strongbox": "step", "cargo": "step",
	"swap": "swap", "deliver": "deliver", "sign": "sign", "verify": "verify", "hold": "", "meals": ""}
const TIERS := ["wood", "brass", "gold"]
## Where a transaction can be looked at, by city.chain. Offline is a rehearsal and anvil a chain on this machine: nothing to link to.
const EXPLORERS := {"sepolia": "https://sepolia.etherscan.io"}

## ms until a moment on the real clock: 0 when it's null, 0 or past (PROTOCOL.md: "0 or past means ready").
static func left_ms(at, now: int) -> int:
	if at == null: return 0
	var t := int(at)
	return 0 if t <= 0 else maxi(t - now, 0)

## A wait as a clock: 59 s -> "0:59", 5 min -> "5:00", 3 h -> "3:00:00". Under a second reads "0:00".
static func clock(ms: int) -> String:
	var s := ceili(maxi(ms, 0) / 1000.0)
	if s >= 3600: return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

## A longer wait in plain words: "in 4 h", "in 12 min", "in 40 s".
static func soon(ms: int) -> String:
	var s := ceili(maxi(ms, 0) / 1000.0)
	if s >= 172800: return "in %d days" % roundi(s / 86400.0)
	if s >= 3600: return "in %d h" % roundi(s / 3600.0)
	if s >= 90: return "in %d min" % roundi(s / 60.0)
	return "in %d s" % s

static func chest_ready(you: Dictionary, now: int) -> bool:
	var chest: Dictionary = you.get("chest", {})
	return not chest.is_empty() and left_ms(chest.get("ready_at"), now) == 0

## The weekly chest: come on enough of the last 7 days, and not opened this week.
static func weekly_ready(you: Dictionary, now: int) -> bool:
	var streak: Dictionary = you.get("streak", {})
	var chest: Dictionary = you.get("chest", {})
	if streak.is_empty() or chest.is_empty(): return false
	return int(streak.get("week_days", 0)) >= int(streak.get("need", 5)) and left_ms(chest.get("weekly_ready_at"), now) == 0

static func free_meal_ready(you: Dictionary, now: int) -> bool:
	return you.has("free_meal_at") and left_ms(you.get("free_meal_at"), now) == 0

## ms left in the Rush run under way, 0 for none.
static func rush_left(you: Dictionary, now: int) -> int:
	if not bool(you.get("in_rush", false)): return 0
	return left_ms(you.get("rush_ends_at"), now)

static func quest(you: Dictionary, id: String) -> Dictionary:
	for q in you.get("quests", []):
		if str(q.get("quest", "")) == id: return q
	return {}

## A quest's template, for a sponsored one ("spice_run"...), or "".
static func template(q: Dictionary) -> String:
	var kind = q.get("kind", {})
	return str(kind.get("template", "")) if kind is Dictionary else ""

## The steps that may be done now: the first undone, in order; with any_order (Grandma's pages) every undone one, and the strongbox
## only once the rest are done.
static func open_steps(q: Dictionary) -> Array:
	var undone: Array = q.get("steps", []).filter(func(s): return not bool(s.get("done", false)))
	if undone.is_empty(): return []
	if not bool(q.get("any_order", false)): return [undone[0]]
	var rest := undone.filter(func(s): return str(s.get("kind", "")) != "strongbox")
	return rest if not rest.is_empty() else undone

## The step the quest log and the map point at: the first open one.
static func next_step(q: Dictionary) -> Dictionary:
	var open := open_steps(q)
	return open[0] if not open.is_empty() else {}

## What does a step: "step" (QuestStep from the client), "swap", "deliver", "sign", "verify", or "" (the chain or the server counts it).
static func done_by(step: Dictionary) -> String:
	return str(BY_STEP.get(str(step.get("kind", "")), ""))

static func steps_done(q: Dictionary) -> int:
	return q.get("steps", []).filter(func(s): return bool(s.get("done", false))).size()

## Every open step of every quest that happens at a place, as [quest, step]: what the world marks.
static func open_at(you: Dictionary, place: String) -> Array:
	var out := []
	for q in you.get("quests", []):
		for s in open_steps(q):
			if str(s.get("place", "")) == place: out.append([q, s])
	return out

## The sponsored campaigns to show on the Bounty Board: live ones only (PROTOCOL.md: `boosted` pays for the mystery instead).
static func board_cards(city: Dictionary) -> Array:
	return city.get("bounty", []).filter(func(c): return str(c.get("status", "")) == "live" and str(c.get("kind", "sponsored")) == "sponsored")

## Everything the Bounty Board offers, in its order: sponsored cards, today's errands, today's mystery, Grandma's Ledger. Each is
## {quest, title, story, by, energy, pays (USDC or -1 when it's the house's to say), card (the campaign, or {})}.
static func offers(you: Dictionary, city: Dictionary) -> Array:
	var out := []
	var on := {}
	for q in you.get("quests", []): on[str(q.get("quest", ""))] = true
	for c in board_cards(city):
		out.append({"quest": str(c.get("quest", "campaign:%d" % int(c.get("id", 0)))), "title": str(c.title), "story": "", "by": "sponsored",
			"energy": int(c.get("energy", 0)), "pays": int(c.get("payout", 0)), "card": c, "place": str(c.get("place", ""))})
	var errands: Dictionary = city.get("errands", {})
	for e in errands.get("list", []):
		out.append({"quest": str(e.quest), "title": str(e.title), "story": str(e.get("story", "")), "by": "errand",
			"energy": int(errands.get("energy", 0)), "pays": int(errands.get("rate", 0)), "card": {}, "place": str(e.get("place", ""))})
	var mystery = city.get("mystery")
	if mystery is Dictionary and not mystery.is_empty():
		out.append({"quest": str(mystery.quest), "title": str(mystery.title), "story": str(mystery.get("story", "")), "by": "mystery",
			"energy": int(mystery.get("energy", 0)), "pays": int(mystery.get("payout", 0)), "card": {}, "boosted_by": mystery.get("boosted_by"), "place": str(mystery.get("place", ""))})
	var grandma = city.get("grandma")
	if grandma is Dictionary and not grandma.is_empty() and not bool(you.get("grandma_done", false)):
		out.append({"quest": str(grandma.quest), "title": str(grandma.title), "story": str(grandma.get("story", "")), "by": "grandma",
			"energy": int(grandma.get("energy", 0)), "pays": -1, "card": {}})
	for o in out: o["on"] = on.has(o.quest)
	return out

## A quest's title, from the quest log or else from what's on offer.
static func quest_title(you: Dictionary, city: Dictionary, id: String) -> String:
	var q := quest(you, id)
	if not q.is_empty(): return str(q.get("title", id))
	for o in offers(you, city):
		if o.quest == id: return str(o.title)
	return "a quest"

## A transaction's page on the chain's explorer, or "" where there's none to see (offline, anvil, no tx).
static func tx_link(chain: String, tx) -> String:
	if tx == null or str(tx) == "" or not EXPLORERS.has(chain): return ""
	return "%s/tx/%s" % [EXPLORERS[chain], str(tx)]

static func address_link(chain: String, address) -> String:
	if address == null or str(address) == "" or not EXPLORERS.has(chain): return ""
	return "%s/address/%s" % [EXPLORERS[chain], str(address)]

## 0x2dde4583f88d88eff86ed67ca50801ca4fc19777 -> "0x2dde…9777".
static func short_address(address) -> String:
	var a := str(address) if address != null else ""
	return a if a.length() <= 12 else "%s…%s" % [a.left(6), a.right(4)]

## The tier one better, for the Town Goal's promise; gold stays gold.
static func tier_after(tier: String) -> String:
	var i := TIERS.find(tier)
	return TIERS[mini(i + 1, TIERS.size() - 1)] if i >= 0 else tier

## What your quests have you carrying (ux13): the cargo money advanced and still owed (USDC units), and the quest token a swap got,
## held for a delivery (base units as the server sends them, with its symbol and decimals). Both go when the quest pays.
static func carrying(you: Dictionary) -> Dictionary:
	var owe := 0
	var cargo := "0"
	var symbol := "MANGO"
	var decimals := 18
	for q in you.get("quests", []):
		if q.get("steps", []).any(func(s): return str(s.get("kind", "")) == "deliver" and bool(s.get("done", false))): continue
		owe += int(q.get("advanced", 0))
		if str(q.get("swapped", "0")) != "0":
			cargo = str(q.swapped)
			for s in q.get("steps", []):
				if s.get("quote") is Dictionary:
					symbol = str(s.quote.get("symbol", symbol))
					decimals = int(s.quote.get("decimals", decimals))
	return {"owe": owe, "cargo": cargo, "symbol": symbol, "decimals": decimals}

## A step in money words, where it moves money (the Spice Run's), else its own words cut to a line.
static func step_says(q: Dictionary, step: Dictionary) -> String:
	var cargo := int(q.get("cargo_usdc", 0))
	match str(step.get("kind", "")):
		"cargo": return "Collect the $%s cargo money at the harbourmaster" % Usdc.amount(cargo) if cargo > 0 else "Collect the cargo money at the harbourmaster"
		"swap": return "Swap $%s for MANGO at the exchange" % Usdc.amount(cargo) if cargo > 0 else "Swap the cargo money for MANGO at the exchange"
		"deliver":
			var held := str(q.get("swapped", "0"))
			return "Deliver %s MANGO to the Spice Merchant" % TokenAmount.about(held, 18) if held != "0" else "Deliver the MANGO to the Spice Merchant"
	return QuestMarks.step_words(step)
