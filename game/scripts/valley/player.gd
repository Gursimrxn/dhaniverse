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
# the feel of the three.js client (game-core tuning.rs, player.ts): straight-line speeding up and a firmer stop, the body turned
# to the input at an eased 12/s, leaned into starts, stops and turns, and a step up climbed in a few frames
const ACCEL := 20.0              # m/s² speeding up
const DECEL := 26.0              # m/s² slowing down, or asked for another way
const TURN_RATE := 12.0          # /s: the rate of the eased turn to face the input
const GRAVITY := 22.0
const TERMINAL := 30.0           # m/s: the fastest fall
const MAX_SLOPE := 46.0          # deg: the steepest walkable slope
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
var _heading = null              # where the input points (radians, 0 facing +Z); null with no input
var _air := 0.0                  # s since the feet left the ground
var _turning := false            # turning on the spot: the legs step round
var _vis_y := NAN                # the drawn height, on a spring so a step up is climbed, not jumped
var _vis_vy := 0.0
var _last_yaw := 0.0
var _speed_was := 0.0
var _accel := 0.0                # m/s², smoothed: the lean reads it
var _lean := Vector2.ZERO        # radians: forward (x), over into a turn (y)

func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(MAX_SLOPE)
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
		_heading = null
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
	_heading = atan2(dir.x, dir.z) if dir.length_squared() > 1e-6 else null
	# towards the input in a straight line, faster when it asks for less or for another way
	var target := Vector2(dir.x, dir.z) * speed
	var drive := Vector2(velocity.x, velocity.z)
	var speeding_up := target.length_squared() >= drive.length_squared() and target.dot(drive) >= 0.0
	drive = drive.move_toward(target, (ACCEL if speeding_up else DECEL) * delta)
	velocity.x = drive.x
	velocity.z = drive.y
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -TERMINAL)
		_air += delta
	else:
		velocity.y = -0.5
		_air = 0.0
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
	# turning on the spot past 100 deg steps the feet round until within 30 deg (game-core anim.rs)
	var off := absf(angle_difference(_vis.rotation.y, _heading)) if _heading != null else 0.0
	_turning = _heading != null and ((off > deg_to_rad(100.0) and spd < 1.0) or (_turning and off > deg_to_rad(30.0)))
	if face_yaw != null:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, face_yaw, 1.0 - exp(-TURN_RATE * delta))
	elif _heading != null:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, _heading, 1.0 - exp(-TURN_RATE * delta))
	elif rest_yaw != null:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, rest_yaw, 1.0 - exp(-10.0 * delta))
	# the lean: forward into speeding up, back into stopping, over into a turn; a little more at a run (player.ts)
	var yaw_rate := angle_difference(_last_yaw, _vis.rotation.y) / delta
	_last_yaw = _vis.rotation.y
	_accel = lerpf(_accel, (spd - _speed_was) / delta, 1.0 - exp(-10.0 * delta))
	_speed_was = spd
	var run_lean := clampf((spd - WALK) / 2.2, 0.0, 1.0) * 0.07
	_lean.x = lerpf(_lean.x, clampf(_accel * 0.012, -0.12, 0.1) + run_lean, 1.0 - exp(-10.0 * delta))
	_lean.y = lerpf(_lean.y, clampf(-yaw_rate * spd * 0.02, -0.18, 0.18), 1.0 - exp(-8.0 * delta))
	avatar.rotation = Vector3(_lean.x, 0.0, _lean.y)
	# the head looks where the camera looks, within the neck's reach; not back over the shoulder at it
	var look := Vector2.ZERO
	if rig and face_yaw == null:
		var dy := angle_difference(_vis.rotation.y, float(rig._yaw) + PI)
		if absf(dy) < deg_to_rad(100.0): look = Vector2(dy, clampf(-float(rig._pitch) * 0.4, -0.35, 0.35))
	avatar.look_target = look
	avatar.step(maxf(spd, 0.7) if _turning else spd, delta, _air)

## The body is posed every frame where it's drawn, so its feet stay put on the ground between physics steps.
func _process(delta: float) -> void:
	if delta <= 0.0: return
	# a step up arrives in one physics tick: the drawn body climbs it in a few frames instead (player.ts visY)
	var y := _interpolated().y
	if is_nan(_vis_y) or absf(y - _vis_y) > 1.5:
		_vis_y = y
		_vis_vy = 0.0
	else:
		var s := _spring(Vector2(_vis_y, _vis_vy), y, 0.07 if y > _vis_y else 0.03, delta)
		_vis_y = s.x
		_vis_vy = s.y
	_vis.global_position = smooth_position()
	_animate(delta, Vector2(velocity.x, velocity.z))

## Where the body is drawn this frame (between its last two physics steps). The camera follows this point too.
func smooth_position() -> Vector3:
	var p := _interpolated()
	if not is_nan(_vis_y): p.y = _vis_y
	return p

func _interpolated() -> Vector3:
	return get_global_transform_interpolated().origin if is_inside_tree() else global_position

## Critically damped spring (Game Programming Gems 4, 1.10; three.js camera.ts): (x, v) towards target over smooth time t, no overshoot.
static func _spring(s: Vector2, target: float, t: float, delta: float) -> Vector2:
	var w := 2.0 / t
	var x := w * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var c := s.x - target
	var tmp := (s.y + w * c) * delta
	return Vector2(target + (c + tmp) * e, (s.y - w * tmp) * e)

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
