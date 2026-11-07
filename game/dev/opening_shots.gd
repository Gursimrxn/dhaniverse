extends SceneTree
## Dev: a new player's way in, pictured: the title's "A new life", the shot over the boat with the name ticket, the Town Pass
## gate (stamped with a rehearsal pass), and the landing on the deck. Needs a --debug server and no saved name, so run it with
## its own user folder (APPDATA pointed somewhere empty). Saves PNGs to --shots-to=<dir>, then quits.

var dir := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-to="): dir = a.trim_prefix("--shots-to=")
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("shot ", name)

func secs(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	while current_scene == null or current_scene.get_node_or_null("World") == null or current_scene.get_node("World").get("title") == null:
		await process_frame
	var world: Node = current_scene.get_node("World")
	while not world.title._may_skip: await process_frame
	world.title._skip_ride()     # any key, as a player would
	while not world.title.active: await process_frame
	await secs(1.0)
	await shot("1_title")
	world.title._new_life()
	await secs(0.8)
	await shot("2_easing")
	await secs(2.5)
	await shot("3_name")
	world.opening.ticket._submit("open%d" % (Time.get_ticks_msec() % 100000))
	while not world.pass_gate.is_open() and world.opening.step != "ashore": await process_frame
	await secs(1.2)
	await shot("4_gate")
	if world.pass_gate.is_open(): world.client.rehearse({"type": "PassTown"})
	await secs(1.0)
	await shot("5_stamped")
	while world.opening.step != "ashore": await process_frame
	await secs(0.6)
	await shot("6_landed")
	quit()
