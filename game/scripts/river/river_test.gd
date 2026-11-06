extends Node3D
## River kit test bed: pool basin + upper stream, stepped waterfall, boulders, fish.
## Screenshots:  -- --shots=D:/tmp/river/x   (saves x_<view>.png then quits)

const X0 := -22.0
const Z0 := -26.0
const W := 44.0
const D := 48.0
const RES := 0.5
const WL := 0.0          # pool water level
const UP_WL := 4.5       # upper stream water level
const LIP_Z := -9.0

var gw := int(W / RES) + 1
var gd := int(D / RES) + 1
var heights := PackedFloat32Array()
var noise := FastNoiseLite.new()
var cam: Camera3D

func _ready() -> void:
	noise.seed = 4
	noise.frequency = 0.08
	_lighting()
	_terrain()
	_water(WL, Vector3(X0 + W * 0.5, WL, Z0 + D * 0.5), Vector2(W, D))
	_water(UP_WL, Vector3(X0 + W * 0.5, UP_WL, (Z0 + LIP_Z + 0.1) * 0.5), Vector2(W, LIP_Z + 0.1 - Z0))
	add_child(RiverKit.waterfall({top = Vector3(0, UP_WL, LIP_Z), bottom = Vector3(0, WL, -5.0), width = 3.2, steps = 3, seed = 3}))
	RiverKit.scatter_rocks(self, _rock_points(), WL)
	RiverKit.scatter_rocks(self, _upper_rock_points(), UP_WL)
	add_child(RiverKit.fish_school(Vector3(2.5, 0, 3.0), 3.5, 12, WL, 7))
	add_child(RiverKit.fish_school(Vector3(-3.5, 0, 0.5), 2.2, 7, WL, 11))
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 300.0
	add_child(cam)
	_view(Vector3(0, 0, -1), 25.0, -35.0, 27.0)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].begins_with("--shots="):
		_capture(args[0].trim_prefix("--shots="))

func _view(target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	cam.global_transform = Transform3D(b, target + b * Vector3(0, 0, dist))

func _capture(prefix: String) -> void:
	var views := [
		["high", Vector3(0, 0, -1), 25.0, -35.0, 27.0],
		["fall", Vector3(0, 1.4, -7), -18.0, -20.0, 13.0],
		["pool", Vector3(1, 0, 1), 160.0, -48.0, 22.0],
	]
	for v in views:
		_view(v[1], v[2], v[3], v[4])
		for i in 90: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, v[0]])
	get_tree().quit()

# --- ground ---------------------------------------------------------------------------
## Pool basin, a cliff behind it and a stream on the terrace above.
func h_at(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	# lower meadow with an organic pool
	var q := Vector2((x - 1.0) / 10.0, (z - 1.5) / 7.5)
	var e := q.length() + n * 0.18
	var h := lerpf(-1.5, 0.55 + n * 0.15, smoothstep(0.55, 1.02, e))
	# outlet running off to the front-right
	var o := Vector2(x, z) - Vector2(1.0, 1.5)
	var along := o.dot(Vector2(0.6, 0.8))
	if along > 0.0:
		var across := absf(o.dot(Vector2(0.8, -0.6)))
		h = minf(h, lerpf(-0.6, 0.55, smoothstep(1.6, 3.2, across + n)))
	# terrace above the falls
	var terrace := smoothstep(-5.6, -9.2, z + n * 1.5 * smoothstep(3.0, 6.0, absf(x)))
	var upper := 5.1 + n * 0.2
	var cx := sin(z * 0.18) * 1.2
	var ch := lerpf(3.6, upper, smoothstep(1.4, 2.8, absf(x - cx) + n * 0.4))
	return lerpf(h, minf(upper, ch), terrace)

func _terrain() -> void:
	heights.resize(gw * gd)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in gd:
		for x in gw:
			var px := X0 + x * RES
			var pz := Z0 + z * RES
			var h := h_at(px, pz)
			heights[z * gw + x] = h
			var wl := UP_WL if pz < LIP_Z else WL
			var bank := smoothstep(wl + 0.5, wl + 0.3, h)
			# cliff face between the levels reads as stone
			var slope := absf(h_at(px, pz + 0.5) - h_at(px, pz - 0.5)) + absf(h_at(px + 0.5, pz) - h_at(px - 0.5, pz))
			var cliff := smoothstep(0.6, 1.0, slope) * (1.0 - bank)
			var path := smoothstep(1.8, 1.2, absf(px + 13.0 + sin(pz * 0.15) * 1.5)) * (1.0 - bank)
			st.set_color(Color(path, bank, 0, cliff))
			st.add_vertex(Vector3(px, h, pz))
	for z in gd - 1:
		for x in gw - 1:
			var a := z * gw + x
			st.add_index(a); st.add_index(a + 1); st.add_index(a + gw)
			st.add_index(a + 1); st.add_index(a + gw + 1); st.add_index(a + gw)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	mi.material_override = m
	add_child(mi)

func _water(level: float, center: Vector3, size: Vector2) -> void:
	var img := Image.create(gw, gd, false, Image.FORMAT_RH)
	for z in gd:
		for x in gw:
			img.set_pixel(x, z, Color(heights[z * gw + x], 0, 0))
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 48
	pm.subdivide_depth = 48
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("map_rect", Vector4(X0, Z0, W, D))
	mat.set_shader_parameter("water_level", level)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = center
	add_child(mi)

# --- rocks ----------------------------------------------------------------------------
func _rock_points() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 21
	var pts := []
	# ring of bank boulders, gap at the outlet and at the falls
	for i in 26:
		var a := TAU * i / 26.0 + r.randf_range(-0.08, 0.08)
		var p := Vector2(1.0 + cos(a) * 10.0 * r.randf_range(0.86, 0.98), 1.5 + sin(a) * 7.5 * r.randf_range(0.86, 0.98))
		if Vector2(cos(a), sin(a)).dot(Vector2(0.6, 0.8)) > 0.9: continue
		var s := r.randf_range(0.6, 1.4)
		pts.append([Vector3(p.x, maxf(h_at(p.x, p.y), WL - 0.3) + s * 0.15, p.y), s])
	# stones standing in the water (get ripple rings)
	for p in [Vector2(-4.5, -1.5), Vector2(5.5, -0.5), Vector2(-2.0, 5.0), Vector2(6.0, 4.5), Vector2(3.0, -3.8), Vector2(-6.2, 3.2)]:
		pts.append([Vector3(p.x, -0.25, p.y), r.randf_range(0.5, 0.8)])
	# pebbles on the pool bed, seen through the clear shallows
	for i in 8:
		var a := r.randf() * TAU
		var d := r.randf_range(0.72, 0.86)
		var p := Vector2(1.0 + cos(a) * 10.0 * d, 1.5 + sin(a) * 7.5 * d)
		pts.append([Vector3(p.x, h_at(p.x, p.y) + 0.05, p.y), r.randf_range(0.3, 0.5), 1])
	# boulders lining the foot of the cliff either side of the falls
	for x in [-11.0, -8.8, -6.6, -4.4, 4.6, 6.8, 9.0, 11.2]:
		var s := r.randf_range(1.2, 1.8)
		var z := -6.6 + r.randf_range(-0.5, 0.5)
		pts.append([Vector3(x, h_at(x, z) + s * 0.25, z), s])
		# second tier up the cliff face
		var s2 := r.randf_range(1.0, 1.5)
		pts.append([Vector3(x + r.randf_range(-0.8, 0.8), 2.6, -8.4), s2])
	return pts

func _upper_rock_points() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var pts := []
	for z in range(-23, -9, 2):
		for sgn in [-1.0, 1.0]:
			var x: float = sin(z * 0.18) * 1.2 + sgn * r.randf_range(2.0, 2.6)
			var s := r.randf_range(0.45, 0.9)
			pts.append([Vector3(x, h_at(x, z) + s * 0.1, z), s])
	return pts

# --- light ----------------------------------------------------------------------------
func _lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -135, 0)
	sun.light_color = Brand.SUN
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.82
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
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
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Brand.FOG
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
