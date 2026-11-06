extends Node3D
## Parity harness: rebuilds the three.js reference scene (exported by tools/vh_export_scene.js into
## dev/vhref/) with the ported shaders, and renders the reference's five viewpoints at the same size,
## so any difference against the browser is a shading difference, not a content difference.
##   godot --path . --rendering-driver opengl3 --resolution 1280x800 res://scenes/vh_ref.tscn -- --shots=D:/tmp/dv/ref

const DIR := "res://dev/vhref/"
const WATERFALL_Z := -94.6
const VIEWPOINTS := [["riverside", -4.2, 22.5, 0.05, 0.06], ["pavilion", -17.3, 1.8, 1.05, -0.02], ["bridge", 13.0, -80.0, -0.15, 0.04],
	["meadow", 26.0, -2.0, -1.0, 0.0], ["plateau", -10.0, -60.0, 2.75, -0.08]]

var m: Dictionary
var heights := PackedFloat32Array()
var field_tex: ImageTexture
var field_rect: Vector4
var cam: Camera3D
var env: Environment
var grass_chunks: Array = []      # [MultiMesh, total, centre xz, max distance]
var refl_vp: SubViewport
var refl_cam: Camera3D
var refl_mats: Array = []
var mesh_cache := {}
var mats := {}

static func _arg(prefix: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix): return a.trim_prefix(prefix)
	return def

static func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

func _ready() -> void:
	m = JSON.parse_string(FileAccess.get_file_as_string(DIR + "scene.json"))
	heights = FileAccess.get_file_as_bytes(DIR + "terrain_heights.bin").to_float32_array()
	_field()
	_environment()
	for o in m.objects: _object(o)
	cam = Camera3D.new()
	cam.fov = m.camera.fov
	cam.near = m.camera.near
	cam.far = m.camera.far
	add_child(cam)
	cam.make_current()
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_reflection()
	if OS.get_cmdline_user_args().has("--spheres"):
		# neutral probes, identical to the ones added to the reference scene (tools: sphere probe)
		for sp in [[-1.6, 0.5, 0.9], [0.0, 0.5, 0.9], [1.6, 0.9, 0.3]]:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 48
			sm.rings = 24
			mi.mesh = sm
			var pm := _shader("res://shaders/vh/pbr.gdshader")
			pm.set_shader_parameter("albedo", Color(sp[1], sp[1], sp[1]).linear_to_srgb())
			pm.set_shader_parameter("rough", sp[2])
			mi.material_override = pm
			add_child(mi)
			mi.global_position = Vector3(-4.2 + sp[0], 1.9800490401685238 + 1.36, 22.5 - 4.5)
	var post := CanvasLayer.new()
	post.layer = -1
	add_child(post)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/vh/grade.gdshader")
	rect.material = gm
	post.add_child(rect)
	var args := OS.get_cmdline_user_args()
	if args.has("--noreflect"): env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if args.has("--noambient"): env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	if args.has("--noglow"): gm.set_shader_parameter("bloom_strength", 0.0)
	if args.has("--noshadow"):
		for c in get_children():
			if c is DirectionalLight3D: c.shadow_enabled = false
	for a in args:
		if a.begins_with("--shots="): _shots(a.trim_prefix("--shots="))

func _h(x: float, z: float) -> float:
	var n := int(m.grid.n)
	var cell: float = float(m.grid.size) / n
	var fx := clampf((x - float(m.grid.x0)) / cell, 0.0, n - 0.001)
	var fz := clampf((z - float(m.grid.z0)) / cell, 0.0, n - 0.001)
	var i := int(fx)
	var j := int(fz)
	var N1 := n + 1
	var a := lerpf(heights[j * N1 + i], heights[j * N1 + i + 1], fx - i)
	var b := lerpf(heights[(j + 1) * N1 + i], heights[(j + 1) * N1 + i + 1], fx - i)
	return lerpf(a, b, fz - j)

## Height + water level as the same RGBA-half field texture the valley uses.
func _field() -> void:
	var n := int(m.grid.n) + 1
	var cell: float = float(m.grid.size) / int(m.grid.n)
	var f := PackedFloat32Array()
	f.resize(n * n * 4)
	for j in n:
		var lvl := 2.4 if float(m.grid.z0) + j * cell < WATERFALL_Z else 0.0
		for i in n:
			var k := (j * n + i) * 4
			f[k] = heights[j * n + i]
			f[k + 2] = lvl
			f[k + 3] = 999.0
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBAF, f.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	field_tex = ImageTexture.create_from_image(img)
	field_rect = Vector4(float(m.grid.x0) - cell * 0.5, float(m.grid.z0) - cell * 0.5, n * cell, n * cell)
	RenderingServer.global_shader_parameter_set("vh_water_y", 0.0)

func _environment() -> void:
	RenderingServer.global_shader_parameter_set("vh_sun", _dir(7.5, 3.0))
	VHSky.upload(_dir(7.5, 3.0))
	RenderingServer.global_shader_parameter_set("vh_light", _dir(3.0, 11.0))
	RenderingServer.global_shader_parameter_set("vh_wind", Vector2(0.82, 0.38))
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var to_light := (WorldData.v3(m.sun.pos) - WorldData.v3(m.sun.target)).normalized()
	sun.look_at_from_position(Vector3.ZERO, -to_light, Vector3.UP)
	sun.light_color = Color(m.sun.color[0], m.sun.color[1], m.sun.color[2]).linear_to_srgb()   # Godot linearises light colours itself
	sun.light_energy = 0.0 if OS.get_cmdline_user_args().has("--nosun") else float(m.sun.intensity) / PI
	sun.shadow_enabled = true
	sun.shadow_bias = float(_arg("--sbias=", "0.03"))
	sun.shadow_normal_bias = float(_arg("--snbias=", "1.0"))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	var sky := Sky.new()
	var skym := ShaderMaterial.new()
	skym.shader = load("res://shaders/vh/sky.gdshader")
	sky.sky_material = skym
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED   # sky light is evaluated in the shaders (VHSky SH)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED   # sky specular is computed in the shaders (vh_ibl_spec)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR     # ACES + sRGB happen in shaders/vh/grade.gdshader
	env.tonemap_exposure = 1.0
	env.glow_enabled = false   # the reference's bloom runs in shaders/vh/grade.gdshader
	env.glow_intensity = 0.32
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7: env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _xf(e: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(e[0], e[1], e[2]), Vector3(e[4], e[5], e[6]), Vector3(e[8], e[9], e[10])), Vector3(e[12], e[13], e[14]))

## three.js BufferGeometry -> ArrayMesh (winding flipped for Godot). Extra attributes: aWind/aFlow -> UV2, aSplat -> COLOR.
func _mesh(id: String) -> ArrayMesh:
	if mesh_cache.has(id): return mesh_cache[id]
	var hd: Dictionary = m.geometries[id]
	var buf := FileAccess.get_file_as_bytes(DIR + id + ".bin")
	var read := func(a: Dictionary) -> PackedFloat32Array:
		return buf.slice(int(a.offset), int(a.offset) + int(a.count) * int(a.itemSize) * 4).to_float32_array()
	var at: Dictionary = hd.attrs
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var p: PackedFloat32Array = read.call(at.position)
	var pos := PackedVector3Array()
	pos.resize(p.size() / 3)
	for i in pos.size(): pos[i] = Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
	arr[Mesh.ARRAY_VERTEX] = pos
	if at.has("normal"):
		var nn: PackedFloat32Array = read.call(at.normal)
		var nrm := PackedVector3Array()
		nrm.resize(pos.size())
		for i in pos.size(): nrm[i] = Vector3(nn[i * 3], nn[i * 3 + 1], nn[i * 3 + 2])
		arr[Mesh.ARRAY_NORMAL] = nrm
	if at.has("uv"):
		var u: PackedFloat32Array = read.call(at.uv)
		var uv := PackedVector2Array()
		uv.resize(pos.size())
		for i in pos.size(): uv[i] = Vector2(u[i * 2], u[i * 2 + 1])
		arr[Mesh.ARRAY_TEX_UV] = uv
	for k in ["aWind", "aFlow"]:
		if at.has(k):
			var w: PackedFloat32Array = read.call(at[k])
			var uv2 := PackedVector2Array()
			uv2.resize(pos.size())
			for i in pos.size(): uv2[i] = Vector2(w[i * 2], w[i * 2 + 1])
			arr[Mesh.ARRAY_TEX_UV2] = uv2
	for k in ["color", "aSplat"]:
		if at.has(k):
			var c: PackedFloat32Array = read.call(at[k])
			var sz := int(at[k].itemSize)
			var col := PackedColorArray()
			col.resize(pos.size())
			for i in pos.size(): col[i] = Color(c[i * sz], c[i * sz + 1], c[i * sz + 2], c[i * sz + 3] if sz == 4 else 1.0)
			arr[Mesh.ARRAY_COLOR] = col
	if hd.index != null:
		var idx := buf.slice(int(hd.index.offset), int(hd.index.offset) + int(hd.index.count) * 4).to_int32_array()
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
		arr[Mesh.ARRAY_INDEX] = idx
	else:
		var idx := PackedInt32Array(range(pos.size()))
		for t in range(0, idx.size() - 2, 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
		arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = mesh.get_aabb().grow(4.0)
	mesh_cache[id] = mesh
	return mesh

func _shader(path: String) -> ShaderMaterial:
	var s := ShaderMaterial.new()
	s.shader = load(path)
	return s

func _srgb(c) -> Color:
	return Color(c[0], c[1], c[2]).linear_to_srgb()

## Reference material descriptor -> ported shader.
func _material(d: Dictionary) -> Material:
	var key := JSON.stringify(d)
	if mats.has(key): return mats[key]
	var k: String = d.get("key", "") if not str(d.get("key", "")).begins_with("onBeforeCompile") else ""
	var kind: String = d.get("kind", "")
	var s: ShaderMaterial
	if k == "terrain-v1":
		s = _shader("res://shaders/vh/terrain_mesh.gdshader")
		for t in ["rock", "ground", "concrete"]:
			s.set_shader_parameter("t_" + t, VHTex.get_tex(t + "_map"))
			s.set_shader_parameter("t_" + t + "_n", VHTex.get_tex(t + "_normal"))
		s.set_shader_parameter("t_noise", VHTex.get_tex("noise"))
		s.set_shader_parameter("field_tex", field_tex)
		s.set_shader_parameter("map_rect", field_rect)
	elif k == "leaf-v1":
		s = _shader("res://shaders/vh/leaf.gdshader")
		s.set_shader_parameter("leaf_tex", VHTex.get_tex("leaf_" + str(d.map)))
		s.set_shader_parameter("transl", 0.35 if d.map == "needle" else 0.6)
		s.set_shader_parameter("rough", float(d.roughness))
	elif k == "bark-v1":
		s = _shader("res://shaders/vh/bark.gdshader")
		s.set_shader_parameter("bark_tex", VHTex.get_tex("bark_map"))
		s.set_shader_parameter("bark_n", VHTex.get_tex("bark_normal"))
	elif k == "rock-v1":
		s = _shader("res://shaders/vh/rock.gdshader")
		s.set_shader_parameter("t_rock", VHTex.get_tex("rock_map"))
		s.set_shader_parameter("t_rock_n", VHTex.get_tex("rock_normal"))
		s.set_shader_parameter("t_noise", VHTex.get_tex("noise"))
		s.set_shader_parameter("field_tex", field_tex)
		s.set_shader_parameter("map_rect", field_rect)
	elif k == "grass-v1" or k == "flower-v1":
		s = _shader("res://shaders/vh/flower_inst.gdshader" if k == "flower-v1" else "res://shaders/vh/grass_inst.gdshader")
		s.set_shader_parameter("grass_transl", float(_arg("--gtransl=", "0.6")))
		s.set_shader_parameter("flip_back", _arg("--flip=", "1") == "1")
	elif k == "tri-v1":
		s = _shader("res://shaders/vh/pbr.gdshader")
		var paving: bool = float(d.roughness) < 0.81
		s.set_shader_parameter("albedo", _srgb(d.color))
		s.set_shader_parameter("rough", float(d.roughness))
		s.set_shader_parameter("tri_tex", VHTex.get_tex("concrete_map"))
		s.set_shader_parameter("tri_n", VHTex.get_tex("concrete_normal"))
		s.set_shader_parameter("tri_scale", 0.32 if paving else 0.25)
		s.set_shader_parameter("tri_ns", 0.6 if paving else 0.8)
	elif k == "glass-v1":
		s = _shader("res://shaders/vh/glass.gdshader")
		s.set_shader_parameter("tint", _srgb(d.color))
		s.set_shader_parameter("opacity", float(d.opacity))
	elif kind == "water":
		s = _shader("res://shaders/vh/water.gdshader")
		s.set_shader_parameter("field_tex", field_tex)
		s.set_shader_parameter("map_rect", field_rect)
		s.set_shader_parameter("t_normal", VHTex.get_tex("water_normal"))
		s.set_shader_parameter("sky_only", d.sky_only)
		s.set_shader_parameter("foam_center", Vector2(14, -92.6))
		if not d.sky_only: refl_mats.append(s)
	elif kind == "waterfall":
		s = _shader("res://shaders/vh/waterfall.gdshader")
	elif kind == "mist":
		s = _shader("res://shaders/vh/mist.gdshader")
		s.set_shader_parameter("t_glow", VHTex.get_tex("glow"))
	elif kind == "city":
		s = _shader("res://shaders/vh/city.gdshader")
	elif d.type == "MeshBasicMaterial":
		if d.get("map", "") == "glow":
			s = _shader("res://shaders/vh/pool.gdshader")
			s.set_shader_parameter("t_glow", VHTex.get_tex("glow"))
			s.set_shader_parameter("color", Color(d.color[0], d.color[1], d.color[2]))
			s.set_shader_parameter("energy", 1.0)
		else:
			s = _shader("res://shaders/vh/led.gdshader")
			var c := Color(d.color[0], d.color[1], d.color[2])
			var e := maxf(c.r, maxf(c.g, c.b))
			s.set_shader_parameter("color", (c / e).linear_to_srgb())
			s.set_shader_parameter("energy", e)
	else:
		s = _shader("res://shaders/vh/pbr.gdshader")
		s.set_shader_parameter("albedo", _srgb(d.color))
		s.set_shader_parameter("rough", float(d.get("roughness", 1.0)))
		s.set_shader_parameter("metal", float(d.get("metalness", 0.0)))
		s.set_shader_parameter("use_vcol", d.get("vertexColors", false))
		s.set_shader_parameter("flat_shade", d.get("flatShading", false))
		if d.has("emissive") and d.emissive != null:
			s.set_shader_parameter("emission_color", _srgb(d.emissive))
			s.set_shader_parameter("emission_energy", float(d.get("emissiveIntensity", 0.0)))
	mats[key] = s
	return s

func _mi(geo: String, mat: Dictionary, xf: Array, cast: bool, vb := 0.0, ve := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(geo)
	mi.material_override = _material(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if OS.get_cmdline_user_args().has("--leafnocast") and str(mat.get("key", "")) == "leaf-v1": mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = vb
	mi.visibility_range_end = ve
	var kind: String = mat.get("kind", "")
	if kind in ["water", "waterfall", "mist"] or mat.get("map", "") == "glow": mi.layers = 4
	add_child(mi)
	mi.global_transform = _xf(xf)

func _object(o: Dictionary) -> void:
	if o.has("lod"):
		var lv: Array = o.lod
		for i in lv.size():
			var vb: float = lv[i].distance
			var ve: float = lv[i + 1].distance if i + 1 < lv.size() else 0.0
			for me in lv[i].meshes: _mi(me.geo, me.mat, me.matrix, me.cast, vb, ve)
		return
	var key: String = str(o.mat.get("key", ""))
	var hide := _arg("--hide=", "").split(",", false)
	if o.mat.get("kind", "") == "sky" or key in hide or str(o.mat.get("kind", "")) in hide: return
	var hd: Dictionary = m.geometries[o.geo]
	if key == "grass-v1" or key == "flower-v1" or o.mat.get("kind", "") == "mist":
		_instanced_geo(o, hd)
		return
	if o.has("instances"):
		var mats_raw := FileAccess.get_file_as_bytes(DIR + str(o.instances.file)).to_float32_array()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cols := PackedFloat32Array()
		if o.instances.has("colors"):
			mm.use_colors = true
			cols = FileAccess.get_file_as_bytes(DIR + str(o.instances.colors)).to_float32_array()
		mm.mesh = _mesh(o.geo)
		mm.instance_count = int(o.instances.count)
		for i in mm.instance_count:
			var e := mats_raw.slice(i * 16, i * 16 + 16)
			mm.set_instance_transform(i, _xf(Array(e)))
			if mm.use_colors: mm.set_instance_color(i, Color(cols[i * 3], cols[i * 3 + 1], cols[i * 3 + 2]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _material(o.mat)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if o.cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		return
	_mi(o.geo, o.mat, o.matrix, o.cast)

## InstancedBufferGeometry (grass/flower chunks with aOffset/aParams, mist with aMist) -> MultiMesh.
func _instanced_geo(o: Dictionary, hd: Dictionary) -> void:
	var buf := FileAccess.get_file_as_bytes(DIR + str(o.geo) + ".bin")
	var inst: Dictionary = hd.instanced
	var count := int(inst.aMist.count if inst.has("aMist") else inst.aOffset.count)   # full lists: the export-time instanceCount was already distance-culled
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh(o.geo)
	mm.instance_count = count
	var mist: bool = o.mat.get("kind", "") == "mist"
	var cx := 0.0
	var cz := 0.0
	if mist:
		var a: PackedFloat32Array = buf.slice(int(inst.aMist.offset), int(inst.aMist.offset) + count * 16).to_float32_array()
		for i in count:
			mm.set_instance_transform(i, Transform3D())
			mm.set_instance_custom_data(i, Color(a[i * 4], a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3]))
	else:
		var off: PackedFloat32Array = buf.slice(int(inst.aOffset.offset), int(inst.aOffset.offset) + count * 16).to_float32_array()
		var par: PackedFloat32Array = buf.slice(int(inst.aParams.offset), int(inst.aParams.offset) + count * 16).to_float32_array()
		for i in count:
			var p := Vector3(off[i * 4], off[i * 4 + 1], off[i * 4 + 2])
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -off[i * 4 + 3]), p))
			mm.set_instance_custom_data(i, Color(par[i * 4], par[i * 4 + 1], par[i * 4 + 2], par[i * 4 + 3]))
			cx += p.x
			cz += p.z
		cx /= maxi(1, count)
		cz /= maxi(1, count)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material(o.mat)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if OS.get_cmdline_user_args().has("--grasscast") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 60, 120)) if mist else AABB()
	mmi.layers = 4 if mist else 2
	add_child(mmi)
	if not mist:
		# chunk centre = cell centre (10 m cells); instances are already shuffled, so a prefix thins evenly
		var c := Vector2(floor((cx + 80.0) / 10.0) * 10.0 - 75.0, floor((cz + 128.0) / 10.0) * 10.0 - 123.0)
		grass_chunks.append([mm, count, c, 42.0 if o.mat.key == "flower-v1" else 70.0])

## vegetation.ts GrassField.update: render a prefix of each chunk's shuffled list by camera distance.
func _process(_d: float) -> void:
	if cam == null: return
	var cp := cam.global_position
	for c in grass_chunks:
		var d := maxf(0.0, Vector2(c[2].x - cp.x, c[2].y - cp.z).length() - 5.0)
		if d > c[3]:
			(c[0] as MultiMesh).visible_instance_count = 0
			continue
		var f := 1.0 if d < 16.0 else pow(16.0 / d, 1.8)
		var fade := 1.0 - smoothstep(c[3] * 0.75, c[3], d)
		(c[0] as MultiMesh).visible_instance_count = int(c[1] * f * fade)
	_update_reflection()

func _reflection() -> void:
	refl_vp = SubViewport.new()
	refl_vp.size = Vector2i(get_viewport().get_visible_rect().size * 0.6)
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refl_vp.use_hdr_2d = true
	refl_vp.world_3d = get_viewport().world_3d
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.cull_mask = 1
	var renv: Environment = env.duplicate()
	renv.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	renv.tonemap_exposure = 1.0
	renv.glow_enabled = false
	refl_cam.environment = renv
	refl_vp.add_child(refl_cam)
	refl_cam.current = true
	for s in refl_mats: s.set_shader_parameter("t_reflection", refl_vp.get_texture())
	RenderingServer.global_shader_parameter_set("vh_refl_y", 0.0)

func _update_reflection() -> void:
	if refl_cam == null: return
	var t := cam.global_transform
	var f := -t.basis.z
	var u := t.basis.y
	refl_cam.fov = cam.fov
	refl_cam.near = cam.near
	refl_cam.far = cam.far
	refl_cam.global_transform = Transform3D(Basis.looking_at(Vector3(f.x, -f.y, f.z), Vector3(u.x, -u.y, u.z)), Vector3(t.origin.x, -t.origin.y, t.origin.z))
	var vp := refl_cam.get_camera_projection() * Projection(refl_cam.global_transform.affine_inverse())
	for s in refl_mats: s.set_shader_parameter("refl_vp", vp)

func _shots(prefix: String) -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.trim_prefix("--only=")
	var views := VIEWPOINTS.duplicate()
	var cv := _arg("--cam=", "")
	if cv != "":
		var c := cv.split(",")
		views = [["custom", float(c[0]), float(c[1]), float(c[2]), float(c[3]), float(c[4])]]
	for v in views:
		if only != "" and v[0] != only: continue
		if v.size() > 5:
			cam.global_position = Vector3(v[1], v[2], v[3])
			cam.rotation = Vector3(v[4], v[5], 0.0)
			for i in 60: await get_tree().process_frame
			var cs := get_viewport().get_texture().get_image()
			cs.convert(Image.FORMAT_RGBA8)
			cs.save_png("%s_%s.png" % [prefix, v[0]])
			continue
		cam.global_position = Vector3(v[1], _h(v[1], v[2]) + 1.66, v[2])
		cam.rotation = Vector3(v[4], -v[3], 0.0)
		RenderingServer.global_shader_parameter_set("player_pos", Vector3(v[1], _h(v[1], v[2]), v[2]))
		for i in 60: await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		shot.save_png("%s_%s.png" % [prefix, v[0]])
		print("view ", v[0], " fps=", Engine.get_frames_per_second(), " draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " tris=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	get_tree().quit()
