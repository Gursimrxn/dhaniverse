extends SceneTree
## Dev: a picture of every screen a player meets after the letter, against a --debug server: the HUD in the square, the five phone
## pages, the mentor, the paper, settings, the food menu and the chest opening. Saves PNGs to --shots-to=<dir>, then quits.
##   tools/godot_d.sh --path game --resolution 1440x810 -s res://dev/ui_tour.gd -- --arrive --player=NAME --shots-to=D:/dir

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

func _run() -> void:
	while current_scene == null or current_scene.get_node_or_null("World") == null or current_scene.get_node("World").get("dhaniverse") == null:
		await process_frame
	world = current_scene.get_node("World")
	world._capturing = true
	world.cinematic_on = false
	client = world.client
	town = world.dhaniverse
	client.event.connect(func(e: Dictionary): _events.append(e))
	while not client.up: await process_frame
	var until := Time.get_ticks_msec() + 15000
	while world.opening.playing and world.opening.step != "letter" and Time.get_ticks_msec() < until: await process_frame
	if world.opening.playing: world.opening.letter.read.emit()
	client.rehearse({"type": "PassTown"})
	await client.rehearsed
	await secs(5.0)
	stand(town.place_at("square") + Vector3(0, 0, 6), town.place_at("square"))
	await secs(3.0)
	await shot("01_hud")
	for page in ["wallet", "quests", "feed", "town", "me"]:
		world.phone.open_page(page)
		await secs(1.2)
		await shot("02_phone_" + page)
	world.phone.toggle()
	await secs(0.8)
	world.mentor.toggle()
	await secs(2.5)
	await shot("03_mentor")
	world.mentor.toggle()
	await secs(0.6)
	world.morning_paper.toggle()
	await secs(1.0)
	await shot("04_paper")
	world.morning_paper.toggle()
	await secs(0.6)
	world.pause.open()
	await secs(1.0)
	await shot("05_pause")
	world.pause.close()
	await secs(0.8)
	world.settings.open_at(4)
	await secs(1.2)
	await shot("05_settings_access")
	world.settings.close()
	await secs(1.0)
	stand(world.FOOD_COUNTER_AT + Vector3(0, 0, 1.6), world.FOOD_COUNTER_AT)
	await secs(1.5)
	world.food_counter.food_menu.open("thali")
	await secs(1.2)
	await shot("06_food")
	world.food_counter.food_menu.close()
	await secs(0.6)
	client.rehearse({"type": "ReadyChest"})
	await client.rehearsed
	stand(town.place_at("homes"), town.chest.global_position)
	await secs(2.0)
	await shot("07_chest_ready")
	town.chest.open_daily()
	await event("ChestOpened")
	await secs(1.3)
	await shot("08_chest_open")
	await secs(2.5)
	await shot("09_chest_sheet")
	quit(0)
