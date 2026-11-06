class_name TownPeople
extends Node
## The people who belong in a place: diners at the tables, people waiting at the bank and off the boat, sellers at the market, fishers on the
## jetty, and others out walking the town's paths. None of it touches the rules: the residents who trade are Presence's. Drawn and posed only
## while you're near, so they cost nothing from across town.

const PersonScript := preload("res://scripts/life/person.gd")
const NEAR := 26.0                 # m from the player: closer than this they're drawn and moving
const SEAT_LIFT := 0.3             # m: a seat, over the ground the sitting clip is made for
const STIR_EVERY := Vector2(5.0, 18.0)   # s between someone looking round or gesturing
const WALKERS_SEEN := 48.0         # m: out of doors you see further
const GROUND_FROM := 0.6           # m over their feet the ground's looked for from: a kerb or a step up, never an awning
const WALK := 1.15                 # m/s
const PAUSE_CHANCE := 0.35         # at a waypoint, stop and look about
const PAUSE := Vector2(2.0, 9.0)   # s
# laps people walk, on the paved ways (x, z), each out and back
const ROUTES := [
	[Vector2(-103.0, 34.0), Vector2(-103.0, 52.0), Vector2(-100.0, 66.0)],
	[Vector2(-101.0, 49.5), Vector2(-92.0, 49.5), Vector2(-88.0, 40.0), Vector2(-90.0, 6.0)],
	[Vector2(-90.0, -2.5), Vector2(-66.0, -3.5), Vector2(-40.0, -5.0)],
	[Vector2(-44.0, -7.0), Vector2(-27.0, -9.0), Vector2(-20.0, -12.0)],
	[Vector2(-30.0, -3.0), Vector2(-12.0, -2.0), Vector2(-1.0, 1.5), Vector2(8.5, 3.0)],
	[Vector2(-51.0, 2.0), Vector2(-51.0, 28.0), Vector2(-45.5, 33.0)],
	[Vector2(-27.0, 2.5), Vector2(-40.0, 2.5), Vector2(-51.0, 2.0)],
	[Vector2(-8.0, 70.0), Vector2(-8.0, 80.0), Vector2(-15.0, 84.0)],
	[Vector2(8.5, 3.0), Vector2(-1.0, 40.0), Vector2(-8.0, 70.0)],
	[Vector2(-20.0, -12.5), Vector2(-20.0, -22.0), Vector2(-24.0, -24.0)],
]
# who's on the jetty with a rod: x, y, z, yaw
const FISHERS := [[-119.0, -0.25, 50.9, 0.0], [-121.5, -0.25, 47.2, PI], [-111.5, -0.25, 50.0, 0.0]]
# x, y, z, yaw, sits?
const PEOPLE := [
	[11.6, 0.02, 18.0, -1.6, true], [19.0, 0.02, 20.0, 0.4, true], [21.0, 0.02, 20.3, -0.9, true], [14.0, 0.02, 15.2, -0.2, false], [18.0, 0.02, 15.0, 2.8, false],
	[-33.4, 0.76, 11.7, 1.57, true], [-20.2, 0.76, 11.2, -1.57, true], [-25.6, 0.76, 12.0, 2.6, false], [-33.4, 0.76, 16.2, 1.57, true], [-30.6, 0.76, 14.0, 0.2, false], [-22.8, 0.76, 13.8, 2.9, false],
	[-74.0, 0.07, 15.2, 3.14, true], [-67.0, 0.07, 20.2, 3.14, true], [-60.0, 0.07, 15.2, 3.14, true], [-62.0, 0.07, 14.5, 0.0, false],
	[-27.0, 0.33, -31.0, 1.57, false], [-9.0, 0.33, -31.0, -1.57, false], [-33.0, 0.33, -26.9, 0.0, false], [-6.0, 0.33, -25.9, 0.0, false],
]

var player: Node3D
var _people: Array = []            # {body, stir_in, look}
var _rng := RandomNumberGenerator.new()
var _walkers: Array = []           # {body, route, at, dir, pause, ground, ground_in, speed}

func _ready() -> void:
	_rng.seed = 41
	for i in PEOPLE.size():
		var p: Array = PEOPLE[i]
		var body: Node3D = PersonScript.new()
		add_child(body)
		body.setup("folk", PersonScript.folk_look(1000 + i * 37))
		body.position = Vector3(p[0], p[1] + (SEAT_LIFT if p[4] else 0.0), p[2])
		body.rotation.y = p[3]
		body.visible = false
		if p[4]: body.sit(true)
		_people.append({"body": body, "stir_in": _rng.randf_range(0.0, STIR_EVERY.y)})
	for i in FISHERS.size():
		var p: Array = FISHERS[i]
		var body: Node3D = PersonScript.new()
		add_child(body)
		body.setup("folk", PersonScript.folk_look(3000 + i * 53))
		body.position = Vector3(p[0], p[1], p[2])
		body.rotation.y = p[3]
		body.visible = false
		body.sit(true)
		var rod := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.008
		m.bottom_radius = 0.016
		m.height = 2.1
		rod.mesh = m
		rod.rotation = Vector3(deg_to_rad(52.0), 0.0, 0.0)
		rod.position = Vector3(0.12, 1.15, 0.8)
		body.add_child(rod)
		_people.append({"body": body, "stir_in": _rng.randf_range(0.0, STIR_EVERY.y)})
	for i in ROUTES.size():
		var body: Node3D = PersonScript.new()
		add_child(body)
		body.setup("folk", PersonScript.folk_look(2000 + i * 71))
		var route: Array = ROUTES[i]
		var start: int = _rng.randi_range(0, route.size() - 1)
		body.position = Vector3(route[start].x, 0.0, route[start].y)
		body.visible = false
		_walkers.append({"body": body, "route": route, "at": start, "dir": 1, "pause": _rng.randf_range(0.0, PAUSE.y), "ground": 0.0, "ground_in": 0.0, "speed": 0.0})

func _process(delta: float) -> void:
	if player == null: return
	for d in _people:
		var body: Node3D = d.body
		var near: bool = body.position.distance_to(player.global_position) < NEAR
		body.visible = near
		if not near: continue
		d.stir_in -= delta
		if d.stir_in <= 0.0:
			d.stir_in = _rng.randf_range(STIR_EVERY.x, STIR_EVERY.y)
			body.look_target = Vector2(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.1, 0.2))
		body.step(0.0, delta)
	for w in _walkers: _walk_on(w, delta)

## Everybody has heard something: they stop and look at it, and take it well or badly.
func react(pleased: bool, at: Vector3) -> void:
	for w in _walkers:
		w.pause = maxf(w.pause, 4.0)
		w.reacting = at
		w.react_for = 4.0
		(w.body as Node3D).call_deferred("gesture", "Wave" if pleased else "Defeat")

## They keep walking when nobody's there to see, so the town doesn't freeze behind you; only the posing stops.
func _walk_on(w: Dictionary, delta: float) -> void:
	var body: Node3D = w.body
	var near: bool = body.position.distance_to(player.global_position) < WALKERS_SEEN
	body.visible = near
	var speed := 0.0
	if w.get("react_for", 0.0) > 0.0:
		w.react_for -= delta
		var to_it: Vector3 = (w.reacting as Vector3) - body.position
		body.rotation.y = lerp_angle(body.rotation.y, atan2(to_it.x, to_it.z), 1.0 - exp(-5.0 * delta))
	if w.pause > 0.0:
		w.pause -= delta
	else:
		var route: Array = w.route
		var goal: Vector2 = route[w.at]
		var to := Vector2(goal.x - body.position.x, goal.y - body.position.z)
		if to.length() < 0.25:
			var next: int = w.at + w.dir
			if next < 0 or next >= route.size():
				w.dir = -w.dir
				next = w.at + w.dir
			w.at = next
			if _rng.randf() < PAUSE_CHANCE: w.pause = _rng.randf_range(PAUSE.x, PAUSE.y)
		else:
			var move := to.normalized() * WALK * delta
			body.position += Vector3(move.x, 0.0, move.y)
			speed = WALK
			if near: body.rotation.y = lerp_angle(body.rotation.y, atan2(to.x, to.y), 1.0 - exp(-6.0 * delta))
	w.speed = lerpf(w.speed, speed, 1.0 - exp(-8.0 * delta))
	if not near: return
	w.ground_in -= delta
	if w.ground_in <= 0.0:
		w.ground_in = 0.0
		var ray := PhysicsRayQueryParameters3D.create(body.position + Vector3.UP * GROUND_FROM, body.position + Vector3.DOWN * 6.0)
		if player is CollisionObject3D: ray.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit: w.ground = hit.position.y
	# up a step at once (easing up it would have them walk through its edge); down one eased, as a foot finds it
	body.position.y = w.ground if w.ground > body.position.y else lerpf(body.position.y, w.ground, 1.0 - exp(-25.0 * delta))
	body.use_gait = body.position.distance_to(player.global_position) < 16.0
	body.watching = player
	body.step(w.speed, delta)
