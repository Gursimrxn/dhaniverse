extends SceneTree
## Dev: the quest crate on its own, pictured: it drops beside the player, then opens with its prizes flying to the plates. No server
## step is needed for the pictures: the crate is dropped and opened by hand. Saves crate_N.png to --shots-to=<dir>, then quits.
##   tools/godot_d.sh --path game --resolution 1440x810 -s res://dev/crate_check.gd -- --arrive --player=NAME --shots-to=D:/dir

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

func _run() -> void:
	while current_scene == null or current_scene.get_node_or_null("World") == null or current_scene.get_node("World").get("quest_crate") == null:
		await process_frame
	var world: Node = current_scene.get_node("World")
	while world.client.you.is_empty(): await process_frame
	for i in 120: await process_frame
	while world.blast.playing or world.pass_gate.is_open(): await process_frame
	var crate = world.quest_crate
	crate._drop("brass")
	print("crate at ", crate.global_position, " player at ", world.player.global_position, " visible ", crate.visible)
	await create_timer(1.0).timeout
	await shot("crate_1_dropped")
	crate._open({"contents": {"energy": 20, "tickets": 2, "voucher": false, "golden_drop": 50000}})
	await create_timer(0.6).timeout
	await shot("crate_2_open")
	await create_timer(0.7).timeout
	await shot("crate_3_flying")
	await create_timer(1.0).timeout
	await shot("crate_4_golden")
	quit()
