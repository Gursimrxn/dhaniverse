extends TestCase
## The client against server messages from server/PROTOCOL.md (version 3), with no socket: what it holds, and what it does with a
## command that has no answer yet.

const YOU := {"name": "sam", "energy": 100.0, "in_rush": false, "served": 0.0, "best_run": 0.0, "firsts": []}
const CITY := {"day": 3.0, "day_ms": 3600000.0, "day_elapsed_ms": 0.0, "now_ms": 10920000.0, "chain": "offline", "price": 1021.0, "most_orders_per_run": 40.0}

func _snapshot(c: TownClient, debug := false) -> void:
	c.handle_message({"type": "snapshot", "seq": 1.0, "debug": debug, "you": YOU.duplicate(), "city": CITY.duplicate()})

func test_it_says_hello_as_protocol_3() -> void:
	eq(TownClient.PROTOCOL, 3, "protocol")

func test_a_snapshot_replaces_everything() -> void:
	var c := TownClient.new()
	var synced: Array[int] = []
	c.synced.connect(func(): synced.append(1))
	_snapshot(c)
	check(c.up, "up after a snapshot")
	eq(synced.size(), 1, "synced")
	eq(int(c.you.energy), 100, "energy")
	check(not c.debug, "not a rehearsal server")
	c.handle_message({"type": "you", "you": {"name": "sam", "energy": 60.0, "served": 4.0}})
	eq(int(c.you.energy), 60, "a `you` replaces what was held")
	check(not c.you.has("in_rush"), "replaced, not merged")
	c.free()

func test_time_corrects_the_day_and_keeps_the_rest() -> void:
	var c := TownClient.new()
	_snapshot(c)
	c.handle_message({"type": "time", "day": 4.0, "day_ms": 3600000.0, "day_elapsed_ms": 5.0})
	eq(int(c.city.day), 4, "day")
	eq(int(c.city.day_elapsed_ms), 5, "elapsed")
	eq(int(c.city.price), 1021, "the rest of the city stays")
	eq(int(c.you.energy), 100, "you stays")
	c.free()

func test_events_are_passed_on_unwrapped() -> void:
	var c := TownClient.new()
	var got: Array[Dictionary] = []
	c.event.connect(func(e: Dictionary): got.append(e))
	c.handle_message({"type": "event", "seq": 2.0, "event": {"type": "OrderServed", "account": "sam", "served": 3.0, "ref": "sam:sam-1"}})
	eq(got.size(), 1, "events")
	eq(got[0].type, "OrderServed", "type")
	eq(int(got[0].served), 3, "the run's count")
	c.free()

func test_rehearsals_go_only_to_a_rehearsal_server() -> void:
	var c := TownClient.new()
	_snapshot(c)
	c.rehearse({"type": "Eat", "item": "chai"})     # no socket either way: this only must not fail
	check(not c.debug, "debug off")
	_snapshot(c, true)
	check(c.debug, "snapshot.debug on")
	var done: Array[int] = []
	c.rehearsed.connect(func(): done.append(1))
	c.handle_message({"type": "debug_done"})
	eq(done.size(), 1, "debug_done")
	c.free()

func test_refs_are_new_for_each_command_and_differ_between_runs() -> void:
	var a := TownClient.new()
	a.start("sam")
	var b := TownClient.new()
	b.start("sam")
	b._session = "later"
	var first := a.send({"type": "ServeOrder"})
	check(first != a.send({"type": "ServeOrder"}), "each command its own ref")
	check(first != b.send({"type": "ServeOrder"}), "a new run does not reuse an old ref")
	check(first.begins_with(a.player), "the ref carries the player")
	a.free()
	b.free()

func test_a_command_waits_until_its_result_keeping_its_ref() -> void:
	var c := TownClient.new()
	var ref := c.send({"type": "ServeOrder"})     # the link is down
	eq(c._pending.size(), 1, "waiting")
	_snapshot(c)                                  # back up: it would be sent again, under this same ref
	eq(c._pending[0].ref, ref, "same ref")
	c.handle_message({"type": "result", "ref": ref, "ok": true})
	eq(c._pending.size(), 0, "answered")
	c.free()

func test_a_refusal_names_the_command_but_refused_on_retry_is_success() -> void:
	var c := TownClient.new()
	var got: Array[String] = []
	c.refused.connect(func(command: Dictionary, r: Dictionary): got.append("%s %s" % [command.type, r.type]))
	var a := c.send({"type": "StartRush"})
	var b := c.send({"type": "ServeOrder"})
	var d := c.send({"type": "ServeOrder"})
	c.handle_message({"type": "result", "ref": b, "ok": false, "refusal": {"type": "RefUsed", "ref": b}})
	eq(got.size(), 0, "RefUsed: the first try got through")
	c.handle_message({"type": "result", "ref": a, "ok": false, "refusal": {"type": "AlreadyInRush"}})
	c.handle_message({"type": "result", "ref": d, "ok": false, "refusal": {"type": "RushFull", "most": 40.0}})
	eq(got, ["StartRush AlreadyInRush", "ServeOrder RushFull"] as Array[String], "refused")
	eq(c._pending.size(), 0, "all answered")
	c.free()

func test_being_kicked_stops_the_link() -> void:
	var c := TownClient.new()
	_snapshot(c)
	c.handle_message({"type": "kicked"})
	check(not c.up, "down")
	check(c.kicked, "and stays down, so two windows don't fight over one name")
	c.free()

func test_the_real_clock_counts_on_between_the_servers_words() -> void:
	var c := TownClient.new()
	eq(c.now_ms(), 0, "nothing heard yet")
	_snapshot(c)
	check(c.now_ms() >= 10920000 and c.now_ms() < 10920000 + 1000, "the snapshot's now_ms: %d" % c.now_ms())
	c.handle_message({"type": "time", "day": 3.0, "day_ms": 3600000.0, "day_elapsed_ms": 9.0, "now_ms": 20000000.0})
	check(c.now_ms() >= 20000000 and c.now_ms() < 20000000 + 1000, "time corrects it: %d" % c.now_ms())
	eq(int(c.city.now_ms), 20000000, "and city.now_ms with it")
	c.handle_message({"type": "city", "city": {"day": 4.0, "now_ms": 30000000.0}})
	check(c.now_ms() >= 30000000, "a city message says it too")
	c.free()

func test_a_snapshot_keeps_the_feed() -> void:
	var c := TownClient.new()
	c.handle_message({"type": "snapshot", "seq": 1.0, "debug": true, "you": YOU.duplicate(), "city": CITY.duplicate(),
		"feed": [{"id": 1.0, "day": 0.0, "kind": "bounty", "text": "A new bounty is up on the board in the square.", "about": null, "reactions": {}}]})
	eq(c.feed.size(), 1, "the feed's posts")
	check(c.debug, "rehearsal")
	c.free()

func test_a_result_with_a_url_reaches_whoever_asked() -> void:
	var c := TownClient.new()
	var got: Array[String] = []
	c.replied.connect(func(command: Dictionary, reply: Dictionary): got.append("%s %s" % [command.type, reply.get("url", "")]))
	var ref := c.send({"type": "TownPass"})
	c.handle_message({"type": "result", "ref": ref, "ok": true, "url": "https://town.example.com/verify?token=4be1"})
	eq(got, ["TownPass https://town.example.com/verify?token=4be1"] as Array[String], "the url")
	c.free()

func test_money_that_moved_is_kept_for_the_wallet() -> void:
	var c := TownClient.new()
	c.start("sam")
	c.handle_message({"type": "event", "seq": 3.0, "event": {"type": "MealEaten", "account": "sam", "item": "thali", "usdc": 21738.0, "food": 6000000.0, "energy": 90.0, "from_ration": 0.0, "ref": "sam:1", "tx": "0xabc"}})
	c.handle_message({"type": "event", "seq": 4.0, "event": {"type": "RewardPaid", "account": "sam", "amount": 1000000.0, "why": "sponsored quest", "ref": "claim:1", "tx": "0xdef"}})
	c.handle_message({"type": "event", "seq": 5.0, "event": {"type": "RewardPaid", "account": "priya", "amount": 5.0, "why": "rush", "ref": "x", "tx": "0x1"}})
	c.handle_message({"type": "event", "seq": 6.0, "event": {"type": "BalanceChanged", "account": "sam", "usdc": 5.0}})
	eq(c.payments.size(), 2, "only this player's, only money that moved")
	eq(int(c.payments[0].usdc), 1000000, "newest first, paid in")
	eq(int(c.payments[1].usdc), -21738, "a meal is money out")
	eq(str(c.payments[1].tx), "0xabc", "with its transaction")
	c.free()

func test_a_profile_is_passed_on() -> void:
	var c := TownClient.new()
	var got: Array[Dictionary] = []
	c.profiled.connect(func(card: Dictionary): got.append(card))
	c.handle_message({"type": "profile", "found": true, "name": "sam", "title": "Spice Runner", "stamps": ["spice-run"], "reputation": "Known around town"})
	eq(got.size(), 1, "profiled")
	eq(str(got[0].reputation), "Known around town", "its words")
	c.free()

func test_the_http_side_is_beside_the_socket() -> void:
	var c := TownClient.new()
	c.url = "ws://127.0.0.1:7878"
	eq(c.http_base(), "http://127.0.0.1:7878", "ws")
	c.url = "wss://town.example.com/"
	eq(c.http_base(), "https://town.example.com", "wss")
	c.free()

func test_an_error_is_said_not_thrown() -> void:
	var c := TownClient.new()
	var got: Array[String] = []
	c.server_said.connect(func(m: String): got.append(m))
	c.handle_message({"type": "error", "message": "Fund is offline only"})
	eq(got, ["Fund is offline only"] as Array[String], "the message")
	c.free()
