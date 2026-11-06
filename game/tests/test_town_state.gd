extends TestCase
## Reading `you` and `city` (PROTOCOL.md v3) as the client needs: the real clock's waits, the chest and the streak, which quest step is
## next and what does it, what the Bounty Board offers, where a transaction can be looked at. All from the server's own numbers.

const SPICE := {"quest": "campaign:1", "title": "The Spice Run", "kind": {"type": "campaign", "campaign": 1.0, "template": "spice_run"}, "any_order": false, "hold": null,
	"steps": [{"id": "cargo", "kind": "cargo", "place": "harbourmaster", "text": "Collect the cargo money from the harbourmaster. If your wallet is short, he'll advance it.", "done": true, "waiting": false},
		{"id": "swap", "kind": "swap", "place": "kiosk", "text": "Swap the cargo money.", "done": false, "waiting": true},
		{"id": "deliver", "kind": "deliver", "place": "spice-merchant", "text": "Deliver the spice.", "done": false, "waiting": false}]}
const GRANDMA := {"quest": "grandma", "title": "Grandma's Ledger", "kind": {"type": "grandma"}, "any_order": true, "hold": null,
	"steps": [{"id": "paper", "kind": "paper", "place": "square", "text": "Page one.", "done": false, "waiting": false},
		{"id": "clerk", "kind": "talk", "place": "bank", "text": "Page two.", "done": true, "waiting": false},
		{"id": "meals", "kind": "meals", "place": "table", "text": "Page three.", "done": false, "waiting": false},
		{"id": "strongbox", "kind": "strongbox", "place": "homes", "text": "Open Grandma's strongbox.", "done": false, "waiting": false}]}

func test_a_wait_on_the_real_clock() -> void:
	eq(TownState.left_ms(null, 500), 0, "null is now")
	eq(TownState.left_ms(0.0, 500), 0, "0 is now")
	eq(TownState.left_ms(400.0, 500), 0, "past is now")
	eq(TownState.left_ms(86400000.0, 1000), 86399000, "still to come")

func test_clocks_read_plainly() -> void:
	eq(TownState.clock(0), "0:00", "nothing")
	eq(TownState.clock(59001), "1:00", "a second up rounds up")
	eq(TownState.clock(90000), "1:30", "a Rush run")
	eq(TownState.clock(3 * 3600000), "3:00:00", "hours")
	eq(TownState.soon(4 * 3600000), "in 4 h", "hours in words")
	eq(TownState.soon(12 * 60000), "in 12 min", "minutes in words")
	eq(TownState.soon(40000), "in 40 s", "seconds in words")

func test_the_chest_and_the_weekly_strongbox() -> void:
	var you := {"chest": {"ready_at": 0.0, "tier": "brass", "pity": 3.0, "pity_every": 10.0, "weekly_ready_at": 0.0}, "streak": {"days": 3.0, "week_days": 3.0, "need": 5.0}}
	check(TownState.chest_ready(you, 1000), "ready_at 0 is ready")
	check(not TownState.weekly_ready(you, 1000), "3 of 5 days: not yet")
	you.streak.week_days = 5.0
	check(TownState.weekly_ready(you, 1000), "5 of 5")
	you.chest.weekly_ready_at = 5000.0
	check(not TownState.weekly_ready(you, 1000), "opened this week")
	you.chest.ready_at = 2000.0
	check(not TownState.chest_ready(you, 1000), "not till 2000")
	check(not TownState.chest_ready({}, 1000), "no chest heard of yet")
	eq(TownState.tier_after("wood"), "brass", "the Town Goal's promise")
	eq(TownState.tier_after("gold"), "gold", "gold stays gold")

func test_the_free_thali_and_the_run() -> void:
	check(TownState.free_meal_ready({"free_meal_at": 0.0}, 10), "ready")
	check(not TownState.free_meal_ready({"free_meal_at": 86400000.0}, 10), "tomorrow")
	check(not TownState.free_meal_ready({}, 10), "nothing heard")
	eq(TownState.rush_left({"in_rush": true, "rush_ends_at": 93025.0}, 3025), 90000, "the server's 90 s")
	eq(TownState.rush_left({"in_rush": false, "rush_ends_at": null}, 3025), 0, "no run")

func test_steps_in_order() -> void:
	var open := TownState.open_steps(SPICE)
	eq(open.size(), 1, "one at a time")
	eq(str(open[0].id), "swap", "the first undone")
	eq(str(TownState.next_step(SPICE).id), "swap", "next")
	eq(TownState.done_by(SPICE.steps[0]), "step", "cargo is reported by the client")
	eq(TownState.done_by(SPICE.steps[1]), "swap", "the swap is its own command")
	eq(TownState.done_by(SPICE.steps[2]), "deliver", "and the delivery")
	eq(TownState.done_by({"kind": "meals"}), "", "meals are counted by the server")
	eq(TownState.steps_done(SPICE), 1, "done")
	eq(TownState.template(SPICE), "spice_run", "template")

func test_grandmas_pages_any_order_and_the_strongbox_last() -> void:
	var open := TownState.open_steps(GRANDMA).map(func(s): return str(s.id))
	eq(open, ["paper", "meals"], "every page still to find, not the strongbox")
	var all_found := GRANDMA.duplicate(true)
	for s in all_found.steps:
		if s.id != "strongbox": s.done = true
	eq(TownState.open_steps(all_found).map(func(s): return str(s.id)), ["strongbox"], "then the strongbox")
	for s in all_found.steps: s.done = true
	eq(TownState.open_steps(all_found).size(), 0, "nothing left")

func test_steps_by_place() -> void:
	var you := {"quests": [SPICE, GRANDMA]}
	eq(TownState.open_at(you, "kiosk").size(), 1, "the swap at the kiosk")
	eq(TownState.open_at(you, "square").size(), 1, "Grandma's first page at the square")
	eq(TownState.open_at(you, "homes").size(), 0, "her strongbox waits for the pages")
	eq(TownState.quest(you, "grandma").title, "Grandma's Ledger", "found by id")
	check(TownState.quest(you, "nope").is_empty(), "not on it")

func test_the_bounty_board_offers() -> void:
	var city := {
		"bounty": [{"id": 1.0, "quest": "campaign:1", "kind": "sponsored", "title": "The Spice Run", "payout": 1000000.0, "energy": 30.0, "status": "live", "slots_left": 47.0},
			{"id": 2.0, "quest": "campaign:2", "kind": "sponsored", "title": "Old", "payout": 1.0, "energy": 1.0, "status": "ended"},
			{"id": 3.0, "quest": "campaign:3", "kind": "boosted", "title": "Boost", "payout": 1.0, "energy": 1.0, "status": "live"}],
		"errands": {"rate": 40000.0, "per_day": 3.0, "energy": 10.0, "list": [{"quest": "errand:chai_round", "title": "The Chai Round", "story": "Thirsty."}]},
		"mystery": {"quest": "mystery:night_bell", "title": "The Night Bell", "story": "?", "energy": 50.0, "payout": 500000.0, "boosted_by": null},
		"grandma": {"quest": "grandma", "title": "Grandma's Ledger", "story": "...", "energy": 50.0}}
	var offers := TownState.offers({"quests": [SPICE], "grandma_done": false}, city)
	eq(offers.map(func(o): return o.quest), ["campaign:1", "errand:chai_round", "mystery:night_bell", "grandma"], "live sponsored cards, errands, the mystery, Grandma")
	eq(int(offers[0].pays), 1000000, "the card's payout, as sent")
	eq(int(offers[1].pays), 40000, "today's errand rate")
	check(offers[0].on, "already on the Spice Run")
	check(not offers[1].on, "not on the errand")
	eq(int(offers[3].pays), -1, "Grandma's is her strongbox's to say")
	eq(TownState.offers({"grandma_done": true}, city).size(), 3, "Grandma's once a season")
	eq(TownState.quest_title({}, city, "errand:chai_round"), "The Chai Round", "a title from what's on offer")

func test_explorer_links_only_where_there_is_a_chain() -> void:
	eq(TownState.tx_link("sepolia", "0xabc"), "https://sepolia.etherscan.io/tx/0xabc", "sepolia")
	eq(TownState.tx_link("offline", "0xabc"), "", "a rehearsal has nothing to look at")
	eq(TownState.tx_link("anvil", "0xabc"), "", "nor a chain on this machine")
	eq(TownState.tx_link("sepolia", null), "", "no tx")
	eq(TownState.address_link("sepolia", "0x2dde"), "https://sepolia.etherscan.io/address/0x2dde", "an address")
	eq(TownState.short_address("0x2dde4583f88d88eff86ed67ca50801ca4fc19777"), "0x2dde…9777", "short")
	eq(TownState.short_address(null), "", "none")
