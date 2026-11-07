extends SceneTree
## Dev: the minimap's painted map next to the town seen straight down, to check one against the other. Saves map.png (the
## minimap's whole image, 1 px a metre) and top.png (the town from overhead, the same rect) to --shots-to=<dir>, then quits.
##   tools/godot_d.sh --path game --resolution 1024x1024 -s res://dev/map_check.gd -- --arrive --player=NAME --shots-to=D:/dir

var dir := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-to="): dir = a.trim_prefix("--shots-to=")
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()

func _run() -> void:
	while current_scene == null or current_scene.get_node_or_null("World") == null or current_scene.get_node("World").get("hud") == null:
		await process_frame
	var world: Node = current_scene.get_node("World")
	var map: Control = world.hud._map
	map._tex.get_image().save_png(dir + "/map.png")
	var d = world.data
	var mid := Vector3(d.x0 + d.w * 0.5, 0.0, d.z0 + d.dep * 0.5)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(d.w, d.dep)
	cam.far = 2000.0
	world.add_child(cam)
	cam.global_position = mid + Vector3.UP * 600.0
	cam.look_at(mid, Vector3.FORWARD)     # north (-z) up, as the minimap
	cam.current = true
	world.ui.visible = false
	for i in 90: await process_frame
	get_root().get_texture().get_image().save_png(dir + "/top.png")
	print("map %d x %d m from (%.0f, %.0f)" % [d.w, d.dep, d.x0, d.z0])
	quit()
