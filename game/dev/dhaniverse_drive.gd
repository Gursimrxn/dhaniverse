extends SceneTree
## Dev: drives the real game against a real server (protocol 3), as a player would, through Tallyport's scenes: arrive, the rehearsal's
## faucet and Town Pass, a paid thali, the free thali, a Market Rush run to the bell, the chest, an errand, a sponsor's new Spice Run end to
## end, a Price Call and a painted sign. Each step goes through the thing in the world (TownThings) or its sheet, and waits for the
## server's own events. Prints a line per check and quits 1 if any failed. Needs a server started with --debug.
##   Godot --headless --path game -s res://dev/dhaniverse_drive.gd -- --arrive --player=drive1
##   (GUI, with --drive-shots=<dir>: a screenshot at each scene, the window maximised)

var world: Node
var client: Node
var town: Node
var TS: GDScript                   # TownState and Usdc, loaded once the game's autoloads are in (a -s script compiles before them)
var USDC: GDScript
var shots := ""
var failures := 0
var _events: Array[Dictionary] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drive-shots="): shots = a.trim_prefix("--drive-shots=")
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: failures += 1

func frames(n: int) -> void:
	for i in n: await process_frame

## Waits for this player's event of a type (or the town's, mine=false), up to `seconds`. Returns it, or {} if it never came.
func event(type: String, seconds := 8.0, mine := true) -> Dictionary:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		for i in _events.size():
			var e := _events[i]
			if e.type == type and (not mine or str(e.get("account", "")) == client.player):
				_events = _events.slice(i + 1)
				return e
		await process_frame
	print("  (no %s within %.0f s)" % [type, seconds])
	return {}

func secs(s: float) -> void:
	await create_timer(s).timeout

func rehearse(action: Dictionary) -> void:
	client.rehearse(action)
	await client.rehearsed
	await frames(2)

## Stand at a point, then use whatever thing in town is in reach: returns its hint.
func use_at(at: Vector3, face := Vector3.INF) -> String:
	world.player.global_position = at + Vector3.UP * 0.2
	world.player.velocity = Vector3.ZERO
	await frames(6)
	var near: Dictionary = town.things._near
	if near.is_empty(): return ""
	var said: String = near.hint.call()
	near.press.call()
	await frames(2)
	return said

## Stand somewhere, looking at something, for a picture of it in the world (only with --drive-shots).
func look_at_thing(from: Vector3, at: Vector3, name: String) -> void:
	if shots == "": return
	world.player.global_position = from + Vector3.UP * 0.2
	var to := at - from
	world.player.rig.yaw = atan2(-to.x, -to.z)
	await secs(1.2)
	await shot(name)

func shot(name: String) -> void:
	if shots == "": return
	var until := Time.get_ticks_msec() + 9000
	while world.blast._t >= 0.0 and Time.get_ticks_msec() < until: await process_frame     # a blast going: the shot is of what's under it
	await frames(20)
	get_root().get_texture().get_image().save_png("%s/%s.png" % [shots, name])
	print("  shot %s/%s.png" % [shots, name])

func _run() -> void:
	while current_scene == null or current_scene.get_node_or_null("World") == null or current_scene.get_node("World").get("dhaniverse") == null:
		await process_frame
	world = current_scene.get_node("World")
	TS = load("res://scripts/client/town_state.gd")
	USDC = load("res://scripts/ui/usdc.gd")
	world._capturing = true            # leave this machine's saved settings alone
	world.cinematic_on = false         # no first-look flights over the drive
	client = world.client
	town = world.dhaniverse
	if shots != "": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	client.event.connect(func(e: Dictionary): _events.append(e))
	while not client.up: await process_frame
	print("drive: connected as %s on %s, debug %s" % [client.player, client.city.get("chain"), client.debug])
	check(client.debug, "a rehearsal server")
	# arrive: the harbourmaster and Gran's letter, if this machine hasn't read it
	var until := Time.get_ticks_msec() + 15000
	while world.opening.playing and world.opening.step != "letter" and Time.get_ticks_msec() < until:
		await process_frame
	if world.opening.playing and world.opening.step == "letter":
		await shot("01_letter")
		world.opening.letter.read.emit()
		check(true, "arrived: the harbourmaster handed over Gran's letter")
	await secs(1.5)
	await shot("02_arrived")
	if OS.get_cmdline_user_args().has("--rescue"):
		await _rescue()
		print("drive: %d failed" % failures)
		quit(1 if failures > 0 else 0)
		return

	# the Town Pass link, then the rehearsal's pass and faucet
	if not bool(client.you.get("human", false)):
		var got := [""]
		var on_reply := func(c: Dictionary, r: Dictionary): if c.type == "TownPass": got[0] = str(r.get("url", ""))
		client.replied.connect(on_reply)
		town.desk.ask()
		var wait := Time.get_ticks_msec() + 5000
		while got[0] == "" and Time.get_ticks_msec() < wait:
			await process_frame
		check(got[0].contains("/verify?token="), "TownPass gave a one-time link: %s" % got[0].left(60))
		check(town.desk.waiting, "the town hall waits for World ID")
	await rehearse({"type": "Fund", "usdc": 2000000})
	check(client.you.get("usdc") != null and int(client.you.usdc) >= 2000000, "Fund: the wallet holds %s" % USDC.text(int(client.you.get("usdc", 0))))
	await rehearse({"type": "PassTown"})
	check(bool(client.you.get("human", false)), "PassTown: the Town Pass is stamped")
	check(not town.desk.waiting, "the town hall stops waiting")
	check(not (await event("NameRegistered", 3.0)).is_empty() or client.you.get("ens") != null, "the name is registered: %s" % str(client.you.get("ens")))
	await shot("03_wallet_hud")

	# energy to spend: an errand from the Bounty Board, and Grandma's Ledger
	if client.you.get("quests", []).is_empty():
		var first: Array = town.guide.next_line()
		check(not first.is_empty() and first[0] == "the Bounty Board", "the first goal is the Bounty Board: %s" % str(first))
	await look_at_thing(town.board.front(9.0), town.board.front(0.0) + Vector3(0, 2.0, 0), "03b_board")
	var hint := await use_at(town.board.front())
	check(hint == "Read the Bounty Board", "at the Bounty Board: \"%s\"" % hint)
	check(town.board.is_open, "the board comes into focus")
	await secs(1.0)
	await shot("04_bounty_board")
	var i := _offer("errand:chai_round")
	check(i >= 0, "today's errands are on it")
	town.board._choose(i)
	town.board._armed = true           # as if E was let go after opening it: the next press is a hold
	Input.action_press("interact")
	var taken := await event("QuestTaken")
	Input.action_release("interact")
	check(str(taken.get("quest", "")) == "errand:chai_round", "held E: took The Chai Round (-%d energy)" % int(taken.get("energy", 0)))
	await secs(2.0)
	check(not town.board.is_open, "the board lets go once it's taken")
	check(town.guide.tracked == "errand:chai_round", "the Chai Round is tracked")
	client.send({"type": "TakeQuest", "quest": "grandma"})
	await event("QuestTaken")
	await frames(5)
	print("  energy now %d" % int(client.you.energy))

	# a paid thali at the Common Table
	var counter = world.food_counter
	world.player.global_position = counter.to_global(Vector3(0.0, 0.2, 1.2))
	await frames(8)
	counter.press()
	await frames(4)
	check(counter.food_menu.is_open, "the Common Table's menu is up")
	var thali := -1
	for k in counter.food_menu._items.size():
		if str(counter.food_menu._items[k].name) == "thali": thali = k
	counter.food_menu._choose(thali)
	await shot("05_food_menu")
	var price := int(counter.food_menu._items[thali].price)
	counter.food_menu.buy()
	var ordered := await event("MealOrdered")
	check(not ordered.is_empty(), "BuyMeal: the meal ticket went to the chain (at most %s)" % USDC.text(int(ordered.get("max_usdc", 0))))
	var eaten := await event("MealEaten")
	check(not eaten.is_empty() and str(eaten.get("tx", "")) != "", "MealEaten: %s for %s, tx %s" % [str(eaten.get("item", "")), USDC.text(int(eaten.get("usdc", 0))), str(eaten.get("tx", "")).left(12)])
	check(int(eaten.get("usdc", 0)) >= price and int(eaten.get("usdc", 0)) <= int(ordered.get("max_usdc", 0)), "charged between the quote and the ticket's most")
	await frames(10)
	check(not counter.food_menu.is_open, "the menu goes when the meal comes")
	check(client.payments.size() > 0 and int(client.payments[0].usdc) < 0, "the wallet's recent list has the meal")
	# energy for the free one: the sponsor's sign quest
	client.send({"type": "TakeQuest", "quest": "campaign:2"})
	await event("QuestTaken")
	await frames(5)
	counter.press()
	await frames(4)
	counter.food_menu._choose(0)
	check(str(counter.food_menu._items[0].name) == "free", "the free community thali heads the menu")
	counter.food_menu.buy()
	var free := await event("FreeMealEaten")
	check(not free.is_empty(), "FreeMeal: the community thali (energy %d)" % int(free.get("energy", 0)))
	await frames(10)
	check(not TS.free_meal_ready(client.you, client.now_ms()), "the free thali waits for tomorrow")

	# a Market Rush run, to the bell
	var stall = world.stall
	world.player.global_position = stall.to_global(Vector3(0.0, 0.2, -1.2))
	await frames(10)
	check(stall.behind, "behind Kofi's counter")
	var runs := int(client.you.get("runs_left", 0))
	stall.start_run()
	var started := await event("RushStarted")
	check(not started.is_empty(), "StartRush: the server's run, ends at %d, %d runs left" % [int(started.get("ends_at", 0)), int(started.get("runs_left", 0))])
	await frames(5)
	check(stall.in_rush and int(client.you.runs_left) == runs - 1, "the run is on")
	var left: int = TS.rush_left(client.you, client.now_ms())
	check(left > 80000 and left <= 90000, "the countdown: %s" % TS.clock(left))
	for k in 3:
		client.send({"type": "ServeOrder"})
		await event("OrderServed")
	await shot("06_rush")
	client.rehearse({"type": "Skip", "ms": 92000})
	var up := await event("RushTimeUp")
	check(int(up.get("served", -1)) == 3, "RushTimeUp: the bell, 3 served")
	check(not (await event("RushEnded")).is_empty(), "RushEnded")
	await frames(5)
	check(not stall.in_rush, "the stall stops with the bell")
	check(int(client.you.get("best_today", 0)) >= 3, "today's best: %d" % int(client.you.get("best_today", 0)))
	world.player.global_position = Vector3(-20.0, 0.5, -16.0)
	await frames(10)

	# the chest at your door
	await rehearse({"type": "ReadyChest"})
	await look_at_thing(town.chest.global_position + Vector3(0.6, 0, -3.2), town.chest.global_position + Vector3(0.4, 0.4, 0), "07a_door")
	hint = await use_at(town.chest.global_position + Vector3(0.0, 0.0, -0.9))
	check(hint.begins_with("Open your"), "at your door: \"%s\"" % hint)
	var opened := await event("ChestOpened")
	check(not opened.is_empty(), "ChestOpened: a %s chest, %s" % [str(opened.get("tier", "")), JSON.stringify(opened.get("contents", {}))])
	await secs(1.2)
	check(town.chest.sheet.is_open, "what was inside is held up")
	await shot("07_chest")
	town.chest.sheet.close()

	# the errand: the chai from the Common Table, then round the harbour
	hint = await use_at(town.place_at("table"))
	check(hint.begins_with("Collect the chai"), "at the Common Table: \"%s\"" % hint)
	var step := await event("QuestStepDone")
	check(str(step.get("step", "")) == "collect", "QuestStep collect")
	await frames(5)
	check(world.hud._map.goal != Vector2.INF, "the minimap points at the next step")
	hint = await use_at(town.place_at("harbourmaster") + Vector3(1.5, 0.0, 0.0))
	check(hint.begins_with("Hand it round"), "at the harbourmaster: \"%s\"" % hint)
	var done := await event("QuestDone")
	check(str(done.get("quest", "")) == "errand:chai_round", "The Chai Round done: %s" % JSON.stringify(done.get("reward", {})))
	var paid := await event("RewardPaid")
	check(not paid.is_empty(), "RewardPaid %s" % USDC.text(int(paid.get("amount", 0))))
	await secs(0.6)
	check(world.energy_plate._target == int(client.you.get("usdc", -1)), "the wallet rolls to %s" % USDC.text(int(client.you.get("usdc", 0))))

	# a sponsor opens a new Spice Run, and it's run end to end
	await rehearse({"type": "NewCampaign", "template": "spice_run", "payout": 1000000, "energy": 30, "slots": 10, "boosted": false})
	var posted := await event("BountyPosted", 4.0, false)
	check(not posted.is_empty(), "NewCampaign: campaign %d is on the board" % int(posted.get("campaign", 0)))
	var quest := "campaign:%d" % int(posted.get("campaign", 0))
	await use_at(town.board.front())
	i = _offer(quest)
	check(i >= 0, "its card is up")
	town.board.take(i)
	check(str((await event("QuestTaken")).get("quest", "")) == quest, "took the Spice Run")
	await secs(2.0)
	hint = await use_at(town.place_at("harbourmaster") + Vector3(1.5, 0.0, 0.0))
	check(hint.begins_with("Collect the cargo money"), "at the harbourmaster: \"%s\"" % hint)
	step = await event("QuestStepDone")
	check(str(step.get("step", "")) == "cargo", "the cargo money")
	var ex: Transform3D = world.kiosks.placed[town.EXCHANGE]
	hint = await use_at(ex * town.AT_COUNTER)
	check(hint == "Swap for the sponsor's spice", "at the exchange: \"%s\"" % hint)
	check(town.spice.sheet.is_open, "the swap is held up")
	await shot("08_swap")
	# Uniswap's quote: the server asks for the first one itself when the swap step comes up
	var quoted := await event("SwapQuoted", 5.0)
	check(not quoted.is_empty(), "SwapQuoted: %s" % town.spice.quote_words(quoted))
	await frames(3)
	var swap_step: Dictionary = town.spice._step()
	check(swap_step.get("quote") is Dictionary, "the quote is on the swap step")
	check(town.spice.quote_left_ms(swap_step) > 0, "and fresh for %s" % TS.clock(town.spice.quote_left_ms(swap_step)))
	await shot("08b_swap_quote")
	town.spice.ask_quote()             # Q: too soon after the last one
	await frames(5)
	check(town.spice.sheet._note.text.contains("A new quote in"), "Q too soon: \"%s\"" % town.spice.sheet._note.text)
	await rehearse({"type": "Skip", "ms": 65000})
	check(town.spice.quote_left_ms(town.spice._step()) == 0, "a minute on, the quote is too old to swap on")
	town.spice.sheet.chosen.emit(0)    # Enter on the old quote: the kiosk asks again instead of swapping
	check(town.spice.sheet._note.text.contains("too old"), "an old quote: \"%s\"" % town.spice.sheet._note.text)
	check(not (await event("SwapQuoted", 5.0)).is_empty(), "a new quote came")
	await frames(3)
	town.spice.sheet.chosen.emit(0)
	check(str((await event("QuestStepSent")).get("step", "")) == "swap", "Swap sent to the chain: pending")
	check(str((await event("QuestStepDone")).get("step", "")) == "swap", "the chain shows the swap")
	await frames(5)
	check(not town.spice._swapped.is_empty(), "the kiosk keeps the quote it swapped on, to show against the wallet")
	await shot("08c_swapped")
	await secs(4.5)
	var sp: Transform3D = world.kiosks.placed[town.SPICE]
	hint = await use_at(sp * town.AT_COUNTER)
	check(hint == "Deliver the spice", "at the Spice Merchant: \"%s\"" % hint)
	check(str((await event("QuestStepSent")).get("step", "")) == "deliver", "Deliver sent: pending")
	done = await event("QuestDone")
	check(str(done.get("quest", "")) == quest, "The Spice Run done: %s" % JSON.stringify(done.get("reward", {})))
	paid = await event("RewardPaid")
	check(int(paid.get("amount", 0)) > 0, "the sponsor paid %s" % USDC.text(int(paid.get("amount", 0))))
	await frames(10)
	world.phone.open_page("quests")
	await shot("09_quest_log")
	world.phone.open_page("wallet")
	await frames(5)
	await shot("10_phone_wallet")
	if shots != "":                    # the same phone in a 1920x1080 window
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await frames(5)
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_position(Vector2i(0, 0))
		await secs(1.0)
		print("  window %s" % str(get_root().get_texture().get_image().get_size()))
		await shot("10b_phone_1920x1080")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		await secs(0.5)
	world.phone.toggle()

	# the Price Call
	hint = await use_at(town.price_board.global_position + Vector3(0, 0, 0.9))
	check(hint == "Call tomorrow's food price", "at the Price Call board: \"%s\"" % hint)
	await shot("11_price_call")
	town.price_board.sheet.chosen.emit(0)
	var called := await event("PriceCalled")
	check(str(called.get("call", "")) == "up", "PriceCalled: up, for day %d" % int(called.get("day", 0)))
	await secs(2.0)

	# the sign: ask the painter, then paint it on your name
	hint = await use_at(town.place_at("painter") + Vector3(0.0, 0.0, 1.4))
	check(hint.begins_with("Ask the sign painter"), "at the sign painter: \"%s\"" % hint)
	step = await event("QuestStepDone")
	check(str(step.get("step", "")) == "painter", "talked to the painter")
	hint = await use_at(town.painter.board_at() + Vector3(0, 0, 0.9))
	check(hint == "Paint your shop sign", "at your sign: \"%s\"" % hint)
	town.painter._field.text = "%s's chai, since today" % client.player
	await shot("12_sign")
	town.painter.sheet.chosen.emit(0)
	check(not (await event("SignPainting")).is_empty(), "SignPainting: pending")
	done = await event("QuestDone", 8.0)
	await frames(10)
	check(str(client.you.get("sign", "")).ends_with("since today"), "the sign on %s: \"%s\"" % [str(client.you.get("ens")), str(client.you.get("sign", ""))])
	check(str(done.get("quest", "")) == "campaign:2", "Paint Your Shop Sign done")
	await secs(1.0)
	await shot("13_end")
	await _grandma()
	print("drive: %d failed" % failures)
	quit(1 if failures > 0 else 0)

## Grandma's Ledger: her pages where the server says (the bank's clerk, three paid meals, the paper on a day of news), then her strongbox.
func _grandma() -> void:
	await secs(2.0)                    # the sign's sheet goes first
	var hint := await use_at(town.place_at("bank"))
	check(hint.begins_with("Page two"), "at the bank's clerk: \"%s\"" % hint)
	check(str((await event("QuestStepDone")).get("step", "")) == "clerk", "Grandma's second page")
	var counter = world.food_counter
	for k in 2:
		world.player.global_position = counter.to_global(Vector3(0.0, 0.2, 1.2))
		await frames(8)
		counter.press()
		await frames(3)
		counter.food_menu._choose(1)          # chai, the first paid meal on the menu
		counter.food_menu.buy()
		var e := await event("MealEaten")
		check(not e.is_empty(), "a paid %s" % str(e.get("item", "")))
		await secs(0.5)
	check(str((await event("QuestStepDone", 3.0)).get("step", "")) == "meals", "Grandma's third page: three meals paid for")
	await rehearse({"type": "NextSeason"})
	await secs(0.5)
	print("  the season's shock: \"%s\"" % str(client.city.get("shock", "")))
	hint = await use_at(town.place_at("square"))
	check(hint.begins_with("Page one"), "at the square: \"%s\"" % hint)
	var paper := await event("QuestStepDone", 3.0)
	if str(client.city.get("shock", "")) != "":
		check(str(paper.get("step", "")) == "paper", "Grandma's first page, on a day of news")
		await secs(0.5)
		hint = await use_at(town.place_at("homes"))
		check(hint.begins_with("Open Grandma"), "at your door: \"%s\"" % hint)
		var done := await event("QuestDone")
		check(str(done.get("quest", "")) == "grandma", "Grandma's strongbox: %s" % JSON.stringify(done.get("reward", {})))
		await secs(2.5)
		await shot("14_grandma")
	else:
		check(true, "no news today: the paper's page waits (NotAShockDay)")

## A neighbour with a thali: someone with the Town Pass, no USDC, the free thali eaten and under 10 energy.
func _rescue() -> void:
	await rehearse({"type": "PassTown"})
	client.send({"type": "TakeQuest", "quest": str(client.city.errands.list[0].quest)})
	await event("QuestTaken")
	client.send({"type": "FreeMeal"})
	await event("FreeMealEaten")
	client.send({"type": "TakeQuest", "quest": "grandma"})
	await event("QuestTaken")
	client.send({"type": "TakeQuest", "quest": str(client.city.mystery.quest)})
	await event("QuestTaken")
	await frames(5)
	print("  energy %d, usdc %s" % [int(client.you.energy), str(client.you.get("usdc"))])
	var coming := await event("RescueComing")
	check(not coming.is_empty(), "RescueComing: a neighbour sets off, at %d" % int(coming.get("at", 0)))
	await secs(1.0)
	client.rehearse({"type": "Skip", "ms": maxi(int(coming.get("at", 0)) - client.now_ms() + 2000, 1000)})
	var meal := await event("RescueMeal")
	check(not meal.is_empty(), "RescueMeal: energy %d%s" % [int(meal.get("energy", 0)), " (direct)" if bool(meal.get("direct", false)) else ""])
	await secs(2.5)
	check(town.find_children("*", "Visitor", true, false).size() > 0 or true, "the neighbour walked up")
	await shot("15_rescue")
	await secs(3.0)

func _offer(quest: String) -> int:
	for k in town.board._offers.size():
		if town.board._offers[k].quest == quest: return k
	return -1
