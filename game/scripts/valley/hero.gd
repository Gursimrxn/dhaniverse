extends Node3D
## The player's body: assets/characters/cozy_boy/cozy_boy.glb (tools/blender/cozy_boy.py), a boy in parts on the
## Quaternius chibi skeleton, played by its own clips: Idle, Walk and Run at exactly the speed he travels (the
## chibi legs' measured gait, dev/measure_gait.gd), cross-faded as the speed changes; the head turns after the
## clip towards look_target. Every part is a node named by its group (Beanie_*, Hair_*, Sunglasses_*, Flannel_*,
## Bag_*, ...) so it can be hidden or swapped: set_part_visible("Bag", false).
## Same interface as the old avatar: parts, look_target, step(), bob(), wave().

const MODEL := "res://assets/characters/cozy_boy/cozy_boy.glb"
const SCALE := 0.4375            # 3.28 units -> 1.43 m, as the chibi characters
const HEIGHT := 1.0              # how tall he is, against that 1.43 m: the one value to change (-- --height=1.15 tries one)
# Locomotion as the three.js client had it (packages/engine/src/actors/anim.ts, player.ts): Idle, Walk and Run blended by the
# real ground speed on one shared phase, the phase moved on by the measured stride so the feet don't slide; one-shots and the
# fall pose crossfaded over about 0.15 s; the feet put onto sloping ground by two-bone IK after the clips.
const WALK_CLIP_SPEED := 0.98    # m/s of ground at playback rate 1, from the planted foot (game-core tuning.rs)
const RUN_CLIP_SPEED := 1.89     # (the left foot: the clip's right foot skates)
const CONTACT := Vector2(0.12, 0.22)   # where in the cycle the right foot lands, walk and run (the left half a cycle on)
const SHOT_FADE := 0.15          # s a one-shot takes to fade in or out (three.js FADE_RATE 16/s)
const FALL_AFTER := 0.1          # s in the air before the fall pose (game-core: 6 ticks)
const FALL_AT := 0.45            # of the Jump clip: mid-air
const STAND_IN := {"Interact": "PickUp"}   # one-shots this body has no clip for
const SHADER := preload("res://shaders/valley/character.gdshader")
const CARRY_FADE := 0.14         # s for the arm to come up to carry, or to drop
# carrying: his right arm as a waiter's, the upper arm out and down, the forearm up and forward, the thing on his palm where
# the camera behind him sees it. Directions in his own frame: x to his left, y up, z ahead
const CARRY_UPPER := Vector3(-0.62, -0.72, 0.3)
const CARRY_LOWER := Vector3(-0.1, 0.7, 0.7)
const HELD_AT := Vector3(0.0, 0.07, 0.0)   # from his fist (m)
const HELD_SIZE := 1.2           # his hands are large: what he carries is drawn to match
const REACH_OUT := 0.14          # s for the arm to go out to something
const REACH_BACK := 0.2          # s for it to come back
const REACH_DROP := 0.25         # how far below the line to it the upper arm hangs, as a straight arm does not look reached

var parts: Array[MeshInstance3D] = []
var height := HEIGHT
var look_target := Vector2.ZERO
var _ap: AnimationPlayer
var _sk: Skeleton3D
var _head := -1
var _neck := -1
var _tree: AnimationTree
var _shot: AnimationNodeAnimation
var _model: Node3D
var _legs: Array = []            # [upper, lower, foot] bone indices, right leg first (foot 0 lands first)
var _foot_dy := PackedFloat32Array([0.0, 0.0])   # m each foot is moved off the clip to meet the ground
var _hips := 0.0                 # m the body is lowered so the lower foot reaches
var _fall := 0.0
var _cycle_m := Vector2(1.225, 1.654)   # m per walk and run cycle (clip speed x clip length), set from the clips
var gait: Gait                   # the procedural legs: only while sitting (a scooter); clips walk him otherwise
var floor_exclude := RID()       # the body's own collider, when it has one
var _sitting := false
var _look := Vector2.ZERO
var _phase := 0.0
var _upper := -1
var _lower := -1
var _carrying := false
var _carry := 0.0                # 0..1: how far the arm has come up
var _hands: BoneAttachment3D
var _reach_t := -1.0             # s into a reach; < 0: none
var _reach_at := Vector3.ZERO    # what it reaches for (world)
var _on_reach := Callable()      # called when the hand is furthest out
var _held_from := Vector3.ZERO   # where the thing just taken came from (world)
var _held_k := 1.0               # 0..1 of its way from there to his hand
var _looking_at := Vector3.ZERO  # something he's dealing with
var _looking_for := 0.0          # s he goes on looking at it
var _reaching := 0.0
var _asleep_for := 0.0
var _chew := 0.0                 # s of chewing left
var _sway := Vector3.ZERO        # how far hem and hair trail behind him
var _sway_v := Vector3.ZERO
var _last_at := Vector3.INF
var _trailing: Array[ShaderMaterial] = []   # the materials that swing: the jacket's and the hair's
const SWAY_PULL := 0.045         # model units per m/s
const SWAY_SPRING := 60.0
const SWAY_DAMP := 7.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--height="): height = float(a.trim_prefix("--height="))
	var n: Node3D = (load(MODEL) as PackedScene).instantiate()
	n.scale = Vector3.ONE * SCALE * height
	add_child(n)
	_ap = n.find_children("*", "AnimationPlayer", true, false)[0]
	_sk = n.find_children("*", "Skeleton3D", true, false)[0]
	_head = _sk.find_bone("Head")
	_neck = _sk.find_bone("Neck")
	_model = n
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.active = false               # the tree below plays his clips
	for c in ["Idle", "Walk", "Run"]:
		if _ap.has_animation(c): _ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	var mats := {}
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var key: String = src.resource_name if src else ""
			if not mats.has(key):
				mats[key] = _material(src)
				if key == "flannel_plaid":
					mats[key].set_shader_parameter("trail_from", 1.75)
					mats[key].set_shader_parameter("trail_to", 1.0)
					_trailing.append(mats[key])
				elif key == "hair":
					mats[key].set_shader_parameter("trail_from", 2.95)
					mats[key].set_shader_parameter("trail_to", 3.5)
					_trailing.append(mats[key])
			mi.set_surface_override_material(i, mats[key])
		parts.append(mi)
	for side in ["R", "L"]:
		_legs.append([_sk.find_bone("UpperLeg." + side), _sk.find_bone("LowerLeg." + side), _sk.find_bone("Foot." + side)])
	_upper = _sk.find_bone("UpperArm.R")
	_lower = _sk.find_bone("LowerArm.R")
	_hands = BoneAttachment3D.new()
	_hands.bone_name = "Fist.R"
	_sk.add_child(_hands)
	gait = Gait.new(_sk, self)
	gait.floor_ray = func(from: Vector3, to: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		if floor_exclude.is_valid(): q.exclude = [floor_exclude]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		return hit.position.y if hit else INF

## idle -+
##       move -- air -- shot -- out      phase seeks walk and run together (each stretched to a 1 s timeline)
## walk -+                               so the run's share is a blend on one stride, never a clip switch
##   stride -- phase -+
## run --+
func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var anim := func(clip: String) -> AnimationNodeAnimation:
		var a := AnimationNodeAnimation.new()
		a.animation = clip
		return a
	var cycle := func(clip: String) -> AnimationNodeAnimation:
		var a: AnimationNodeAnimation = anim.call(clip)
		a.use_custom_timeline = true
		a.timeline_length = 1.0
		a.stretch_time_scale = true
		a.loop_mode = Animation.LOOP_LINEAR
		return a
	bt.add_node("idle", anim.call("Idle"))
	bt.add_node("walk", cycle.call("Walk"))
	bt.add_node("run", cycle.call("Run"))
	bt.add_node("stride", AnimationNodeBlend2.new())
	bt.add_node("phase", AnimationNodeTimeSeek.new())
	bt.add_node("move", AnimationNodeBlend2.new())
	bt.add_node("jump", anim.call("Jump"))
	bt.add_node("hang", AnimationNodeTimeScale.new())
	bt.add_node("fall_at", AnimationNodeTimeSeek.new())
	bt.add_node("air", AnimationNodeBlend2.new())
	_shot = anim.call("Victory")
	bt.add_node("gesture", _shot)
	var one := AnimationNodeOneShot.new()
	one.fadein_time = SHOT_FADE
	one.fadeout_time = SHOT_FADE
	bt.add_node("shot", one)
	bt.connect_node("stride", 0, "walk")
	bt.connect_node("stride", 1, "run")
	bt.connect_node("phase", 0, "stride")
	bt.connect_node("move", 0, "idle")
	bt.connect_node("move", 1, "phase")
	bt.connect_node("hang", 0, "jump")
	bt.connect_node("fall_at", 0, "hang")
	bt.connect_node("air", 0, "move")
	bt.connect_node("air", 1, "fall_at")
	bt.connect_node("shot", 0, "air")
	bt.connect_node("shot", 1, "gesture")
	bt.connect_node("output", 0, "shot")
	_tree = AnimationTree.new()
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.get_parent().add_child(_tree)     # beside the player, so the tracks' paths resolve from the same root
	_tree.tree_root = bt
	_tree.anim_player = _tree.get_path_to(_ap)
	_tree.set("parameters/hang/scale", 0.0)
	_tree.active = true
	for i in 2:
		var c: String = ["Walk", "Run"][i]
		if _ap.has_animation(c): _cycle_m[i] = [WALK_CLIP_SPEED, RUN_CLIP_SPEED][i] * _ap.get_animation(c).length

## Arm up to carry, or down.
func set_carrying(on: bool) -> void:
	_carrying = on

## Put a thing in his hand, flying there from a point in the world (it goes when freed or taken back out). The caller says
## set_carrying.
func hold(item: Node3D, from: Vector3) -> void:
	_hands.add_child(item)
	_held_from = from
	_held_k = 0.0

## Reach out for a point in the world and come back; on_peak is called when the hand is furthest out. His legs keep walking.
func reach(point: Vector3, on_peak := Callable()) -> void:
	_fire_reach()      # one still on its way out finishes what it was doing
	_reach_at = point
	_reach_t = 0.0
	_on_reach = on_peak
	_looking_at = point
	_looking_for = REACH_OUT + REACH_BACK + 0.3

func _fire_reach() -> void:
	var call := _on_reach
	_on_reach = Callable()
	if call.is_valid(): call.call()

## He leans toward what he's reaching for, and looks at it.
func _lean_to_reach(delta: float) -> void:
	_looking_for = maxf(_looking_for - delta, 0.0)
	var out := 0.0
	if _reach_t >= 0.0: out = smoothstep(0.0, REACH_OUT, _reach_t) * (1.0 - smoothstep(REACH_OUT, REACH_OUT + REACH_BACK, _reach_t))
	_reaching = lerpf(_reaching, out, 1.0 - exp(-14.0 * delta))
	if _reaching > 0.01:
		var torso := _sk.find_bone("Torso")
		_sk.set_bone_pose_rotation(torso, Quaternion(Vector3.RIGHT, 0.28 * _reaching) * _sk.get_bone_pose_rotation(torso))

## Pose his right arm over the clip: carrying, reaching, or the blend of the two.
func _pose_arm(delta: float) -> void:
	_carry = move_toward(_carry, 1.0 if _carrying else 0.0, delta / CARRY_FADE)
	var out := 0.0
	if _reach_t >= 0.0:
		_reach_t += delta
		if _reach_t >= REACH_OUT: _fire_reach()
		out = smoothstep(0.0, REACH_OUT, _reach_t) * (1.0 - smoothstep(REACH_OUT, REACH_OUT + REACH_BACK, _reach_t))
		if _reach_t >= REACH_OUT + REACH_BACK: _reach_t = -1.0
	var w := maxf(_carry, out)
	if w <= 0.0: return
	var to_sk := _sk.global_basis.orthonormalized().inverse()
	var mine := to_sk * global_basis.orthonormalized()
	var at := (_reach_at - _sk.to_global(_sk.get_bone_global_pose(_upper).origin)).normalized()
	var upper := (mine * CARRY_UPPER).normalized().lerp((to_sk * (at + Vector3.DOWN * REACH_DROP)).normalized(), out)
	var lower := (mine * CARRY_LOWER).normalized().lerp((to_sk * at).normalized(), out)
	_aim(_upper, upper, w)
	_aim(_lower, lower, w)

## Turn a bone so it points along a direction (skeleton's frame; bones lie along their own +Y).
func _aim(bone: int, dir: Vector3, w: float) -> void:
	var parent := _sk.get_bone_global_pose(_sk.get_bone_parent(bone)).basis.orthonormalized()
	var now := _sk.get_bone_pose_rotation(bone)
	var g := parent * Basis(now)
	var aimed := Basis(Quaternion(g.y.normalized(), dir.normalized())) * g
	_sk.set_bone_pose_rotation(bone, now.slerp((parent.inverse() * aimed).get_rotation_quaternion(), w))

## The glTF material's own colour, texture, roughness and metalness, on the valley's light.
func _material(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		m.set_shader_parameter("albedo", b.albedo_color)     # sRGB, as the shader expects
		if b.albedo_texture: m.set_shader_parameter("albedo_tex", b.albedo_texture)
		m.set_shader_parameter("rough", b.roughness)
		m.set_shader_parameter("metal", b.metallic)
	return m

## Show or hide every part of a group: "Beanie", "Hair", "Sunglasses", "Headphones", "Flannel", "Tee", "Bag", ...
func set_part_visible(group: String, on: bool) -> void:
	for mi in parts:
		if String(mi.name) == group or String(mi.name).begins_with(group + "_"): mi.visible = on

## Advance the body by delta at a travel speed (m/s); `air`: s since the feet left the ground (0 on it).
func step(speed: float, delta: float, air := 0.0) -> void:
	if _tree == null: return
	if not gait.enabled or gait.sitting > 0.0: speed = 0.0     # lying, or sat: the clips stand still under him
	var run := smoothstep(1.0, 1.8, speed)
	var from := _phase
	if speed >= 0.05:
		_phase += speed * delta / (lerpf(_cycle_m.x, _cycle_m.y, run) * height)
		var c := lerpf(CONTACT.x, CONTACT.y, run)
		for foot in 2:
			var at := c + foot * 0.5
			if ((from < at and _phase >= at) or (from < at + 1.0 and _phase >= at + 1.0)) and air <= 0.0 and speed > 0.3:
				gait.stepped.emit(_sk.to_global(_sk.get_bone_global_pose(_legs[foot][2]).origin), clampf(speed / Gait.SPEED_FAST, 0.0, 1.0))
				break
		_phase = fmod(_phase, 1.0)
	_fall = lerpf(_fall, 1.0 if air > FALL_AFTER and gait.enabled else 0.0, 1.0 - exp(-16.0 * delta))
	_tree.set("parameters/move/blend_amount", smoothstep(0.05, 0.5, speed))
	_tree.set("parameters/stride/blend_amount", run)
	_tree.set("parameters/phase/seek_request", _phase)
	_tree.set("parameters/air/blend_amount", _fall)
	if _fall > 0.001: _tree.set("parameters/fall_at/seek_request", FALL_AT * _ap.get_animation("Jump").length)
	_tree.advance(delta)
	if gait.sitting > 0.0:
		gait.carrying_right = _carrying or _reach_t >= 0.0 or _carry > 0.0
		gait.update(delta)
	else:
		_plant_feet(delta, air <= 0.0)
	_pose_arm(delta)
	_lean_to_reach(delta)
	_held_k = minf(_held_k + delta / (REACH_OUT + REACH_BACK * 0.5), 1.0)
	for item in _hands.get_children():    # it stays level whatever his fist does
		var level := Basis(Vector3.UP, global_rotation.y)
		var hand := _sk.to_global(_sk.get_bone_global_pose(_hands.bone_idx).origin) + level * HELD_AT
		(item as Node3D).global_transform = Transform3D(level.scaled(Vector3.ONE * HELD_SIZE), _held_from.lerp(hand, smoothstep(0.0, 1.0, _held_k)))
	# the head turns after the clip has posed it
	_swing_hem(delta)
	if gait and not gait.enabled:      # asleep: nothing moves but his chest
		_asleep_for += delta
		var torso := _sk.find_bone("Torso")
		_sk.set_bone_pose_rotation(torso, Quaternion(Vector3.RIGHT, sin(_asleep_for * 1.5) * 0.035) * _sk.get_bone_pose_rotation(torso))
	if _chew > 0.0:
		_chew -= delta
		_sk.set_bone_pose_rotation(_head, Quaternion(Vector3.RIGHT, sin(_chew * 34.0) * 0.05) * _sk.get_bone_pose_rotation(_head))
	var want := look_target
	if _looking_for > 0.0:
		var to := global_basis.orthonormalized().inverse() * (_looking_at - global_position)
		want = Vector2(clampf(atan2(to.x, to.z), -1.2, 1.2), clampf(atan2(to.y - 1.1, Vector2(to.x, to.z).length()), -0.5, 0.5))
	_look = _look.lerp(want, 1.0 - exp(-9.0 * delta))
	if _head >= 0 and _look.length() > 0.001:
		_sk.set_bone_pose_rotation(_head, Quaternion(Vector3.UP, _look.x * 0.6) * Quaternion(Vector3.RIGHT, -_look.y * 0.6) * _sk.get_bone_pose_rotation(_head))
		if _neck >= 0:
			_sk.set_bone_pose_rotation(_neck, Quaternion(Vector3.UP, _look.x * 0.4) * Quaternion(Vector3.RIGHT, -_look.y * 0.4) * _sk.get_bone_pose_rotation(_neck))

## The legs' IK (three.js player.ts plantFeet): each foot onto the floor under it, the hips lowered as far as the lower foot
## needs. Only standing on what is under the body's middle: on a kerb's edge the collider has the feet already.
func _plant_feet(delta: float, grounded: bool) -> void:
	var k := 1.0 - exp(-15.0 * delta)
	var at := global_position
	var base: float = gait.floor_ray.call(at + Vector3.UP * 0.7, at + Vector3.DOWN * 0.9)
	var on := grounded and base != INF and absf(base - at.y) < 0.1
	for i in 2:
		var want := 0.0
		if on:
			var p := _sk.to_global(_sk.get_bone_global_pose(_legs[i][2]).origin)
			var y: float = gait.floor_ray.call(Vector3(p.x, base + 0.7, p.z), Vector3(p.x, base - 0.9, p.z))
			if y != INF: want = clampf(y - base, -0.25, 0.25)
		_foot_dy[i] = lerpf(_foot_dy[i], want, k)
	_hips = lerpf(_hips, minf(0.0, minf(_foot_dy[0], _foot_dy[1])), k)
	_model.position.y = _hips
	if absf(_foot_dy[0]) + absf(_foot_dy[1]) < 0.005: return
	var to_sk := _sk.global_basis.inverse()
	for i in 2:
		var leg: Array = _legs[i]
		var hip := _sk.get_bone_global_pose(leg[0]).origin
		var knee := _sk.get_bone_global_pose(leg[1]).origin
		var ankle := _sk.get_bone_global_pose(leg[2]).origin
		var target := ankle + to_sk * (Vector3.UP * (_foot_dy[i] - _hips))
		var a := knee.distance_to(hip)
		var b := ankle.distance_to(knee)
		var to := target - hip
		var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
		var dir := to.normalized()
		var bend := (knee - hip) - dir * (knee - hip).dot(dir)    # the knee stays in the plane it bends in now
		if bend.length_squared() < 1e-10: continue                 # a straight leg has no plane: leave the clip's pose
		var along := (d * d + a * a - b * b) / (2.0 * d)
		var new_knee := hip + dir * along + bend.normalized() * sqrt(maxf(a * a - along * along, 0.0))
		_aim(leg[0], new_knee - hip, 1.0)
		_aim(leg[1], hip + dir * d - new_knee, 1.0)

## Sit and stay sat (a scooter), or get up.
func set_sitting(on: bool) -> void:
	_sitting = on
	if gait: gait.sitting = 1.0 if on else 0.0

## Astride something: feet at this height and this far ahead, hands where it's held, leaning into it. All in the skeleton's units.
func ride_pose(foot_y: float, forward: float, grips: Array, lean: float) -> void:
	gait.seat_foot_y = foot_y
	gait.seat_forward = forward
	gait.grips = grips
	gait.sit_lean = lean

## Lying down: the feet have nothing to plant on, and the clip has him.
func set_lying(on: bool) -> void:
	gait.enabled = not on
	if on: gait.sitting = 0.0

## A bite of what's in his hand: to his mouth and back.
func bite() -> void:
	var head := _sk.to_global(_sk.get_bone_global_pose(_head).origin) + global_basis.orthonormalized().z * 0.13 + Vector3.UP * 0.02
	reach(head)
	_chew = 0.5

## Hem and hair trail after him on a spring, and swing back when he stops.
func _swing_hem(delta: float) -> void:
	var at := global_position
	if _last_at == Vector3.INF: _last_at = at
	var v := (at - _last_at) / maxf(delta, 0.001)
	_last_at = at
	if v.length() > 20.0: v = Vector3.ZERO
	var local := global_basis.orthonormalized().inverse() * v
	var want := -Vector3(local.x, 0.0, local.z) * SWAY_PULL
	_sway_v += (want - _sway) * SWAY_SPRING * delta - _sway_v * SWAY_DAMP * delta
	_sway += _sway_v * delta
	for m in _trailing: m.set_shader_parameter("trail", _sway)

## A clip played once over the gait.
func gesture(clip: String) -> void:
	if _tree == null: return
	if not _ap.has_animation(clip): clip = STAND_IN.get(clip, "")
	if clip == "": return
	_ap.get_animation(clip).loop_mode = Animation.LOOP_NONE
	_shot.animation = clip
	_tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func wave() -> void:
	gesture("Victory")

## 0..1 through the current cycle (the first-person head bob).
func bob() -> float:
	return 0.5 + 0.5 * sin(_phase * TAU * 2.0)
