extends Node3D
## Living-world test bed: meadow, stone path loop, bench, market stall, pond, trees,
## 8 villagers + ambient life.   -- --shots=D:/tmp/life/x  saves screenshots then quits.

var cam: Camera3D
var director: LifeDirector
var path_pts: Array[Vector3] = []

func _ready() -> void:
	RenderingServer.global_shader_parameter_set("player_pos", Vector3(0, -100, 0))
	_lighting()
	_ground()
	# rounded-rectangle stroll loop
	for i in 14:
		var a := TAU * i / 14.0
		path_pts.append(Vector3(cos(a) * 9.0, 0, sin(a) * 5.5))
	_path()
	_grass()
	var bench_pos := Vector3(0, 0, -7.4)
	_bench(bench_pos)
	var stall_pos := Vector3(11.8, 0, 1.5)
	_stall(stall_pos)
	var trees := [Vector3(-6, 0, -8.5), Vector3(5.5, 0, 8.6), Vector3(-12.5, 0, 3)]
	for i in trees.size(): _tree(trees[i], i)
	var pond := Vector3(-4, 0, 9.5)
	_pond(pond)
	var flowers := [Vector3(-2.5, 0, -8.6), Vector3(3, 0, -8.2), Vector3(-10, 0, -4), Vector3(8, 0, 6.8), Vector3(-1, 0, 7.4)]
	for f in flowers: _flower_bed(f)

	director = LifeDirector.new()
	director.height_at = func(_x: float, _z: float) -> float: return 0.0
	add_child(director)
	director.setup({
		"count": 8, "seed": 4,
		"waypoints": path_pts,
		"points_of_interest": [
			{"pos": bench_pos + Vector3(0, 0, 0.2), "kind": "sit", "facing": 0.0, "slots": 2, "spacing": 0.8},
			{"pos": stall_pos + Vector3(-1.05, 0, 0), "kind": "shop", "facing": PI * 0.5, "slots": 2, "spacing": 0.9},
			{"pos": Vector3(-7, 0, 0.5), "kind": "chat"},
			{"pos": pond + Vector3(1.0, 0, -3.3), "kind": "look", "facing": pond},
		],
	})
	Ambient.build(self, {"flower_spots": flowers, "tree_spots": trees, "water_center": pond,
		"bounds": AABB(Vector3(-16, 0, -12), Vector3(32, 11, 24)), "canopy_height": 3.6})

	cam = Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	_view(Vector3(0, 0.5, 0), 20.0, -35.0, 26.0)
	var tris := 0
	for v in director.villagers: tris = maxi(tris, v.tris)
	print("villager max tris (base, outline pass doubles): ", tris)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].begins_with("--shots="):
		_capture(args[0].trim_prefix("--shots="))

func _view(focus: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0))
	cam.global_transform = Transform3D(b, focus + b.z * dist)

func _capture(prefix: String) -> void:
	DirAccess.make_dir_recursive_absolute(prefix.get_base_dir())
	for i in 120: await get_tree().process_frame
	var views := [
		["high", Vector3(0, 0.5, 0), 20.0, -35.0, 26.0, 150],
		["high2", Vector3(-1, 0.5, 1), -35.0, -38.0, 24.0, 200],
		["close", Vector3(4, 0.8, -4), 30.0, -24.0, 10.0, 120],
	]
	for v in views:
		_view(v[1], v[2], v[3], v[4])
		for i in v[5]: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, v[0]])
	get_tree().quit()

# --- set dressing ------------------------------------------------------------------
func _toon(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

func _mesh(mesh: Mesh, c: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _toon(c)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi

func _box(s: Vector3, c: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = s
	return _mesh(b, c, pos, rot)

func _lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -140, 0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 2.5
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.8
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
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
	env.ambient_light_color = Color("a8c6dc")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Brand.FOG
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	_mesh(pm, Color("4f8a3c"), Vector3.ZERO)

func _path_dist(x: float, z: float) -> float:
	var best := INF
	var p := Vector2(x, z)
	for i in path_pts.size():
		var a := Vector2(path_pts[i].x, path_pts[i].z)
		var b := Vector2(path_pts[(i + 1) % path_pts.size()].x, path_pts[(i + 1) % path_pts.size()].z)
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

func _path() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := path_pts.size()
	for i in n:
		var a := path_pts[i]
		var b := path_pts[(i + 1) % n]
		var c := path_pts[(i + 2) % n]
		var na := (b - path_pts[(i - 1 + n) % n]).normalized().cross(Vector3.UP) * 1.25
		var nb := (c - a).normalized().cross(Vector3.UP) * 1.25
		var y := Vector3(0, 0.02, 0)
		for v in [a - na, a + na, b + nb, a - na, b + nb, b - nb]: st.add_vertex(v + y)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _toon(Brand.PATH)
	add_child(mi)
	# plaza patches under the POIs
	var disc := CylinderMesh.new(); disc.top_radius = 1.6; disc.bottom_radius = 1.6; disc.height = 0.03
	_mesh(disc, Brand.PATH, Vector3(-7, 0.01, 0.5))

func _grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	var sampler := func(x: float, z: float) -> Array:
		var d := _path_dist(x, z)
		var keep := smoothstep(1.35, 2.1, d)
		if Vector2(x + 7, z - 0.5).length() < 2.0: keep = 0.0
		if Vector2(x + 4, z - 9.5).length() < 3.0: keep = 0.0
		if absf(x - 11.8) < 1.6 and absf(z - 1.5) < 2.0: keep = 0.0
		if absf(z + 7.8) < 0.8 and absf(x) < 1.6: keep = 0.0
		return [0.0, keep]
	var n := GrassBuilder.build(self, mat, sampler, -18, -14, 36, 30, 7.0, 3)
	print("grass clumps: ", n)

func _bench(p: Vector3) -> void:
	var wood := Brand.TIMBER
	_box(Vector3(1.9, 0.07, 0.45), wood, p + Vector3(0, 0.45, 0.0))
	_box(Vector3(1.9, 0.38, 0.06), wood.darkened(0.1), p + Vector3(0, 0.72, -0.22), Vector3(-0.15, 0, 0))
	for sx in [-0.8, 0.8]:
		_box(Vector3(0.08, 0.45, 0.4), Color("3d3a3e"), p + Vector3(sx, 0.22, 0))

func _stall(p: Vector3) -> void:
	_box(Vector3(1.0, 0.85, 2.4), Brand.TIMBER, p + Vector3(0, 0.42, 0))
	for z in [-1.1, 1.1]:
		for x in [-0.45, 0.45]:
			_box(Vector3(0.08, 2.3, 0.08), Brand.TIMBER.darkened(0.2), p + Vector3(x, 1.15, z))
	for i in 6:   # striped awning
		_box(Vector3(1.5, 0.05, 0.42), Brand.CORAL if i % 2 == 0 else Brand.SNOW, p + Vector3(-0.15, 2.3 - 0.0, -1.05 + i * 0.42), Vector3(0, 0, 0.22))
	var fruit := [Color("e8573f"), Color("f2b632"), Color("8fbf4a"), Color("f08a3c")]
	for i in 4:
		_box(Vector3(0.7, 0.18, 0.5), Color("b98a52"), p + Vector3(-0.05, 0.94, -0.85 + i * 0.57))
		var s := SphereMesh.new(); s.radius = 0.2; s.height = 0.22; s.radial_segments = 10; s.rings = 4
		_mesh(s, fruit[i], p + Vector3(-0.05, 1.04, -0.85 + i * 0.57))

func _tree(p: Vector3, i: int) -> void:
	var t := TreeBuilder.build("broad", 31 + i * 7)
	var bark := ShaderMaterial.new(); bark.shader = load("res://shaders/bark.gdshader")
	var leaf := ShaderMaterial.new(); leaf.shader = load("res://shaders/leaves.gdshader")
	leaf.set_shader_parameter("shade_col", Color("1d4a38"))
	leaf.set_shader_parameter("mid_col", Color("4f9a3e"))
	leaf.set_shader_parameter("light_col", Color("b5dc5c"))
	leaf.set_shader_parameter("card_size", 1.25)
	for pair in [[t.bark, bark], [t.leaves, leaf]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0]
		mi.material_override = pair[1]
		mi.position = p
		mi.scale = Vector3.ONE * 0.9
		add_child(mi)

func _pond(p: Vector3) -> void:
	var d := CylinderMesh.new(); d.top_radius = 3.0; d.bottom_radius = 3.0; d.height = 0.04; d.radial_segments = 32
	_mesh(d, Color("8f8b84"), p + Vector3(0, 0.01, 0))
	var w := CylinderMesh.new(); w.top_radius = 2.6; w.bottom_radius = 2.6; w.height = 0.04; w.radial_segments = 32
	var m := _mesh(w, Color("2fa3a0"), p + Vector3(0, 0.03, 0))
	(m.material_override as StandardMaterial3D).roughness = 0.15
	(m.material_override as StandardMaterial3D).specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

func _flower_bed(p: Vector3) -> void:
	var cols := [Color("f4a6bd"), Color("fff6e0"), Color("f2b632"), Color("b08ad8")]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.x * 13 + p.z * 7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var s := SphereMesh.new(); s.radius = 0.08; s.height = 0.12; s.radial_segments = 6; s.rings = 3
	mm.mesh = s
	mm.instance_count = 26
	for i in 26:
		var o := Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.25, 0.45), rng.randf_range(-0.6, 0.6))
		mm.set_instance_transform(i, Transform3D(Basis(), p + o))
		mm.set_instance_color(i, cols[rng.randi() % cols.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := _toon(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	mmi.material_override = m
	add_child(mmi)
