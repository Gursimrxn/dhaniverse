extends Node3D
## One approved building: model, brand recolour, outside box collider,
## door trigger, and an interior trimesh that is only active while inside.

var def: Dictionary
var model: Node3D
var center2 := Vector2.ZERO
var half2 := Vector2(8, 8)          # half extents of the box round the (turned) building, world axes
var frame := Vector2(8, 8)          # half extents of its own footprint: across its front, deep
var height := 8.0
var floor_y := 0.0
var door := Vector3.ZERO
var face := Vector2(0, 1)
var materials: Array[ShaderMaterial] = []
var outer_body: StaticBody3D
var inner_body: StaticBody3D
var inside_point := Vector3.ZERO
var entrance_local := Vector3.ZERO
var has_entrance := false
var entrance_front := Vector2(0, 1)   # the front's direction in the model's own axes

func setup(d: Dictionary, manifest: Dictionary) -> void:
	def = d
	name = d.id
	face = (d.get("face", Vector2(0, 1)) as Vector2).normalized()
	var glb := str(d.get("glb", ""))
	var path := glb if glb.begins_with("res://") else "res://assets/buildings/%s" % glb
	if d.has("node"):
		model = d.node
	elif d.has("glb") and ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate()
	else:
		model = _placeholder()
	add_child(model)
	# rotate the model so its entrance (from the export manifest) looks along `face`
	var door_local := Vector2(0, 1)
	var info: Dictionary = manifest.get("buildings", {}).get(glb.get_file().get_basename(), {})
	if info.get("entrance") is Dictionary:
		var fd: Array = info.entrance.front_dir
		door_local = Vector2(fd[0], fd[2])
		var ep: Array = info.entrance.position
		entrance_local = Vector3(ep[0], ep[1], ep[2])
		has_entrance = true
	if door_local.length() < 0.01: door_local = Vector2(0, 1)
	entrance_front = door_local
	# baked v3 sites keep the exact orientation they had in the town master
	if d.get("keep_orientation", false): face = door_local.normalized()
	var yaw := door_local.angle_to(face)
	model.rotation.y = -yaw
	model.scale = Vector3.ONE * float(d.get("scale", 1.0))
	_apply_materials()
	_measure()
	center2 = d.pos
	position = Vector3(center2.x, 0, center2.y)

func _placeholder() -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# a block the size the layout reserves (world axes), until the site's model is built
	var half: Array = def.get("half", [7, 6])
	var turned := absf(face.x) > absf(face.y)
	bm.size = Vector3(float(half[1 if turned else 0]) * 2.0, 8, float(half[0 if turned else 1]) * 2.0)
	mi.mesh = bm
	mi.position.y = 4
	var n := Node3D.new()
	n.add_child(mi)
	return n

## What each surface of a building is, from its material name (the convention of the quarter's GLBs,
## tools/blender/tallyport_arch.py); shaders/foliage/building.gdshader paints each part in its site's colour.
## Surfaces whose names say none of these (the retained masters) are sorted by their vertex colours.
const PART_WALL := 0
const PART_TRIM := 1
const PART_FRAME := 2
const PART_ROOF := 3
const PART_WOOD := 4
const PART_STONE := 5
const PART_METAL := 6
const PART_CANVAS := 7
const PART_PLANT := 8
const PART_LIGHT := 9
const PART_GLASS := 10
const PART_AUTHORED := 11
const PART_BY_COLOUR := -1
## Checked in this order: a lamp on a wall is a light, a timber frame is wood.
const PART_NAMES := [["glass", PART_GLASS], ["glaz", PART_GLASS], ["light", PART_LIGHT], ["glow", PART_LIGHT],
	["canvas", PART_CANVAS], ["fabric", PART_AUTHORED], ["ceramic", PART_AUTHORED], ["plant", PART_PLANT],
	["metal", PART_METAL], ["stone", PART_STONE], ["wood", PART_WOOD], ["roof", PART_ROOF], ["frame", PART_FRAME],
	["trim", PART_TRIM], ["wall", PART_WALL]]
const PART_KEYS := {PART_WALL: "wall", PART_TRIM: "trim", PART_FRAME: "frame", PART_ROOF: "roof", PART_WOOD: "wood",
	PART_STONE: "stone", PART_METAL: "metal", PART_CANVAS: "canvas", PART_PLANT: "plant"}

static func part_for(material_name: String) -> int:
	var n := material_name.to_lower()
	for p in PART_NAMES:
		if n.contains(p[0]): return p[1]
	return PART_BY_COLOUR

## Every building's colours (sRGB): the quarter's shared palette, which a site's own entry here or a
## "palette" in its data overrides part by part. Pearl and cream walls, charcoal frames, slate roofs,
## warm timber, pale stone: one family, so the town reads as one place.
const STYLES := {
	"": {"wall": "f1ebe0", "trim": "d8cebc", "frame": "3a3d40", "roof": "4c5359", "wood": "b0835a", "stone": "cfc6b6",
		"metal": "4a4f54", "canvas": "f2e8d2", "plant": "6f9a4f", "glass": "3b4a55"},
	"dv02": {"wall": "f0ece6", "trim": "d6d0c5"},
	"dv04": {"wall": "f3e8d8", "trim": "dccfbe"},
}

func _palette() -> Dictionary:
	var pal: Dictionary = STYLES[""].duplicate()
	pal.merge(STYLES.get(def.id, {}), true)
	pal.merge(def.get("palette", {}), true)
	return pal

func _apply_materials() -> void:
	var pal := _palette()
	var shader := load("res://shaders/foliage/building.gdshader")
	var cache := {}
	for mi in _meshes(model):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := (src.resource_name if src else "")
			var vcol: bool = mi.mesh is ArrayMesh and (mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var base := Color(0.9, 0.9, 0.9)
			if src is BaseMaterial3D: base = (src as BaseMaterial3D).albedo_color
			var part := part_for(nm)
			# unnamed surfaces without vertex colours (lettering, emblems) keep their own colour
			if part == PART_BY_COLOUR and not vcol: part = PART_AUTHORED
			var key := "%d_%s_%s" % [part, vcol, base.to_html()]
			if not cache.has(key):
				var m := ShaderMaterial.new()
				m.shader = shader
				m.set_shader_parameter("part", part)
				m.set_shader_parameter("use_vcol", vcol)
				m.set_shader_parameter("base", base)
				m.set_shader_parameter("col", Color(pal.get(PART_KEYS.get(part, "wall"), pal.wall)))
				for k in ["wall", "trim", "frame", "roof", "wood"]: m.set_shader_parameter("pal_" + k, Color(pal[k]))
				m.set_shader_parameter("glass_tint", Color(pal.glass))
				cache[key] = m
				materials.append(m)
			mi.set_surface_override_material(i, cache[key])

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.mesh: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out

func _aabb_rel(n: Node, xf: Transform3D, acc: Array) -> void:
	var t: Transform3D = xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D and n.mesh:
		var b: AABB = t * (n as MeshInstance3D).get_aabb()
		acc[0] = b if acc[0] == null else (acc[0] as AABB).merge(b)
	for c in n.get_children(): _aabb_rel(c, t, acc)

func _measure() -> void:
	# its own footprint first, unturned: across the front and deep, whichever local axis the front faces along
	var yaw := model.rotation.y
	model.rotation.y = 0.0
	var acc0 := [null]
	_aabb_rel(model, Transform3D.IDENTITY, acc0)
	var b0: AABB = acc0[0]
	model.rotation.y = yaw
	var fl := Vector2(entrance_front.x, entrance_front.y)
	frame = Vector2(b0.size.x, b0.size.z) * 0.5 if absf(fl.y) >= absf(fl.x) else Vector2(b0.size.z, b0.size.x) * 0.5
	# then turned: centre it on the site with its base at y = 0
	var acc := [null]
	_aabb_rel(model, Transform3D.IDENTITY, acc)
	var b: AABB = acc[0]
	model.position -= Vector3(b.get_center().x, b.position.y, b.get_center().z)
	half2 = Vector2(b.size.x, b.size.z) * 0.5
	height = b.size.y

func settle(y: float) -> void:
	# called after the terrain is flattened: drop onto the plinth, build colliders and the door
	floor_y = y
	position.y = y
	# the box the interior light (building / glass shaders) works in
	var lo := Vector3(center2.x - half2.x, y, center2.y - half2.y)
	var hi := Vector3(center2.x + half2.x, y + height, center2.y + half2.y)
	for m in materials:
		m.set_shader_parameter("floor_y", y)
		m.set_shader_parameter("int_lo", lo)
		m.set_shader_parameter("int_hi", hi)
	var along := frame.y
	# keep the entrance's sideways offset, but stand just outside the footprint
	var lateral := 0.0
	var side := Vector2(-face.y, face.x)
	if has_entrance:
		var e := model.transform * entrance_local
		lateral = clampf(Vector2(e.x, e.z).dot(side), -frame.x + 2.0, frame.x - 2.0)
	var c := center2 + side * lateral
	door = Vector3(c.x + face.x * (along + 1.6), y, c.y + face.y * (along + 1.6))
	inside_point = Vector3(c.x + face.x * (along - 3.0), y + 0.2, c.y + face.y * (along - 3.0))

	outer_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(frame.x * 2.0 - 0.6, height, frame.y * 2.0 - 0.6)
	cs.shape = sh
	cs.position = Vector3(0, height * 0.5, 0)
	cs.rotation.y = atan2(face.x, face.y)     # its local +Z (the front) along the facing
	outer_body.add_child(cs)
	add_child(outer_body)

	var area := Area3D.new()
	var acs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 2.6
	acs.shape = sph
	area.add_child(acs)
	area.monitoring = true
	add_child(area)
	area.global_position = door + Vector3(0, 1, 0)
	area.body_entered.connect(func(b): if b.has_method("near_site"): b.near_site(self))
	area.body_exited.connect(func(b): if b.has_method("left_site"): b.left_site(self))


func set_inside(on: bool) -> void:
	for m in materials: m.set_shader_parameter("focused", on)
	outer_body.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	for c in outer_body.get_children(): c.disabled = on
	if on and inner_body == null:
		inner_body = StaticBody3D.new()
		for mi in _meshes(model):
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			inner_body.add_child(cs)
			cs.global_transform = mi.global_transform
		add_child(inner_body)
		# re-apply transforms once parented
		var i := 0
		for mi in _meshes(model):
			(inner_body.get_child(i) as Node3D).global_transform = mi.global_transform
			i += 1
	if inner_body:
		for c in inner_body.get_children(): c.disabled = not on

func focus_radius() -> float:
	return maxf(half2.x, half2.y) + 1.5
