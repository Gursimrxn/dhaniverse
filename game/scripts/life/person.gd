extends Node3D
## A person: the player's body or a townsperson. One of the chubby characters in assets/characters/chibi
## (Quaternius Ultimate Animated Character Pack, CC0; body "C", scaled to 1.4 m) or the slim modular adults in
## assets/characters/src (W_/M_), painted in the foliage light (shaders/foliage/character.gdshader) with an ink outline,
## recoloured per person (skin, hair, hat, top, accents, bottom, shoes), and animated by its own clips:
## idle, walk and run played at exactly the speed it travels (GAIT, measured by dev/measure_gait.gd) so its
## feet stay planted, cross-faded as the speed changes; a wave or a reach to interact played once on top.
## The animation is stepped by hand (step), so the head can turn after it, towards look_target.

const SRC := "res://assets/characters/src/%s.gltf"
const CHIBI := "res://assets/characters/chibi/%s.gltf"
const FOLK := "res://assets/characters/folk/folk.glb"   # the player's body, thinned for a crowd (tools/blender/build_folk.py)
const CHIBI_SCALE := 0.4375     # 3.2 units -> 1.4 m
const FOLK_SHADER := preload("res://shaders/valley/character.gdshader")
const CHAR_SHADER := preload("res://shaders/foliage/character.gdshader")
const INK_SHADER := preload("res://shaders/foliage/character_ink.gdshader")
# ground speed (m/s) of each locomotion clip at speed 1, per body (dev/measure_gait.gd)
const GAIT := {"W": {"Walk": 1.106, "Run": 2.373}, "M": {"Walk": 1.378, "Run": 2.99}, "C": {"Walk": 1.001, "Run": 2.179}}
const WALK_UNTIL := {"W": 2.0, "M": 2.0, "C": 1.45}     # m/s: faster than this it runs
# gestures each body may lack, and what it plays instead
const ALIAS := {"Wave": ["Wave", "Victory"], "Interact": ["Interact", "PickUp"]}
const FADE := 0.22              # s: cross-fade between clips
const SKINS := ["f3d2b8", "e8b994", "d39f78", "b9805a", "94603f", "6e452e", "4f3122"]
const HAIRS := ["2b2018", "3b2a20", "5a3a22", "8a5a32", "b98a4e", "d9c08a", "a8a8a8", "6b2e22"]

var parts: Array[MeshInstance3D] = []
var look_target := Vector2.ZERO  # head turn (yaw, pitch), radians
var body := "W"
var _ap: AnimationPlayer
var _sk: Skeleton3D
var _head := -1
var _neck := -1
var _clip := ""
var _turned := {}                  # bone -> [the clip's pose, the turned pose set last]
var _once := ""                  # a gesture playing once, then back to the gait
var _look := Vector2.ZERO
var _phase := 0.0
var _mats := {}
static var _folk_shapes := {}      # the parts worn -> [their meshes' arrays put end to end, each part's vertex count, flags]
static var _folk_mat: ShaderMaterial
var _chibi := false
var _sitting := false
var legs: Gait                   # the folk body, near the camera: proper feet. Further off, the clips will do
var use_gait := false
var watching: Node3D = null      # who they glance at when they're close
var _eyes: MeshInstance3D
var _blink_in := 2.0
const BLINK := 0.11              # s
const WATCH_WITHIN := 5.0        # m

static func gait(b: String, speed: float) -> Array:
	if speed < 0.15: return ["Idle", 1.0]
	var clip := "Walk" if speed < float(WALK_UNTIL[b]) else "Run"
	return [clip, speed / float(GAIT[b][clip])]

## The chubby characters' surfaces are named for what they are.
static func role_chibi(mat: String) -> String:
	match mat:
		"Skin": return "skin"
		"Hair", "Moustache", "Beard": return "hair"
		"Hat", "HatBrown", "HatLightBrown": return "hat"
		"Shirt", "Clothes", "Main", "Jacket": return "top"
		"Vest", "Top", "Scarf", "Band", "Detail", "Details": return "top2"
		"Pants", "DarkClothes": return "bottom"
		"Belt": return "shoes"
	return "keep"

static func role_for(mesh: String, mat: String, k: int) -> String:
	if mat == "Skin": return "skin"
	if mesh.contains("Head"):
		if mat.contains("Hair") or mat.contains("Eyebrow") or mat.contains("Moustache") or mat.contains("Beard"): return "hair"
		if mat in ["Eye", "Eyes", "Brown", "DarkBrown", "Black", "White"]: return "keep"
		return "hat"
	if mesh.contains("Body"): return "top" if k == 0 else "top2"
	if mesh.contains("Legs") or mesh.contains("Pants"): return "bottom"
	if mesh.contains("Feet"): return "shoes"
	return "hide"

## Someone of the town's, from any whole number: the same number always makes the same person. Not the player in other colours: a shape,
## a head and clothes of their own.
static func folk_look(n: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = n
	var pick := func(list: Array): return list[r.randi_range(0, list.size() - 1)]
	var look := {"skin": pick.call(SKINS), "hair": pick.call(HAIRS), "top": pick.call(["2f7c7a", "b8473b", "d9a441", "4b6ea6", "6b8e4e", "8a5a7a", "c98a5e", "4a4f63"]),
		"tee": pick.call(["e8e2d4", "c9c2b4", "4a4f63", "d9a441"]), "bottom": pick.call(["2a2a30", "3b3a4a", "4b3a2c", "5a5f55", "6a6a72", "28324a"]), "shoes": pick.call(["2a2a30", "4b3a2c", "6a5a4a"]),
		"hat": "", "open_top": r.randf() < 0.55, "tall": r.randf_range(0.9, 1.1), "wide": r.randf_range(0.9, 1.22)}
	match r.randi_range(0, 7):           # a head of their own
		0: look.long_hair = true
		1: look.bun = true
		2:
			look.cap = true
			look.hat = pick.call(["b8473b", "26335f", "d9a441", "2f7c7a"])
		3: look.hat = pick.call(["26335f", "b8473b", "6b8e4e"])
		4:
			look.beard = true
			look.bald = r.randf() < 0.5
		5:
			look.long_hair = true
			look.skirt = true
		6:
			look.bun = true
			look.skirt = true
		7: look.bald = true
	if look.has("skirt"): look.skirt_colour = pick.call(["4b6ea6", "b8473b", "6b8e4e", "8a5a7a", "d9a441"])
	if r.randf() < 0.12: look.apron = true
	return look

## outfit: "folk" (look as folk_look gives), a model in assets/characters/src (W_Casual, M_Suit, ...); look: colours by role (skin, hair, hat,
## top, top2, bottom, shoes), each an html colour; roles left out keep the model's own colour.
func setup(outfit: String, look := {}) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # whoever owns this moves it every frame
	var folk := outfit == "folk"
	_chibi = not folk and ResourceLoader.exists(CHIBI % outfit)
	body = "C" if _chibi or folk else outfit.substr(0, 1)
	var n: Node3D = (load(FOLK) if folk else load((CHIBI if _chibi else SRC) % outfit)).instantiate()
	add_child(n)
	if _chibi: n.scale = Vector3.ONE * CHIBI_SCALE
	if folk:
		var wide := float(look.get("wide", 1.0))
		n.scale = Vector3(wide, float(look.get("tall", 1.0)), wide) * CHIBI_SCALE
	_ap = n.find_children("*", "AnimationPlayer", true, false)[0]
	_sk = n.find_children("*", "Skeleton3D", true, false)[0]
	_head = _sk.find_bone("Head")
	_neck = _sk.find_bone("Neck")
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for c in ["Idle", "Walk", "Run", "Walk_Carry", "Run_Carry"]:
		if _ap.has_animation(c): _ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if folk: _paint_folk(mi as MeshInstance3D, look)
		else: _paint(mi as MeshInstance3D, look)
	if folk and not OS.get_cmdline_user_args().has("--folk-parts"): _merge_folk()     # dev: --folk-parts draws them part by part, to compare
	_ap.play("Idle")
	_clip = "Idle"
	if folk:
		legs = Gait.new(_sk, self)
		legs.floor_ray = func(from: Vector3, to: Vector3) -> float:
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
			return hit.position.y if hit else INF

## Each of the folk body's meshes is one kind of thing, in a colour of its own. What they aren't wearing isn't drawn.
func _paint_folk(mi: MeshInstance3D, look: Dictionary) -> void:
	var part := String(mi.name)
	if part == "Eyes": _eyes = mi
	var wears: bool
	var colour := ""
	match part:
		"Skin":
			wears = true
			colour = look.get("skin", "e8b994")
		"Eyes":
			wears = true
			colour = "16161c"
		"Hair":
			wears = not bool(look.get("bald", false)) and not bool(look.get("cap", false))
			colour = look.get("hair", "2b2018")
		"HairLong", "Bun", "Beard":
			wears = bool(look.get({"HairLong": "long_hair", "Bun": "bun", "Beard": "beard"}[part], false))
			colour = look.get("hair", "2b2018")
		"Beanie":
			wears = str(look.get("hat", "")) != "" and not bool(look.get("cap", false))
			colour = look.get("hat", "26335f")
		"Cap":
			wears = bool(look.get("cap", false))
			colour = look.get("hat", "b8473b")
		"Flannel":
			wears = bool(look.get("open_top", true))
			colour = look.get("top", "2f7c7a")
		"Tee":
			wears = true
			colour = look.get("tee", "c9c2b4")
		"Pants":
			wears = true
			colour = look.get("bottom", "2a2a30")
		"Skirt":
			wears = bool(look.get("skirt", false))
			colour = look.get("skirt_colour", "4b6ea6")
		"Apron":
			wears = bool(look.get("apron", false))
			colour = look.get("apron_colour", "e8e2d4")
		"Shoes":
			wears = true
			colour = look.get("shoes", "3a3a44")
		_: wears = false
	mi.visible = wears
	if not wears: return
	if part in ["Eyes", "Bun", "Beard"]: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = FOLK_SHADER
	m.set_shader_parameter("albedo", Color(colour))
	m.set_shader_parameter("rough", 0.8)
	mi.set_surface_override_material(0, m)
	parts.append(mi)

## What they wear drawn as one mesh (and what casts no shadow as another; the eyes, which blink, on their own): one draw a
## pass, not one a part. The same look: each part's colour goes in its vertices, for the same shader.
func _merge_folk() -> void:
	var cast: Array[MeshInstance3D] = []
	var no_cast: Array[MeshInstance3D] = []
	for mi in parts:
		if mi == _eyes: continue
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: no_cast.append(mi)
		else: cast.append(mi)
	var kept: Array[MeshInstance3D] = []
	if _eyes in parts: kept.append(_eyes)
	for group in [cast, no_cast]:
		var one: MeshInstance3D = _merged(group) if group.size() > 1 else null
		if one == null: kept.append_array(group)
		else: kept.append(one)
	parts = kept

## The parts' meshes put end to end, once for each set of parts worn; then this person's colours in their vertices.
func _merged(group: Array[MeshInstance3D]) -> MeshInstance3D:
	for mi in group:     # the same skeleton and skin, placed the same: or they can't be one mesh
		if mi.skin != group[0].skin or mi.skeleton != group[0].skeleton or mi.transform != group[0].transform or mi.mesh.get_surface_count() != 1: return null
	var key := ",".join(group.map(func(mi: MeshInstance3D) -> String: return String(mi.name)))
	if not _folk_shapes.has(key):
		var joined := []
		joined.resize(Mesh.ARRAY_MAX)
		var counts: Array[int] = []
		for mi in group:
			var a: Array = mi.mesh.surface_get_arrays(0)
			var base: int = 0 if joined[Mesh.ARRAY_VERTEX] == null else (joined[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			counts.append((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for i in Mesh.ARRAY_MAX:
				if a[i] == null or i == Mesh.ARRAY_COLOR: continue
				var part = a[i]
				if i == Mesh.ARRAY_INDEX:
					var idx: PackedInt32Array = part
					for k in idx.size(): idx[k] += base
					part = idx
				if joined[i] == null: joined[i] = part.duplicate()
				else: joined[i].append_array(part)
		_folk_shapes[key] = [joined, counts, group[0].mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS]
	var shape: Array = _folk_shapes[key]
	var arrays: Array = (shape[0] as Array).duplicate()
	var colours := PackedColorArray()
	for j in group.size():
		var c: Color = (group[j].get_surface_override_material(0) as ShaderMaterial).get_shader_parameter("albedo")
		var run := PackedColorArray()
		run.resize(shape[1][j])
		run.fill(c)
		colours.append_array(run)
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, shape[2])
	var one := MeshInstance3D.new()
	one.name = "Worn"
	one.mesh = mesh
	one.skin = group[0].skin
	one.transform = group[0].transform
	one.cast_shadow = group[0].cast_shadow
	one.material_override = _folk_material()
	group[0].get_parent().add_child(one)
	one.skeleton = group[0].skeleton
	for mi in group: mi.queue_free()
	return one

static func _folk_material() -> ShaderMaterial:
	if _folk_mat == null:
		_folk_mat = ShaderMaterial.new()
		_folk_mat.shader = FOLK_SHADER
		_folk_mat.set_shader_parameter("colour_in_vertices", true)
		_folk_mat.set_shader_parameter("rough", 0.8)
	return _folk_mat

func _paint(mi: MeshInstance3D, look: Dictionary) -> void:
	var k := 0
	var first := {}              # role -> luminance of its first surface, to keep two-tone outfits' steps
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		var nm := src.resource_name if src else ""
		var orig: Color = (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color(0.7, 0.7, 0.7)
		var role := role_chibi(nm) if _chibi else role_for(mi.name, nm, k)
		if role != "skin": k += 1
		if role == "hide":
			mi.visible = false
			return
		var col := orig
		# an accent with no colour of its own takes the top's, keeping its light-dark step against it
		var ref := "top" if role == "top2" and not look.has("top2") else role
		var want: String = look.get(ref, "")
		if role != "keep" and want != "":
			col = Color(want)
			var lum := orig.get_luminance()
			if first.has(ref): col = col * clampf(lum / maxf(first[ref], 0.02), 0.45, 1.6)
			else: first[ref] = lum
			col.a = 1.0
		mi.set_surface_override_material(i, _mat(col))
	parts.append(mi)

func _mat(col: Color) -> ShaderMaterial:
	var key := col.to_html(false)
	if _mats.has(key): return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = CHAR_SHADER
	m.set_shader_parameter("albedo", col)
	var ink := ShaderMaterial.new()
	ink.shader = INK_SHADER
	m.next_pass = ink
	_mats[key] = m
	return m

## Advance the body by delta at a travel speed (m/s).
func step(speed: float, delta: float) -> void:
	if _ap == null: return
	if legs and use_gait and not _sitting and _once == "":
		if _clip != "Idle":
			_clip = "Idle"
			_ap.play("Idle", FADE)
		_ap.speed_scale = 1.0
		_ap.advance(delta)
		legs.update(delta)
		_blink_and_glance(delta)
		_look_step(delta)
		return
	if _once != "":
		if not _ap.is_playing() or _ap.current_animation != _once:
			_once = ""
	if _sitting:
		# held at the end of sitting down until told to stand
		if _ap.assigned_animation == "SitDown" and (not _ap.is_playing() or _ap.current_animation_position >= _ap.current_animation_length - 0.02):
			_look_step(delta)
			return
	elif _once == "":
		var g := gait(body, speed)
		if g[0] != _clip:
			_clip = g[0]
			_ap.play(_clip, FADE)
		_ap.speed_scale = clampf(float(g[1]), 0.5, 3.2) if _clip != "Idle" else 1.0
	else:
		_ap.speed_scale = 1.0
	_ap.advance(delta)
	_phase = fmod(_phase + delta * _ap.speed_scale / maxf(_ap.current_animation_length, 0.01), 1.0)
	_look_step(delta)

func _blink_and_glance(delta: float) -> void:
	_blink_in -= delta
	if _eyes:
		if _blink_in <= -BLINK:
			_blink_in = randf_range(1.8, 5.5)
		_eyes.visible = _blink_in > 0.0
	if watching == null: return
	var to := global_basis.orthonormalized().inverse() * (watching.global_position - global_position)
	if to.length() < WATCH_WITHIN and to.z > -0.5: look_target = Vector2(clampf(atan2(to.x, to.z), -1.1, 1.1), 0.05)
	else: look_target = look_target.lerp(Vector2.ZERO, delta * 2.0)

## Sit down where it stands (on a bench, a step) and hold it; stand again with sit(false).
func sit(on: bool) -> void:
	if _ap == null or on == _sitting or not _ap.has_animation("SitDown"): return
	_sitting = on
	if on:
		_ap.get_animation("SitDown").loop_mode = Animation.LOOP_NONE
		_ap.speed_scale = 1.0
		_ap.play("SitDown", FADE)
	else:
		gesture("StandUp")

# the head turns from the pose the clip gave it. A clip that's finished (sat down, held) poses nothing: then it's the pose
# it last gave, not last frame's turned head, or the turns would pile up and the head spin.
func _look_step(delta: float) -> void:
	_look = _look.lerp(look_target, 1.0 - exp(-8.0 * delta))
	if _head < 0: return
	_turn(_head, Quaternion(Vector3.UP, _look.x * 0.6) * Quaternion(Vector3.RIGHT, -_look.y * 0.6))
	if _neck >= 0: _turn(_neck, Quaternion(Vector3.UP, _look.x * 0.4) * Quaternion(Vector3.RIGHT, -_look.y * 0.4))

func _turn(bone: int, q: Quaternion) -> void:
	var now := _sk.get_bone_pose_rotation(bone)
	var was: Array = _turned.get(bone, [now, Quaternion(0, 0, 0, 0)])     # [the clip's pose, what was set last]
	if not now.is_equal_approx(was[1]): was[0] = now                     # the clip posed it since
	was[1] = q * was[0]
	_turned[bone] = was
	_sk.set_bone_pose_rotation(bone, was[1])

## A gesture played once over the gait: "Wave", "Interact".
func gesture(clip: String) -> void:
	if _ap == null: return
	for c in ALIAS.get(clip, [clip]):
		if _ap.has_animation(c):
			clip = c
			break
	if not _ap.has_animation(clip): return
	_ap.get_animation(clip).loop_mode = Animation.LOOP_NONE
	_once = clip
	_clip = clip                     # so whatever comes after it starts again
	_ap.play(clip, FADE)

func wave() -> void:
	gesture("Wave")

## 0..1 through the current cycle (the first-person bob used it; kept for the player's API).
func bob() -> float:
	return 0.5 + 0.5 * sin(_phase * TAU * 2.0)
