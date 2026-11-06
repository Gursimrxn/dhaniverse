extends Node3D
## Kit showcase: a little river neighbourhood built only from Kit pieces.
## Run: godot --path game res://scenes/tests/kit_test.tscn -- --shots=D:/tmp/kit/x
## Saves x_<view>.png for each camera view, prints triangle counts, then quits.

const VIEWS := {
	"hero": [Vector3(13, 21, 27), Vector3(-1, 0, -3)],
	"market": [Vector3(11, 6.5, 8), Vector3(5, 1.6, -3.5)],
	"river": [Vector3(-15, 7.5, 17), Vector3(-4, 0, 6)],
	"houses": [Vector3(0, 9, 2), Vector3(-1, 3, -16)],
}

var cam: Camera3D


func _ready() -> void:
	_lighting()
	_ground()
	_layout()
	_report()
	cam = Camera3D.new()
	cam.fov = 42
	add_child(cam)
	_set_view("hero")
	var prefix := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			prefix = a.substr(8)
	if prefix != "":
		DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
		_shoot(prefix)


func _set_view(v: String) -> void:
	cam.position = VIEWS[v][0]
	cam.look_at(VIEWS[v][1])


func _shoot(prefix: String) -> void:
	for i in 60: await get_tree().process_frame
	for v in VIEWS:
		_set_view(v)
		for i in 12: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, v])
	get_tree().quit()


func _put(n: Node3D, pos: Vector3, yaw := 0.0) -> Node3D:
	n.position = pos
	n.rotation_degrees.y = yaw
	add_child(n)
	return n


func _report() -> void:
	var pieces := {
		"house(seed1)": Kit.house({"seed": 1}), "house(seed4,2fl,pergola)": Kit.house({"seed": 4, "floors": 2, "pergola": true}),
		"market_hall(3 bays)": Kit.market_hall(), "produce_stall": Kit.produce_stall({"sign": true}),
		"lamp": Kit.lamp(), "bench": Kit.bench(), "cafe_table": Kit.cafe_table({"chairs": 4}),
		"planter": Kit.planter(), "stair(10)": Kit.stair({"steps": 10}), "awning": Kit.awning(),
		"pergola": Kit.pergola(), "dock": Kit.dock(), "rowboat": Kit.rowboat(), "chalkboard": Kit.chalkboard(),
		"crate": Kit.crate(), "wall(10m x1.8)": Kit.retaining_wall(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)]), 1.8),
		"fence rope(10m)": Kit.fence(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)]), "rope"),
		"fence iron(10m)": Kit.fence(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)]), "iron"),
		"fence timber(10m)": Kit.fence(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)]), "timber"),
	}
	for k in pieces:
		var n: Node3D = pieces[k]
		var mi: MeshInstance3D = n.get_node("Mesh")
		print("KIT %-26s tris=%5d surfaces=%d" % [k, n.get_meta("tris"), mi.mesh.get_surface_count()])
		n.free()


# --- environment ----------------------------------------------------------------------
func _lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -135, 0)
	sun.light_color = Brand.SUN
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.82
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_dir", -sun.global_transform.basis.z)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9cc3e0")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _ground() -> void:
	var mb := MeshUtil.new()
	var paving := Brand.PATH
	var grass := Color("5f9e45")
	mb.box("solid", MeshUtil.xf(Vector3(0, -0.5, -2)), Vector3(60, 1, 16.2), paving)          # plaza z -10..6
	mb.box("solid", MeshUtil.xf(Vector3(0, 0.9, -26)), Vector3(60, 1.8, 31.4), grass)          # terrace
	mb.box("solid", MeshUtil.xf(Vector3(0, 1.81, -11.5)), Vector3(60, 0.02, 2.4), paving)      # terrace walk
	mb.box("solid", MeshUtil.xf(Vector3(0, -2.1, 14.5)), Vector3(60, 1, 17), Color("3f6e5a"))  # river bed
	mb.box("solid", MeshUtil.xf(Vector3(0, -0.6, 30)), Vector3(60, 1.2, 14), grass)            # far bank
	for x in [-18.0, -14.0, 14.0, 18.0]:
		mb.box("solid", MeshUtil.xf(Vector3(x, 0.01, 2.5)), Vector3(3.2, 0.02, 3.5), grass)   # lawn beds
	# shrubs hugging walls and bank so pieces sit in greenery like the reference
	var r := RandomNumberGenerator.new()
	r.seed = 5
	mb.sway = 0.2
	for i in 90:
		var p: Vector3
		match i % 3:
			0: p = Vector3(r.randf_range(-24, 24), 0.0, r.randf_range(-9.9, -9.2))
			1: p = Vector3(r.randf_range(-24, 24), 0.0, r.randf_range(5.6, 6.0))
			_: p = Vector3(r.randf_range(-24, 24), 0.0, r.randf_range(23.2, 26))
		if absf(p.x + 6) < 2.0 and p.z < 0 or absf(p.x + 4) < 2.0 and p.z > 0 and p.z < 10 or absf(p.x - 8) < 1.6 and p.z > 0 and p.z < 10:
			continue
		var s := r.randf_range(0.35, 0.7)
		mb.sphere("leaf", MeshUtil.xf(p + Vector3(0, s * 0.5, 0), Vector3(0, r.randf() * 90, 0), Vector3(1.2, 0.85, 1)), s, Kit._leaf(r), 6, 4)
	add_child(mb.to_node("Ground"))
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 17)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.62, 0.62, 0.78)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.15
	water.material_override = wm
	water.position = Vector3(0, -0.55, 14.5)
	add_child(water)


func _layout() -> void:
	var P := func(a: Array) -> PackedVector3Array: return PackedVector3Array(a)
	# river bank: stone wall with a gap for stairs down to the water
	_put(Kit.retaining_wall(P.call([Vector3(-30, -1.6, 6.28), Vector3(6.6, -1.6, 6.28)]), 1.6, {"seed": 1}), Vector3.ZERO)
	_put(Kit.retaining_wall(P.call([Vector3(9.4, -1.6, 6.28), Vector3(30, -1.6, 6.28)]), 1.6, {"seed": 2}), Vector3.ZERO)
	_put(Kit.stair({"steps": 9, "width": 2.0, "railing": "timber", "seed": 3}), Vector3(8, -1.6, 6.0 + 1.44), 180)
	_put(Kit.fence(P.call([Vector3(-24, 0.08, 6.2), Vector3(-6.2, 0.08, 6.2)]), "rope"), Vector3.ZERO)
	_put(Kit.fence(P.call([Vector3(-1.8, 0.08, 6.2), Vector3(6.4, 0.08, 6.2)]), "rope"), Vector3.ZERO)
	_put(Kit.fence(P.call([Vector3(9.6, 0.08, 6.2), Vector3(24, 0.08, 6.2)]), "rope"), Vector3.ZERO)
	_put(Kit.dock({"length": 6.0, "width": 2.6}), Vector3(-4, -0.55, 9.4))
	_put(Kit.rowboat({"seed": 2}), Vector3(-1.4, -0.55, 10.4), 12)

	# plaza
	_put(Kit.market_hall({"seed": 7}), Vector3(5, 0, -4.6))
	_put(Kit.produce_stall({"seed": 3, "awning_style": "coral", "sign": true}), Vector3(-4.5, 0, -5.5), 10)
	_put(Kit.awning({"style": "gold", "width": 2.0}), Vector3(15.5, 0, -6.5), -20)
	_put(Kit.crate({"seed": 4, "good": "orange"}), Vector3(15.3, 0, -5.6))
	_put(Kit.crate({"seed": 5, "good": "greens"}), Vector3(15.9, 0, -5.4), 20)
	_put(Kit.chalkboard({"seed": 9}), Vector3(14, 0, -4.8), 30)
	for i in 3:
		_put(Kit.cafe_table({"seed": i, "parasol_style": ["teal", "coral", "teal"][i]}), [Vector3(-12, 0, -3), Vector3(-9, 0, -0.2), Vector3(-13.5, 0, 1.2)][i])
	for p in [Vector3(-7, 0, 4.6), Vector3(2.5, 0, 4.6), Vector3(13, 0, 4.6), Vector3(-2.8, 0, -8.6), Vector3(-15.5, 0, -6.5)]:
		_put(Kit.lamp(), p)
	_put(Kit.bench({"seed": 1}), Vector3(-0.5, 0, 4.9))
	_put(Kit.bench({"seed": 2}), Vector3(-10, 0, 4.9))
	_put(Kit.bench({"seed": 3, "length": 1.5}), Vector3(-7.6, 0, -8.8), 0)
	for i in 5:
		_put(Kit.planter({"seed": i + 1}), [Vector3(-6.5, 0, -0.5), Vector3(-2.5, 0, 0.5), Vector3(13.6, 0, 0.2), Vector3(-10.6, 0, -9.2), Vector3(-1.2, 0, -9.2)][i], [0, 90, 90, 0, 0][i])

	# upper terrace: stone wall, stairs, iron railing, houses
	_put(Kit.retaining_wall(P.call([Vector3(-30, 0, -10.3), Vector3(-7.45, 0, -10.3)]), 1.8, {"seed": 4}), Vector3.ZERO)
	_put(Kit.retaining_wall(P.call([Vector3(-4.55, 0, -10.3), Vector3(30, 0, -10.3)]), 1.8, {"seed": 5}), Vector3.ZERO)
	_put(Kit.stair({"steps": 10, "width": 2.2, "railing": "iron", "seed": 6}), Vector3(-6, 0, -10.03 + 1.6))
	_put(Kit.fence(P.call([Vector3(-24, 1.93, -10.3), Vector3(-7.5, 1.93, -10.3)]), "iron"), Vector3.ZERO)
	_put(Kit.fence(P.call([Vector3(-4.5, 1.93, -10.3), Vector3(-0.5, 1.93, -10.3)]), "iron"), Vector3.ZERO)
	_put(Kit.fence(P.call([Vector3(2.5, 1.93, -10.3), Vector3(24, 1.93, -10.3)]), "timber"), Vector3.ZERO)
	for i in 5:
		_put(Kit.house({"seed": i + 1, "pergola": i % 2 == 0}), Vector3(-19 + i * 9.5, 1.8, -17))
	_put(Kit.pergola({"seed": 3, "width": 3.2, "depth": 2.4}), Vector3(1, 1.8, -12.6))
