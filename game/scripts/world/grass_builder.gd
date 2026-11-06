class_name GrassBuilder
extends RefCounted
## Ground-cover fields: a square lattice of instances that follows the camera in whole cells.
## Placement, density, height and per-instance variation happen on the GPU (field.gdshaderinc),
## so cover costs a constant instance count however big the valley grows. The lattice keeps only the
## points that can ever show (inside `radius`, outside the hole of `inner`) and is cut into TILES x TILES
## MultiMeshes, all at the field's centre (so NODE_POSITION_WORLD stays the centre the shader measures
## from) but each with its own bounds, so the parts behind and beside the camera are culled.

const TILES := 6

static func field(mat: Material, spacing: float, radius: float, mesh: Mesh, inner := 0.0, layers := 1) -> Node3D:
	var n := int(ceil(radius * 2.0 / spacing))
	var lo2 := maxf(inner * 0.72 - spacing, 0.0)
	var hi2 := radius + spacing
	var tile := radius * 2.0 / TILES
	var buckets: Array = []
	for t in TILES * TILES: buckets.append([])
	for i in n * n:
		var o := Vector2((i % n - n / 2) * spacing, (i / n - n / 2) * spacing)
		var r := o.length()
		if r < lo2 or r > hi2: continue
		var tx := clampi(floori((o.x + radius) / tile), 0, TILES - 1)
		var tz := clampi(floori((o.y + radius) / tile), 0, TILES - 1)
		buckets[tz * TILES + tx].append(o)
	var root := Node3D.new()
	for t in buckets.size():
		var list: Array = buckets[t]
		if list.is_empty(): continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		var bmin := Vector2(INF, INF)
		var bmax := -bmin
		for k in list.size():
			var o: Vector2 = list[k]
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3(o.x, 0.0, o.y)))
			bmin = bmin.min(o)
			bmax = bmax.max(o)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.layers = layers
		var pad := spacing + 2.0
		mmi.custom_aabb = AABB(Vector3(bmin.x - pad, -40.0, bmin.y - pad), Vector3(bmax.x - bmin.x + pad * 2.0, 120.0, bmax.y - bmin.y + pad * 2.0))
		root.add_child(mmi)
	return root

## Camera-facing quad of the original billboard grass.
static func grass_quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 1.0)
	q.orientation = QuadMesh.FACE_Z
	return q

## Shared material with the original prototype's exact grass settings.
static func original_grass_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://original/shaders/Grass.gdshader")
	var tex := load("res://original/textures/grassleaf.png")
	m.render_priority = 1
	m.set_shader_parameter("albedo_texture", tex)
	m.set_shader_parameter("albedo1", Color(0.443, 0.635, 0.0))
	m.set_shader_parameter("albedo2_noise", load("res://original/textures/Albedo2Noise.tres"))
	m.set_shader_parameter("albedo2", Color(0.557, 0.678, 0.212))
	m.set_shader_parameter("albedo2_scale", 0.11)
	m.set_shader_parameter("albedo2_threshold", 0.537)
	m.set_shader_parameter("albedo3_noise", load("res://original/textures/Albedo3Noise.tres"))
	m.set_shader_parameter("albedo3", Color(0.502, 0.655, 0.224))
	m.set_shader_parameter("albedo3_scale", 0.1)
	m.set_shader_parameter("albedo3_threshold", 0.471)
	m.set_shader_parameter("accent_frequency1", 0.001)
	m.set_shader_parameter("accent_texture1", tex)
	m.set_shader_parameter("accent_albedo1", Color(0.604, 0.718, 0.0))
	m.set_shader_parameter("accent_height1", 0.1)
	m.set_shader_parameter("accent_scale1", 1.0)
	m.set_shader_parameter("accent_probability2", 0.0001)
	m.set_shader_parameter("accent_texture2", load("res://original/textures/accentleaf.png"))
	m.set_shader_parameter("accent_albedo2", Color(0.424, 0.604, 0.0))
	m.set_shader_parameter("accent_height2", 0.185)
	m.set_shader_parameter("accent_scale2", 1.0)
	m.set_shader_parameter("framerate", 30.0)
	m.set_shader_parameter("quantised", false)
	m.set_shader_parameter("world_space_sway", true)
	m.set_shader_parameter("world_sway_angle", 60.0)
	m.set_shader_parameter("fake_perspective_scale", 0.3)
	m.set_shader_parameter("wind_noise", load("res://original/textures/WindNoise.tres"))
	m.set_shader_parameter("wind_noise_threshold", 0.2)
	m.set_shader_parameter("wind_noise_scale", 0.05)
	m.set_shader_parameter("noise_diverge_angle", 10.0)
	m.set_shader_parameter("view_space_sway", true)
	m.set_shader_parameter("view_sway_speed", 0.1)
	m.set_shader_parameter("view_sway_angle", 10.0)
	m.set_shader_parameter("cuts", 3)
	m.set_shader_parameter("wrap", 0.0)
	m.set_shader_parameter("steepness", 1.0)
	m.set_shader_parameter("threshold_gradient_size", 0.5)
	m.set_shader_parameter("min_ambient", 0.22)
	return m
