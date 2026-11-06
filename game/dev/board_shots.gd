extends SceneTree
## Dev: pictures of the game layer's first batch, against a --debug server: the Bounty Board from down the road with the island's Next
## line, the board in focus with the hold-E ring half full, the first quest's blast, and a later quest's pay (the island's lobe and the
## wallet rolling). Saves PNGs to --shots-to=<dir>, then quits.
##   tools/godot_d.sh --path game --resolution 1440x810 -s res://dev/board_shots.gd -- --arrive --player=NAME --shots-to=D:/dir

var world: Node
var client: Node
var town: Node
var dir := ""
var _events: Array[Dictionary] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-to="): dir = a.trim_prefix("--shots-to=")
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()

func secs(s: float) -> void:
	await create_timer(s).timeout

func shot(name: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func event(type: String, seconds := 8.0) -> Dictionary:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		for i in _events.size():
			if _events[i].type == type and str(_events[i].get("account", "")) == client.player:
				var e := _events[i]
				_events = _events.slice(i + 1)
				return e
		await process_frame
	print("(no %s)" % type)
	return {}

func stand(at: Vector3, look: Vector3) -> void:
	world.player.global_position = at + Vector3.UP * 0.2
	world.player.velocity = Vector3.ZERO
	var to := look - at
	world.player.rig.yaw = atan2(-to.x, -to.z)

func press_at(at: Vector3) -> void:
	stand(at, at + Vector3(0, 0, -1))
	for i in 6: await process_frame
	var near: Dictionary = town.things._near
	if not near.is_empty(): near.press.call()

func _run() -> void:
	while current_scene == null or current_scene.get_node_or_null("World") == null or current_scene.get_node("World").get("tallyport") == null:
		await process_frame
	world = current_scene.get_node("World")
	world._capturing = true
	world.cinematic_on = false
	client = world.client
	town = world.tallyport
	client.event.connect(func(e: Dictionary): _events.append(e))
	while not client.up: await process_frame
	var until := Time.get_ticks_msec() + 15000
	while world.opening.playing and world.opening.step != "letter" and Time.get_ticks_msec() < until: await process_frame
	if world.opening.playing: world.opening.letter.read.emit()
	client.rehearse({"type": "PassTown"})
	await client.rehearsed
	await secs(4.0)                    # the plates fade in, the sky comes up
	# 1. down the road: the board, its lamps and the gold diamond; the island says how far
	stand(town.board.front(26.0), town.board.front(0.0) + Vector3.UP * 2.0)
	await secs(3.0)
	await shot("a_road")
	# 2. in focus, a card lifted, the ring half full
	await press_at(town.board.front())
	await secs(1.6)
	var chai := -1
	for k in town.board._offers.size():
		if town.board._offers[k].quest == "errand:chai_round": chai = k
	town.board._choose(chai)
	town.board._armed = true
	Input.action_press("interact")
	await secs(0.45)
	await shot("b_focus")
	await event("QuestTaken")
	Input.action_release("interact")
	await secs(2.0)
	# 3. the first quest: the blast
	await press_at(town.place_at("table"))
	await event("QuestStepDone")
	await press_at(town.place_at("harbourmaster") + Vector3(1.5, 0, 0))
	await event("QuestDone")
	await secs(1.4)
	await shot("c_blast")
	while world.blast.playing: await process_frame
	await secs(1.0)
	# 4. a later one: paid, in the island and the wallet
	client.send({"type": "TakeQuest", "quest": "errand:letters"})
	await event("QuestTaken")
	await secs(1.0)
	await press_at(town.place_at("harbourmaster") + Vector3(1.5, 0, 0))
	await event("QuestStepDone")
	await secs(4.5)                    # the step's own moment goes by
	await press_at(town.place_at("homes"))
	await event("QuestDone")
	stand(town.place_at("homes"), town.place_at("homes") + Vector3(4.0, 0, -10.0))
	until = Time.get_ticks_msec() + 20000
	while not (str(load("res://scripts/ui/island.gd").up._m.get("head", "")).begins_with("Paid") and load("res://scripts/ui/island.gd").up._phase == 2) and Time.get_ticks_msec() < until: await process_frame
	await shot("d_paid")
	# 5. back up the road with nothing to say: the island's Next line, the diamond over the board
	var isl = load("res://scripts/ui/island.gd").up
	until = Time.get_ticks_msec() + 40000
	while not (isl._m.is_empty() and isl._q.is_empty()) and Time.get_ticks_msec() < until: await process_frame
	stand(town.board.front(30.0), town.board.front(0.0) + Vector3.UP * 2.0)
	await secs(2.0)
	await shot("e_next")
	quit(0)
