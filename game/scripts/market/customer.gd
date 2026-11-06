class_name MarketCustomer
extends Node3D
## A stand-in customer: a townsperson who walks a line of points on the floor, waits with their order over their head
## and turns to whoever is working. Ignores collision: the routes are laid clear of everything (scripts/market/stall.gd).

const PersonScript := preload("res://scripts/life/person.gd")
const SPEED := 1.3               # m/s
const TURN := 7.0
const BUBBLE_Y := 1.62           # m over the floor

var order_id := -1
var watching: Node3D = null
var patience := INF               # s they'll still wait in line
var item := ""                   # what they want
var bubble: OrderBubble
var _person: Node3D
var _route: Array[Vector3] = []
var _on_arrive := Callable()
var _face_at := Vector3.INF      # what to look at when standing

const GAIT_WITHIN := 25.0         # m from the camera

func setup(outfit: String, look: Dictionary, tags: Control) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # moved every frame by hand
	_person = PersonScript.new()
	add_child(_person)
	_person.setup(outfit, look)
	bubble = OrderBubble.new()
	tags.add_child(bubble)

func walk(route: Array[Vector3], on_arrive := Callable()) -> void:
	_route = route
	_on_arrive = on_arrive

func is_walking() -> bool:
	return not _route.is_empty()

func face(point: Vector3) -> void:
	_face_at = point

func cheer() -> void:
	_person.wave()

func reach() -> void:
	_person.gesture("Interact")

func _process(delta: float) -> void:
	var speed := 0.0
	var yaw := rotation.y
	if not _route.is_empty():
		var to := _route[0] - position
		to.y = 0.0
		if to.length() < 0.08:
			_route.pop_front()
			if _route.is_empty() and _on_arrive.is_valid(): _on_arrive.call()
		else:
			var move := minf(SPEED * delta, to.length())
			position += to.normalized() * move
			speed = SPEED
			yaw = atan2(to.x, to.z)
			position.y = _floor_y()
	elif _face_at != Vector3.INF:
		yaw = atan2(_face_at.x - position.x, _face_at.z - position.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN * delta))
	var eye := get_viewport().get_camera_3d()
	_person.use_gait = eye == null or eye.global_position.distance_to(global_position) < GAIT_WITHIN
	_person.watching = watching
	_person.step(speed, delta)
	bubble.at = position + Vector3.UP * BUBBLE_Y

## The floor under them: kerbs and the hall's threshold rise along the way in.
func _floor_y() -> float:
	var q := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 1.0, position + Vector3.DOWN * 2.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else position.y

func _exit_tree() -> void:
	if bubble: bubble.queue_free()
