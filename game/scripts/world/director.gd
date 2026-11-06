class_name Director
extends Node
## The one owner of every camera takeover: the opening and the big moments in the spec's §8. It has a camera of its own, so the
## player's rig keeps following underneath and nothing has to be put back. Any key skips a shot. Fly a path, then land() on the rig.

signal skipped

const LAND_TIME := 1.1             # s to glide from the last shot into the player's own view

var rig: Node3D
var cam := Camera3D.new()
var _token := 0                    # each shot's own number: a skip or a newer shot ends the older one
var _skippable := false
var keys_pass_through := false     # a shot over ordinary play: a key ends it and still does what it does

## How much of a shot has gone, eased, for this many seconds.
static func eased(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

## A point along a smooth line through points, u from 0 to 1.
static func along(points: Array, u: float) -> Vector3:
	if points.size() == 1: return points[0]
	var f := clampf(u, 0.0, 1.0) * (points.size() - 1)
	var i := mini(int(f), points.size() - 2)
	var a: Vector3 = points[maxi(i - 1, 0)]
	var d: Vector3 = points[mini(i + 2, points.size() - 1)]
	return (points[i] as Vector3).cubic_interpolate(points[i + 1], a, d, f - i)

func _ready() -> void:
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.1
	cam.far = 6000.0
	add_child(cam)
	process_mode = Node.PROCESS_MODE_ALWAYS

var busy: bool:
	get: return cam.current

## Fly the camera along eyes, looking along ats, for `seconds`. Returns once it's done or skipped.
func fly(eyes: Array, ats: Array, seconds: float, fov := 40.0, skippable := true) -> void:
	_token += 1
	var me := _token
	_skippable = skippable
	cam.fov = fov
	_place(eyes, ats, 0.0)
	cam.make_current()
	var t := 0.0
	while t < seconds and me == _token:
		await get_tree().process_frame
		t += get_process_delta_time()
		_place(eyes, ats, eased(minf(t / seconds, 1.0)))

func _place(eyes: Array, ats: Array, u: float) -> void:
	cam.look_at_from_position(along(eyes, u), along(ats, u))

## A shot worked out each frame, for something that moves: shot(u) gives [eye, what it looks at], u going 0 to 1 at an even pace.
func follow(shot: Callable, seconds: float, fov := 40.0) -> void:
	_token += 1
	var me := _token
	_skippable = true
	cam.fov = fov
	var t := 0.0
	var at: Array = shot.call(0.0)
	cam.look_at_from_position(at[0], at[1])
	cam.make_current()
	while t < seconds and me == _token:
		await get_tree().process_frame
		t += get_process_delta_time()
		at = shot.call(minf(t / seconds, 1.0))
		cam.look_at_from_position(at[0], at[1])

## Glide from wherever the shot ended into the player's view, and hand back.
func land(seconds := LAND_TIME) -> void:
	_token += 1
	var me := _token
	_skippable = false
	var from := cam.global_transform
	var from_fov := cam.fov
	var t := 0.0
	while t < seconds and me == _token:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := eased(minf(t / seconds, 1.0))
		cam.global_transform = from.interpolate_with(rig.cam.global_transform, k)
		cam.fov = lerpf(from_fov, rig.cam.fov, k)
	if me == _token: rig.cam.make_current()

## Straight back to the player's view.
func cut() -> void:
	_token += 1
	_skippable = false
	rig.cam.make_current()

func _unhandled_input(e: InputEvent) -> void:
	if not _skippable or not busy: return
	if e.is_echo() or not e.is_pressed() or not (e is InputEventKey or e is InputEventMouseButton): return
	_token += 1
	_skippable = false
	skipped.emit()
	if not keys_pass_through: get_viewport().set_input_as_handled()
