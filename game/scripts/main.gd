extends Node
## Starts the game: black, then the logo opening over the title, the Dhani Valley by default; `-- --world=quarter` runs the Old Quarter
## build instead. `-- --title-shots=<dir>` (dev) captures the opening and title at set moments, then quits; with `--title-skip` it skips
## the ferry's ride part way.

func _ready() -> void:
	var path := "res://scripts/valley/world.gd"
	for a in OS.get_cmdline_user_args():
		if a == "--world=quarter": path = "res://scripts/world/world.gd"
	var intro: BootIntro = null
	if TitleScreen.wanted():
		intro = BootIntro.new()
		add_child(intro)
		await get_tree().process_frame     # so the black is on screen before the town starts building
		await get_tree().process_frame
	var world := Node3D.new()
	world.name = "World"
	world.set_script(load(path))
	add_child(world)
	TitleScreen.skip_once = false
	if intro:
		world.title.begin()
		intro.opened.connect(world.title.enter)
		intro.play()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--title-shots="): _shots(a.trim_prefix("--title-shots="), world)

func _shot(dir: String, what: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, what])

func _shots(dir: String, world: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var skip := OS.get_cmdline_user_args().has("--title-skip")
	for at in [0.6, 3.2, 5.2, 10.0, 16.0, 22.0]:
		await get_tree().create_timer(maxf(at - (Time.get_ticks_msec() - t0) / 1000.0, 0.01)).timeout
		_shot(dir, "t%04d" % int(at * 100.0))
		print("at %.1f s: %d fps, %d draw calls, ride %.2f" % [at, Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), world.opening._ride_u])
		if skip and at == 5.2: world.title._skip_ride()
	while not world.title.active: await get_tree().process_frame
	print("menu up after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await get_tree().create_timer(3.0).timeout
	_shot(dir, "menu")
	print("items: ", world.title._items.map(func(i): return i.word), " ride ", world.opening._ride_u)
	world.title._go(world.title._chosen)
	for at in [0.5, 1.5, 3.0]:
		await get_tree().create_timer(at).timeout
		_shot(dir, "go%02d" % int(at * 10.0))
	print("step: ", world.opening.step, " playing ", world.opening.playing, " frozen ", world.player.frozen, " on deck ", world.opening.ferry.global_transform.affine_inverse() * world.player.global_position)
	world.player.global_position = world.opening.ferry.global_transform * Vector3(3.6, 0.05, 0.0)
	await get_tree().create_timer(1.0).timeout
	print("step after the rail: ", world.opening.step)
	_shot(dir, "ticket")
	get_tree().quit()
