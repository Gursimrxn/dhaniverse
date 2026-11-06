extends CharacterBody3D
## Player: camera-relative movement and the body (scripts/valley/hero.gd) it drives.

const Avatar := preload("res://scripts/valley/hero.gd")

const WALK := 3.4               # m/s: a small body at a brisk walk
const ON_SCOOTER := 11.5         # m/s
const SEAT_LIFT := 0.37          # m: sitting on it, over sitting on the ground
const SCOOTER_SIZE := 0.75       # its model is for a bigger body
const SCOOTER_AHEAD := 0.2       # m its middle is ahead of him: he's on the seat, not over the bars
# in his skeleton's units: where his feet and hands go, how far he leans
const RIDE_FOOT_Y := -0.5
const RIDE_FOOT_FORWARD := 0.9
const RIDE_GRIPS: Array[Vector3] = [Vector3(0.52, 1.2, 1.25), Vector3(-0.52, 1.2, 1.25)]
const RIDE_LEAN := 0.42
const SPRINT := 1.65
const ACCEL := 9.0               # he has weight: a moment to get going, and to stop
const GRAVITY := 22.0
const STEP_H := 0.5             # the highest kerb or stair the player walks up
const STEP_REACH := 0.2         # how far ahead of the body it looks for one

signal footstep(at: Vector3, heavy: float)

var rig: Node3D
var site: Node3D = null          # building door we're standing at
var frozen := false
var riding: Node3D = null        # on a boat: stands at this point and goes where it goes
var on_scooter := false
var dev_walk = null              # dev: a point (x, z) to walk straight at, with no keyboard (world.gd --walk)
var face_yaw = null              # heading to face instead of the walking direction (first person)
var rest_yaw = null              # heading to turn to when standing still (behind a counter: towards it)
var _vis: Node3D
var avatar: Node3D
var _body_shown := true

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)
	floor_snap_length = 0.4
	_build_avatar()

func _build_avatar() -> void:
	_vis = Node3D.new()
	_vis.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # placed by hand each frame, where the engine draws the body
	add_child(_vis)
	avatar = Avatar.new()
	avatar.floor_exclude = get_rid()
	_vis.add_child(avatar)
	avatar.gait.stepped.connect(func(at: Vector3, heavy: float): footstep.emit(at, heavy))

func _physics_process(delta: float) -> void:
	if riding:
		global_position = riding.global_position
		velocity = Vector3.ZERO
		return
	var input := Vector2.ZERO
	if not frozen:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw: float = rig.yaw if rig else 0.0
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var speed := ON_SCOOTER if on_scooter else WALK * (SPRINT if Input.is_action_pressed("sprint") else 1.0)
	if dev_walk != null:
		var to := (dev_walk as Vector2) - Vector2(global_position.x, global_position.z)
		dir = Vector3(to.x, 0, to.y).normalized() if to.length() > 0.3 else Vector3.ZERO
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-ACCEL * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-ACCEL * delta))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	_step_up(Vector3(velocity.x, 0, velocity.z) * delta)
	move_and_slide()

## Up kerbs, doorsteps and stairs: if walking is blocked here but clear STEP_H higher, stand on what is ahead
## in one move (only lifting would let gravity pull the body straight back off the edge).
func _step_up(motion: Vector3) -> void:
	if motion.length() < 1e-4 or (not is_on_floor() and velocity.y > 1.0): return
	var ahead := motion.normalized() * STEP_REACH
	var from := global_transform
	if not test_move(from, ahead): return
	var up := Vector3.UP * STEP_H
	if test_move(from, up): return
	var raised := from.translated(up)
	if test_move(raised, ahead): return
	var hit := KinematicCollision3D.new()
	var lifted := raised.translated(ahead)
	if not test_move(lifted, -up * 1.2, hit): return
	var top := lifted.origin - Vector3.UP * hit.get_travel().length()
	if top.y > from.origin.y + 0.01:
		global_position = top + Vector3.UP * 0.01
		velocity.y = 0.0

func _animate(delta: float, v: Vector2) -> void:
	var spd := v.length()
	if face_yaw != null:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, face_yaw, 1.0 - exp(-12.0 * delta))
	elif spd > 0.3:
		var want := atan2(v.x, v.y)
		_vis.rotation.y = lerp_angle(_vis.rotation.y, want, 1.0 - exp(-12.0 * delta))
	elif rest_yaw != null:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, rest_yaw, 1.0 - exp(-10.0 * delta))
	# the head looks where the camera looks, within the neck's reach; not back over the shoulder at it
	var look := Vector2.ZERO
	if rig and face_yaw == null:
		var dy := angle_difference(_vis.rotation.y, float(rig._yaw) + PI)
		if absf(dy) < deg_to_rad(100.0): look = Vector2(dy, clampf(-float(rig._pitch) * 0.4, -0.35, 0.35))
	avatar.look_target = look
	avatar.step(spd, delta)

## The body is posed every frame where it's drawn, so its feet stay put on the ground between physics steps.
func _process(delta: float) -> void:
	_vis.global_position = smooth_position()
	_animate(delta, Vector2(velocity.x, velocity.z))

## Where the body is drawn this frame (between its last two physics steps). The camera follows this point too.
func smooth_position() -> Vector3:
	return get_global_transform_interpolated().origin if is_inside_tree() else global_position

## On the scooter or off it. The scooter is the caller's to place: it goes under the node this gives.
func set_on_scooter(on: bool) -> Node3D:
	on_scooter = on
	avatar.ride_pose(RIDE_FOOT_Y, RIDE_FOOT_FORWARD, RIDE_GRIPS, RIDE_LEAN)
	avatar.set_sitting(on)
	avatar.position.y = SEAT_LIFT if on else 0.0
	return _vis

## How the scooter sits under him.
static func scooter_under() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * SCOOTER_SIZE), Vector3(0.0, 0.0, SCOOTER_AHEAD))

## Which way the body faces, for the others to see.
func body_yaw() -> float:
	return _vis.rotation.y

## First person hides the avatar from the camera but keeps its shadow on the ground.
func set_body_visible(on: bool) -> void:
	if on == _body_shown: return
	_body_shown = on
	for mi in avatar.parts:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

## 0..1 bounce of the walk cycle, for the first-person head bob.
func walk_bob() -> float:
	return avatar.bob()

func near_site(s: Node3D) -> void:
	site = s

func left_site(s: Node3D) -> void:
	if site == s: site = null

func wave() -> void:
	avatar.wave()
