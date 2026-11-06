extends CharacterBody3D
## Player: camera-relative movement, step counting, and the body it drives (scripts/life/person.gd: a chubby
## rigged character in Arus's colours, its clips played at the speed it moves).

const Person := preload("res://scripts/life/person.gd")
const OUTFIT := "Casual_Male"
const LOOK := {"skin": "a0704e", "hair": "2a1d14", "top": "4f7a3e", "bottom": "2e4a4a", "shoes": "6b4a32"}

const WALK := 4.2               # m/s, as the base version moved
const SPRINT := 1.55
const ACCEL := 14.0
const GRAVITY := 22.0

var rig: Node3D
var site: Node3D = null          # building door we're standing at
var frozen := false
var face_yaw = null              # heading to face instead of the walking direction (first person)
var _vis: Node3D
var avatar: Node3D
var _body_shown := true
var _tick_a := Vector3.ZERO      # body position at the previous and at the latest physics step
var _tick_b := Vector3.ZERO

func _ready() -> void:
	add_to_group("grass_actors")   # the grass parts where it walks (GrassTrails)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)
	floor_snap_length = 0.4
	_build_avatar()
	_tick_a = global_position
	_tick_b = global_position

func _build_avatar() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	avatar = Person.new()
	_vis.add_child(avatar)
	avatar.setup(OUTFIT, LOOK)

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not frozen:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw: float = rig.yaw if rig else 0.0
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var speed := WALK * (SPRINT if Input.is_action_pressed("sprint") else 1.0)
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-ACCEL * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-ACCEL * delta))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	_tick_a = _tick_b
	_tick_b = global_position
	_animate(delta, Vector2(velocity.x, velocity.z))

func _animate(delta: float, v: Vector2) -> void:
	var spd := v.length()
	if face_yaw != null:
		_vis.rotation.y = lerp_angle(_vis.rotation.y, face_yaw, 1.0 - exp(-12.0 * delta))
	elif spd > 0.3:
		var want := atan2(v.x, v.y)
		_vis.rotation.y = lerp_angle(_vis.rotation.y, want, 1.0 - exp(-12.0 * delta))
	# the head looks where the camera looks, within the neck's reach; not back over the shoulder at it
	var look := Vector2.ZERO
	if rig and face_yaw == null:
		var dy := angle_difference(_vis.rotation.y, float(rig._yaw) + PI)
		if absf(dy) < deg_to_rad(100.0): look = Vector2(dy, clampf(-float(rig._pitch) * 0.4, -0.35, 0.35))
	avatar.look_target = look
	avatar.step(spd, delta)

func _process(_delta: float) -> void:
	_vis.position = smooth_position() - global_position

## Where the body is drawn this frame: between its last two physics positions, so it glides at any frame
## rate. The camera follows this point too.
func smooth_position() -> Vector3:
	if not global_position.is_equal_approx(_tick_b):    # moved outside the physics step (a tween, a teleport)
		_tick_a = global_position
		_tick_b = global_position
	return _tick_a.lerp(_tick_b, Engine.get_physics_interpolation_fraction())

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
