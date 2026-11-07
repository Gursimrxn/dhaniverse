class_name OtherPlayer
extends Node3D
## Someone else in town. A player has the player's own body and is drawn a moment behind what the server last said, so they glide
## between its few updates a second. A resident is a townsperson: the server only names the place they're off to, and here they
## walk the paved way there and find a spot of their own, shifting about while they're there.

const HeroScript := preload("res://scripts/valley/hero.gd")
const PersonScript := preload("res://scripts/life/person.gd")
const FIRST_FROM := 1.5            # m: where they first stand isn't known yet; the square's raised floor, but not an awning
const BEHIND := 0.25               # s: how far back a player is drawn, so there's always a next point to go towards
const SNAP_OVER := 8.0             # m in one update: a sleep or a door, not a walk
const TAG_OVER := 1.95             # m
const TAG_WITHIN := 7.0            # m from the camera: a name is for someone you've come up to
const TURN := 7.0
const WALK := 1.3                  # m/s, a resident
const GROUND_EVERY := 0.2          # s between looking for the floor under a resident
const SHIFT_EVERY := Vector2(7.0, 22.0)   # s between a resident moving to another spot where they are
const SEEN_TO := 42.0              # m from the camera: further off they aren't drawn, or posed
const CLOSE := 11.0                # m: within this, posed every frame; further off, every third
# each place: the way to it from the square, and where people stand when there (middle, half size)
const SQUARE := Vector3(-27.0, 0.0, -6.0)
const WAYS := {
	"square": [],
	"market": [Vector3(-20.0, 0.0, -12.5), Vector3(-20.0, 0.0, -20.0)],
	"bank": [Vector3(-27.2, 0.0, 3.0), Vector3(-27.2, 0.0, 12.0)],
	"table": [Vector3(8.5, 0.0, 6.0), Vector3(8.5, 0.0, 12.0)],
	"homes": [Vector3(-51.0, 0.0, 2.0), Vector3(-51.0, 0.0, 28.0), Vector3(-45.5, 0.0, 33.0)],
}
const SPOTS := {
	"square": [Vector3(-27.0, 0.0, -6.0), Vector2(11.0, 4.5)],
	"market": [Vector3(-22.0, 0.0, -22.0), Vector2(9.0, 3.0)],
	"bank": [Vector3(-27.0, 0.0, 14.0), Vector2(4.0, 2.0)],
	"table": [Vector3(13.0, 0.0, 15.5), Vector2(4.0, 2.5)],
	"homes": [Vector3(-45.5, 0.0, 35.0), Vector2(4.0, 2.5)],
}

var resident := false
var _body: Node3D
var _tag: KeyHint
var _points: Array = []            # a player: [time, position, yaw], oldest first
var _speed := 0.0
var _place := ""                   # a resident: where they are or are off to
var _path: Array[Vector3] = []     # a resident: the rest of the way
var _shift_in := 0.0
var _ground_in := 0.0
var _ground_y := 0.0
var _rng := RandomNumberGenerator.new()
var _scooter: Node3D
var _pose_in := 0
var _pose_delta := 0.0

func setup(who: String, _title: String, is_resident: bool, tags: Control) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # moved every frame by hand
	resident = is_resident
	if resident:
		_body = PersonScript.new()
		add_child(_body)
		var h := who.hash()
		_rng.seed = h
		_body.setup("folk", PersonScript.folk_look(h))
	else:
		_body = HeroScript.new()
		add_child(_body)
	_tag = KeyHint.new()
	_tag.name_tag = true     # ux02: players by name and title, magenta
	tags.add_child(_tag)
	_tag.show_hint("", who + (" · " + _title if _title != "" else ""))
	visible = false

## What the server last said about them.
func heard(d: Dictionary, now: float) -> void:
	if resident: _heard_place(str(d.get("from", d.place)), str(d.place), str(d.get("anim", "idle")) == "walk")
	else: _heard_point(d, now)

func _heard_point(d: Dictionary, now: float) -> void:
	_show_scooter(str(d.get("anim", "")) == "scooter")
	var p := Vector3(float(d.x), float(d.y), float(d.z))
	if _points.is_empty() or (_points.back()[1] as Vector3).distance_to(p) > SNAP_OVER:
		_points.clear()
		position = p
		rotation.y = float(d.yaw)
		visible = true
	_points.append([now, p, float(d.yaw)])
	if _points.size() > 12: _points.pop_front()

## Someone else on theirs.
func _show_scooter(on: bool) -> void:
	if on == (_scooter != null): return
	if on:
		_scooter = preload("res://assets/market/scooter.glb").instantiate()
		for body in _scooter.find_children("*", "StaticBody3D", true, false): body.queue_free()
		add_child(_scooter)
		_scooter.transform = preload("res://scripts/valley/player.gd").scooter_under()
		_body.ride_pose(-0.5, 0.9, [Vector3(0.52, 1.2, 1.25), Vector3(-0.52, 1.2, 1.25)], 0.42)
		_body.set_sitting(true)
		_body.position.y = 0.37
	else:
		_scooter.queue_free()
		_scooter = null
		_body.set_sitting(false)
		_body.position.y = 0.0

func _heard_place(from: String, place: String, walking: bool) -> void:
	if place == _place: return
	var first := _place == ""
	_place = place
	if first and not walking:
		position = _spot(place)
		_ground_y = _floor_at(position, FIRST_FROM)
		visible = true
		return
	if first:                          # already on the way when we arrived: somewhere along it
		position = _spot(from)
		_ground_y = _floor_at(position, FIRST_FROM)
		visible = true
	# back out of where they were, across the square, in by the way to the next
	_path.clear()
	var out: Array = WAYS.get(from, [])
	for i in range(out.size() - 1, -1, -1): _path.append(out[i])
	if from != place:
		_path.append(SQUARE + Vector3(_rng.randf_range(-3.0, 3.0), 0.0, _rng.randf_range(-2.0, 2.0)))
		for w in WAYS.get(place, []): _path.append(w)
	_path.append(_spot(place))

func _spot(place: String) -> Vector3:
	var s: Array = SPOTS.get(place, SPOTS.square)
	return s[0] + Vector3(_rng.randf_range(-s[1].x, s[1].x), 0.0, _rng.randf_range(-s[1].y, s[1].y))

## The ground under p, looked for from a little over it: a step up, never an awning, a roof or a tree.
func _floor_at(p: Vector3, from := 0.6) -> float:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * from, p + Vector3.DOWN * 8.0))
	return hit.position.y if hit else p.y

func _process(delta: float) -> void:
	if resident: _walk_on(delta)
	else: _glide(delta)
	_tag.at = position + Vector3.UP * TAG_OVER
	var cam := get_viewport().get_camera_3d()
	var far := cam.global_position.distance_to(global_position) if cam else 0.0
	_body.visible = far < SEEN_TO
	_tag.visible = far < TAG_WITHIN
	_pose_delta += delta
	if not _body.visible: return
	if _body.get("use_gait") != null: _body.use_gait = far < CLOSE
	_pose_in -= 1
	if _pose_in > 0 and far > CLOSE: return
	_pose_in = 3
	_body.step(_speed, _pose_delta)
	_pose_delta = 0.0

func _glide(delta: float) -> void:
	var at := Time.get_ticks_msec() * 0.001 - BEHIND
	while _points.size() > 2 and float(_points[1][0]) < at: _points.pop_front()
	var was := position
	if _points.size() >= 2:
		var a: Array = _points[0]
		var b: Array = _points[1]
		position = (a[1] as Vector3).lerp(b[1], clampf((at - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, float(b[2]), 1.0 - exp(-TURN * delta))
	var moved := Vector2(position.x - was.x, position.z - was.z).length() / maxf(delta, 0.001)
	_speed = lerpf(_speed, moved, 1.0 - exp(-10.0 * delta))

func _walk_on(delta: float) -> void:
	_ground_in -= delta
	if _path.is_empty():
		_speed = move_toward(_speed, 0.0, delta * 4.0)
		_shift_in -= delta
		if _shift_in <= 0.0 and _place != "":
			_shift_in = _rng.randf_range(SHIFT_EVERY.x, SHIFT_EVERY.y)
			_path.append(_spot(_place))
	else:
		var to := _path[0] - position
		to.y = 0.0
		if to.length() < 0.12:
			_path.pop_front()
		else:
			position += to.normalized() * minf(WALK * delta, to.length())
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-TURN * delta))
			_speed = move_toward(_speed, WALK, delta * 5.0)
		if _ground_in <= 0.0:
			_ground_in = GROUND_EVERY
			_ground_y = _floor_at(position)
	position.y = lerpf(position.y, _ground_y, 1.0 - exp(-10.0 * delta))

## Heard something: a gesture, and if it's a resident on the move, a moment's stop.
func react(pleased: bool) -> void:
	if resident:
		_body.gesture("Wave" if pleased else "Interact")
		_shift_in = maxf(_shift_in, 4.0)

func leave() -> void:
	_tag.queue_free()
	queue_free()
