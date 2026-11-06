class_name PortDressing
extends Node3D
## The river and the port: the first thing anyone sees, for as long as the ferry takes. Reeds and cattails along both waterlines, lily pads in the
## shallows, long grass and flowers on the banks, boats and buoys riding the water, gulls and ducks, smoke, a low mist at dawn, and a board on the
## jetty with the town's real food price and day. One batch per kind of plant, the props merged by material, and the gulls and ducks in a batch
## each, so all of it is a few dozen draws. Props: tools/blender/build_port.py. The tree line goes through world.gd's own planting: tree_line().

const PORT := preload("res://assets/market/port.glb")
const PLANT_SHADER := preload("res://shaders/valley/plant.gdshader")
const AREA := Rect2(-175.0, -60.0, 120.0, 190.0)    # the river's reach the ferry shows
const SEEN_FROM_X := -40.0          # m: east of this, the river's out of sight and none of its plants are drawn
const STEP := 0.55                 # m between places tried
const WATER_Y := -1.2
const REEDS_FROM := -1.3           # m from the water's edge (under 0: in the water)
const REEDS_TO := 0.7
const LILY_FROM := -6.5
const LILY_TO := -1.6
const GRASS_TO := 24.0
const FLOWERS_TO := 18.0
const JETTY_CLEAR := Rect2(-126.0, 45.0, 23.5, 8.0)
const FERRY_ROUTE_WIDE := 4.5      # m each side of the river's middle kept clear of lilies
const BOB := 0.035                 # m
const BOARD_AT := Vector3(-122.7, -0.55, 46.85)
const BOARD_SIZE := Vector3(1.5, 1.0, 0.06)
const BOARD_EVERY := 1.0           # s between checking the numbers
const MIST_MODES := ["dawn"]
const GULLS := 7
const DUCKS := 6

var world: Node3D
var client: TownClient
var _boats: Node3D                 # they ride the water together
var _boats_y := 0.0
var _plants: Node3D
var _sails: Node3D
var _gulls: Array = []             # {centre, radius, height, speed, at}
var _ducks: Array = []             # {centre, radius, speed, at}
var _gull_batch: MultiMesh
var _duck_batch: MultiMesh
var _mist: MeshInstance3D
var _price: Label3D
var _day: Label3D
var _board_in := 0.0
var _rng := RandomNumberGenerator.new()

## Where trees go along the river, for world.gd to plant with the rest: [kind, x, z].
static func tree_line(data: WorldData) -> Array:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 19
	var out: Array = []
	var taken: Array = []
	# a real line along the banks, thicker as it climbs away from the water
	var z := -90.0
	while z < 132.0:
		var x := -174.0
		while x < -55.0:
			var p := Vector2(x + rnd.randf_range(-2.5, 2.5), z + rnd.randf_range(-2.5, 2.5))
			var sd := data.water_sd(p)
			var want := 0.0
			if sd > 7.0 and sd < 14.0: want = 0.55
			elif sd >= 14.0 and sd < 34.0: want = 0.5
			if want > 0.0 and rnd.randf() < want and data.pave_dist(p) > 2.5 and not JETTY_CLEAR.grow(6.0).has_point(p) and not Rect2(-103.0, 38.0, 22.0, 22.0).has_point(p) and not Rect2(-147.0, 38.0, 12.0, 12.0).has_point(p):
				var clear := true
				for q in taken:
					if p.distance_to(q) < 5.0: clear = false
				if clear:
					taken.append(p)
					var r := rnd.randf()
					out.append(["pine" if r < 0.42 else ("oak" if r < 0.72 else ("young" if r < 0.86 else "cypress")), p.x, p.y])
			x += 5.0
		z += 5.0
	# big ones right at the water's edge, in the ferry's view
	for b in [[-112.0, 33.0], [-119.0, 72.0], [-110.5, 80.0], [-147.0, 58.0], [-150.0, 22.0], [-128.0, -6.0]]:
		out.append(["oak", b[0], b[1]])
	return out

func setup(on: Node3D) -> void:
	world = on
	client = world.client if world.get("client") else null
	_rng.seed = 23
	_plant()
	_props()
	_life()

# --- plants, in meshes of their own; UV.y is how far up a vertex is ---------------------------------------------------------------
static func _blade(st: SurfaceTool, base: Vector3, tip: Vector3, width: float, col: Color, tip_col: Color) -> void:
	var side := (tip - base).cross(Vector3(0.3, 0.1, 1.0)).normalized() * width
	var mid := base.lerp(tip, 0.55) + Vector3(0.0, 0.0, 0.0)
	var pts := [[base - side, 0.0, col], [base + side, 0.0, col], [mid + side * 0.55, 0.55, col.lerp(tip_col, 0.5)], [mid - side * 0.55, 0.55, col.lerp(tip_col, 0.5)], [tip, 1.0, tip_col]]
	for i in [0, 1, 2, 0, 2, 3, 3, 2, 4]:
		st.set_color(pts[i][2])
		st.set_uv(Vector2(0.0, pts[i][1]))
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[i][0])

func _reed_mesh(cattails: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 3 if cattails else 4
	var green := Color("5d7f43")
	var pale := Color("a9b56a")
	for i in 9:
		var a := rnd.randf() * TAU
		var r := rnd.randf() * 0.22
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := rnd.randf_range(0.9, 1.65)
		var lean := Vector3(rnd.randf_range(-0.22, 0.22), 0.0, rnd.randf_range(-0.22, 0.22))
		_blade(st, base, base + lean + Vector3.UP * h, 0.022, green, pale)
		if cattails and i % 3 == 0:     # a brown head on a stalk
			var top := base + lean * 0.8 + Vector3.UP * (h * 0.92)
			var head := Color("5a3c26")
			for k in 2:
				var sw := Vector3(0.017, 0.0, 0.0) if k == 0 else Vector3(0.0, 0.0, 0.017)
				var quad := [[top - sw, 0.8], [top + sw, 0.8], [top + sw * 0.5 + Vector3.UP * 0.15, 0.9], [top - sw * 0.5 + Vector3.UP * 0.15, 0.9]]
				for j in [0, 1, 2, 0, 2, 3]:
					st.set_color(head)
					st.set_uv(Vector2(0.0, quad[j][1]))
					st.set_normal(Vector3.UP)
					st.add_vertex(quad[j][0])
	return st.commit()

func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 6
	for i in 7:
		var a := rnd.randf() * TAU
		var base := Vector3(cos(a), 0.0, sin(a)) * rnd.randf() * 0.2
		var tip := base + Vector3(rnd.randf_range(-0.2, 0.2), rnd.randf_range(0.42, 0.78), rnd.randf_range(-0.2, 0.2))
		_blade(st, base, tip, 0.03, Color("4e7a34"), Color("9db45a"))
	return st.commit()

func _lily_mesh(flower: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color("3f6e45")
	var n := 10
	for i in n:
		if i == 0: continue             # the notch in a lily pad
		var a0 := float(i) / n * TAU
		var a1 := float(i + 1) / n * TAU
		for v in [Vector3.ZERO, Vector3(cos(a0), 0.0, sin(a0)) * 0.24, Vector3(cos(a1), 0.0, sin(a1)) * 0.24]:
			st.set_color(green)
			st.set_uv(Vector2.ZERO)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	if flower:
		for k in 6:
			var a := k * TAU / 6.0
			var tip := Vector3(cos(a), 0.14, sin(a)) * Vector3(0.1, 1.0, 0.1)
			var s := Vector3(-sin(a), 0.0, cos(a)) * 0.035
			for v in [Vector3.UP * 0.03 - s, Vector3.UP * 0.03 + s, tip]:
				st.set_color(Color("f4d6dc"))
				st.set_uv(Vector2.ZERO)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	return st.commit()

func _flower_mesh(col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blade(st, Vector3.ZERO, Vector3.UP * 0.34, 0.012, Color("4f7f3a"), Color("6c9a4a"))
	for k in 3:
		var a: float = k * PI / 3.0
		var dx := Vector3(cos(a), 0.0, sin(a)) * 0.065
		var dz := Vector3(-sin(a), 0.0, cos(a)) * 0.026
		var h := Vector3.UP * 0.35
		for v in [h - dx - dz, h + dx - dz, h + dx + dz, h - dx - dz, h + dx + dz, h - dx + dz]:
			st.set_color(col)
			st.set_uv(Vector2(0.0, 1.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()

func _plant() -> void:
	var kinds := {"reed": [_reed_mesh(false), 0.09], "cattail": [_reed_mesh(true), 0.09], "tuft": [_tuft_mesh(), 0.1], "lily": [_lily_mesh(false), 0.0], "lily_f": [_lily_mesh(true), 0.0],
		"yellow": [_flower_mesh(Color("f2c84b")), 0.04], "pink": [_flower_mesh(Color("e59aac")), 0.04], "white": [_flower_mesh(Color("f1eee6")), 0.04], "violet": [_flower_mesh(Color("a68ad0")), 0.04]}
	var batches := {}                  # kind -> transforms
	var add := func(kind: String, p: Vector2, y: float, size: float):
		if not batches.has(kind): batches[kind] = []
		batches[kind].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * size), Vector3(p.x, y, p.y)))
	var data: WorldData = world.data
	var x := AREA.position.x
	while x < AREA.end.x:
		var z := AREA.position.y
		while z < AREA.end.y:
			var p := Vector2(x + _rng.randf_range(-0.25, 0.25), z + _rng.randf_range(-0.25, 0.25))
			z += STEP
			if JETTY_CLEAR.has_point(p): continue
			var sd := data.water_sd(p)
			if sd > GRASS_TO: continue
			var patch := sin(p.x * 0.19) * cos(p.y * 0.23) + sin((p.x + p.y) * 0.07)      # they grow in stands, not evenly
			var h := data.height(p)
			if sd >= REEDS_FROM and sd <= REEDS_TO:
				if patch > -0.55 and _rng.randf() < 0.42: add.call("cattail" if _rng.randf() < 0.3 else "reed", p, maxf(h, WATER_Y - 0.25), _rng.randf_range(0.8, 1.25))
			elif sd >= LILY_FROM and sd <= LILY_TO:
				if patch > 0.55 and _rng.randf() < 0.09 and absf(sd) < 11.0 - FERRY_ROUTE_WIDE: add.call("lily_f" if _rng.randf() < 0.14 else "lily", p, WATER_Y + 0.015, _rng.randf_range(0.8, 1.5))
			elif sd > REEDS_TO and data.pave_dist(p) > 1.2:
				if patch > -0.2 and _rng.randf() < 0.3 * (1.0 - sd / (GRASS_TO * 1.4)): add.call("tuft", p, h - 0.01, _rng.randf_range(0.85, 1.5))
				if sd < FLOWERS_TO and patch > 0.75 and _rng.randf() < 0.18:
					add.call(["yellow", "pink", "white", "violet"][int(absf(sin(floorf(p.x / 9.0) * 12.9 + floorf(p.y / 9.0) * 78.2)) * 3.99)], p, h - 0.01, _rng.randf_range(0.9, 1.3))
		x += STEP
	_plants = Node3D.new()
	add_child(_plants)
	var total := 0
	for kind in batches:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = kinds[kind][0]
		mm.instance_count = batches[kind].size()
		for i in batches[kind].size(): mm.set_instance_transform(i, batches[kind][i])
		total += batches[kind].size()
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := ShaderMaterial.new()
		m.shader = PLANT_SHADER
		m.set_shader_parameter("sway", kinds[kind][1])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_plants.add_child(mi)
	print("port: %d plants in %d batches" % [total, batches.size()])

# --- props -----------------------------------------------------------------------------------------------------------------------
func _props() -> void:
	var model: Node3D = PORT.instantiate()
	add_child(model)
	for node in model.get_children():
		if String(node.name) == "Windmill_sails":
			_sails = node
			world._town_materials(node)
	var boats := _merged(model, func(top: String): return top.begins_with("Boat_"))
	var rest := _merged(model, func(top: String): return not top.begins_with("Boat_") and top != "Windmill_sails")
	for node in model.get_children():
		if node != _sails and node is Node3D and not (node.find_children("*", "StaticBody3D", true, false).size() > 0 or node is StaticBody3D): node.queue_free()
	_boats = boats
	add_child(boats)
	add_child(rest)
	# the sign board: the town's economy, from the first shot
	var root := Node3D.new()
	add_child(root)
	root.position = BOARD_AT
	root.rotation.y = -PI * 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Brand.PLATE
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = BOARD_SIZE
	panel.mesh = pm
	panel.material_override = dark
	panel.position = Vector3(0.0, 1.45, 0.0)
	root.add_child(panel)
	for sx in [-0.6, 0.6]:
		var post := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.07, 0.95, 0.07)
		post.mesh = cm
		post.material_override = dark
		post.position = Vector3(sx, 0.47, 0.0)
		root.add_child(post)
	var head := _label(Brand.FONT_BODY, 30, 0.0034)
	head.text = "TALLYPORT HARBOUR"
	head.position = Vector3(0.0, 1.8, 0.04)
	root.add_child(head)
	_price = _label(Brand.FONT_EDITORIAL, 56, 0.0034)
	_price.position = Vector3(0.0, 1.53, 0.04)
	root.add_child(_price)
	_day = _label(Brand.FONT_EDITORIAL, 56, 0.0034)
	_day.position = Vector3(0.0, 1.22, 0.04)
	root.add_child(_day)
	_price.text = "Food  ·"
	_day.text = "Day  ·"

## Everything under these top-level nodes as one mesh, one surface per material: however many pieces, a handful of draws.
func _merged(model: Node3D, wanted: Callable) -> MeshInstance3D:
	var tools := {}                    # material -> SurfaceTool
	for top in model.get_children():
		if not wanted.call(String(top.name)): continue
		var parts: Array = top.find_children("*", "MeshInstance3D", true, false)
		if top is MeshInstance3D: parts.append(top)
		for mi in parts:
			var xf := Transform3D.IDENTITY
			var p: Node = mi
			while p != model and p is Node3D:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			for i in (mi as MeshInstance3D).mesh.get_surface_count():
				var mat: Material = world._town_mat((mi as MeshInstance3D).mesh, i)
				if not tools.has(mat):
					tools[mat] = SurfaceTool.new()
					tools[mat].begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat].append_from((mi as MeshInstance3D).mesh, i, xf)
	var out := ArrayMesh.new()
	for mat in tools:
		tools[mat].commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	var result := MeshInstance3D.new()
	result.mesh = out
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return result

func _label(font: Font, font_size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = font_size
	l.pixel_size = px
	l.modulate = Brand.CREAM
	l.visibility_range_end = 60.0
	return l

## The real numbers: what food costs today, and the city's day. Nothing's shown till the server's said.
func _show_board() -> void:
	if client == null or client.city.is_empty(): return
	_price.text = "Food  %s" % Usdc.text(int(client.city.get("price", 0)))
	_day.text = "Day  %d" % int(client.city.get("day", 0))

# --- life -------------------------------------------------------------------------------------------------------------------------
func _gull_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color("f1eee6")
	var tri := func(a: Vector3, b: Vector3, c: Vector3, ua: float, ub: float, uc: float):
		for v in [[a, ua], [b, ub], [c, uc]]:
			st.set_color(white)
			st.set_uv(Vector2(v[1], 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	for s_ in [-1.0, 1.0]:              # UV.x is how far out on the wing: that's how far it flaps
		tri.call(Vector3(s_ * 0.04, 0.0, 0.12), Vector3(s_ * 0.04, 0.0, -0.1), Vector3(s_ * 0.55, 0.0, -0.05), 0.0, 0.0, 1.0)
	tri.call(Vector3(0.0, 0.03, 0.2), Vector3(-0.05, 0.0, -0.18), Vector3(0.05, 0.0, -0.18), 0.0, 0.0, 0.0)
	return st.commit()

func _duck_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ball := func(c: Vector3, size: Vector3, col: Color):
		var pts: Array[Vector3] = []
		for i in 6:
			var a := i * TAU / 6.0
			pts.append(c + Vector3(cos(a) * size.x, 0.0, sin(a) * size.z))
		var top := c + Vector3.UP * size.y
		var low := c - Vector3.UP * size.y
		for i in 6:
			for v in [top, pts[(i + 1) % 6], pts[i], low, pts[i], pts[(i + 1) % 6]]:
				st.set_color(col)
				st.set_uv(Vector2.ZERO)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	ball.call(Vector3.ZERO, Vector3(0.1, 0.08, 0.17), Color("6b5a44"))
	ball.call(Vector3(0.0, 0.12, 0.13), Vector3(0.055, 0.055, 0.055), Color("2f6e4a"))
	return st.commit()

func _batch(mesh: ArrayMesh, count: int, flap: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = PLANT_SHADER
	m.set_shader_parameter("sway", 0.0)
	m.set_shader_parameter("flap", flap)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-300.0, -50.0, -300.0), Vector3(600.0, 150.0, 600.0))
	add_child(mi)
	return mm

func _life() -> void:
	_gull_batch = _batch(_gull_mesh(), GULLS, 0.2)
	_duck_batch = _batch(_duck_mesh(), DUCKS, 0.0)
	for i in GULLS:
		_gulls.append({"centre": Vector3(_rng.randf_range(-142.0, -112.0), 0.0, _rng.randf_range(-5.0, 70.0)), "radius": _rng.randf_range(14.0, 34.0), "height": _rng.randf_range(5.0, 13.0), "speed": _rng.randf_range(0.13, 0.26) * (1.0 if i % 2 == 0 else -1.0), "at": _rng.randf() * TAU})
	for i in DUCKS:
		_ducks.append({"centre": Vector3(-114.0 + i * 1.2, WATER_Y + 0.04, 61.0 + i * 0.9), "radius": 2.0 + i * 0.7, "speed": 0.1 + i * 0.015, "at": i * 1.05})
	_smoke(Vector3(-142.2, 3.3, 43.1))
	_smoke(Vector3(-77.0, 6.0, 140.0))
	_smoke(Vector3(-118.0, 6.0, 142.0))
	var mist_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\nuniform float alpha = 0.055;\nvoid fragment() {\n\tvec2 c = UV * 2.0 - 1.0;\n\tfloat d = 1.0 - smoothstep(0.1, 1.0, length(c * vec2(1.0, 1.0)));\n\tfloat n = 0.75 + 0.25 * sin(UV.x * 9.0 + TIME * 0.12) * sin(UV.y * 7.0 - TIME * 0.09);\n\tALBEDO = vec3(1.0, 0.92, 0.86);\n\tALPHA = d * n * alpha;\n}\n"
	mist_mat.shader = sh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 14:
		var at := Director.along([Vector3(-146.0, WATER_Y + 0.5, -40.0), Vector3(-137.0, WATER_Y + 0.5, 0.0), Vector3(-127.0, WATER_Y + 0.5, 40.0), Vector3(-112.0, WATER_Y + 0.5, 76.0), Vector3(-90.0, WATER_Y + 0.5, 118.0)], float(i) / 13.0)
		at.x += _rng.randf_range(-3.0, 3.0)
		var corners := [[Vector3(-22.0, 0.0, -15.0), Vector2(0.0, 0.0)], [Vector3(22.0, 0.0, -15.0), Vector2(1.0, 0.0)], [Vector3(22.0, 0.0, 15.0), Vector2(1.0, 1.0)], [Vector3(-22.0, 0.0, 15.0), Vector2(0.0, 1.0)]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(corners[k][1])
			st.set_normal(Vector3.UP)
			st.add_vertex(at + corners[k][0])
	_mist = MeshInstance3D.new()
	_mist.mesh = st.commit()
	_mist.material_override = mist_mat
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mist)

func _smoke(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = 14
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.direction = Vector3(0.25, 1.0, 0.1)
	p.spread = 8.0
	p.initial_velocity_min = 0.45
	p.initial_velocity_max = 0.75
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.86, 0.84, 0.82, 0.13)
	q.material = m
	add_child(p)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	if _boats:
		_boats.position.y = sin(t * 1.1) * BOB * 0.6
		_boats.rotation.z = cos(t * 0.65) * 0.0015
	if _sails: _sails.rotation.z += delta * 0.22
	var eye := get_viewport().get_camera_3d()
	if eye and _plants: _plants.visible = eye.global_position.x < SEEN_FROM_X
	for i in _gulls.size():
		var g: Dictionary = _gulls[i]
		g.at += g.speed * delta
		var at: Vector3 = g.centre + Vector3(cos(g.at), 0.0, sin(g.at)) * g.radius + Vector3.UP * (g.height + sin(g.at * 3.0) * 0.7)
		_gull_batch.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -g.at + (PI if g.speed > 0.0 else 0.0)), at))
	for i in _ducks.size():
		var d: Dictionary = _ducks[i]
		d.at += d.speed * delta
		_duck_batch.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -d.at), d.centre + Vector3(cos(d.at), 0.0, sin(d.at)) * d.radius))
	var misty: bool = str(world.mode) in MIST_MODES
	if _mist.visible != misty: _mist.visible = misty
	_board_in -= delta
	if _board_in <= 0.0:
		_board_in = BOARD_EVERY
		_show_board()
