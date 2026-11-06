class_name LifeDirector
extends Node3D
## Spawns villagers and runs their routines: stroll the waypoint graph, now and then
## detour to a point of interest (sit / shop / chat / look), then move on.
## Also feeds the 4 villagers nearest the camera into the foliage push globals.
##
## config:
##   count: int (<= 12 recommended), seed: int
##   waypoints: Array[Vector3]
##   edges: Array[Vector2i]   optional; default = waypoints form a closed loop
##   points_of_interest: Array of {pos: Vector3, kind: "sit"|"shop"|"chat"|"look",
##       facing: float yaw (0 = +Z) or Vector3 point to face, slots: int = 1 (2 for chat),
##       spacing: float = 0.75 (slot spread, metres)}

const VillagerScript := preload("res://scripts/life/villager.gd")
const ACTORS: Array[StringName] = [&"actor_a", &"actor_b", &"actor_c", &"actor_d"]
const PUSH_RADIUS := 1.1
const SEP_RADIUS := 0.85
const POI_REACH := 9.0
const DUR := {"sit": Vector2(7, 14), "shop": Vector2(4, 9), "chat": Vector2(6, 12), "look": Vector2(3, 6)}
enum { ROAM, GO_POI, ACT, PAUSE }

var height_at: Callable
var villagers: Array[Node3D] = []
var waypoints: Array[Vector3] = []
var links: Array = []        # waypoint index -> Array[int] neighbours
var pois: Array = []         # {kind, slots: Array[Vector3], facing: Array[float], used: Array[Node], near_wp: int}
var _rng := RandomNumberGenerator.new()
var _near_d := PackedFloat32Array([0, 0, 0, 0])
var _near_i := PackedInt32Array([0, 0, 0, 0])

func setup(cfg: Dictionary) -> void:
	_rng.seed = cfg.get("seed", 1)
	for p in cfg.get("waypoints", []): waypoints.append(p)
	links.resize(waypoints.size())
	for i in links.size(): links[i] = []
	var edges: Array = cfg.get("edges", [])
	if edges.is_empty():
		for i in waypoints.size(): edges.append(Vector2i(i, (i + 1) % waypoints.size()))
	for e in edges:
		links[e.x].append(e.y)
		links[e.y].append(e.x)
	for p in cfg.get("points_of_interest", []):
		_add_poi(p)
	for i in int(cfg.get("count", 8)):
		var v := VillagerScript.new()
		v.build(_rng.randi())
		v.height_at = height_at
		v.ai_wp = _rng.randi() % maxi(waypoints.size(), 1)
		v.ai_prefs = {"sit": _rng.randf_range(0.2, 1.0), "shop": _rng.randf_range(0.2, 1.0),
			"chat": _rng.randf_range(0.2, 1.0), "look": _rng.randf_range(0.1, 0.6)}
		add_child(v)
		# scatter along the path so nobody spawns stacked
		var a: Vector3 = waypoints[v.ai_wp] if waypoints else Vector3.ZERO
		var b: Vector3 = waypoints[links[v.ai_wp][0]] if waypoints and links[v.ai_wp] else a
		v.position = a.lerp(b, _rng.randf())
		v.ai_wp = links[v.ai_wp][0] if waypoints and links[v.ai_wp] else v.ai_wp
		_go_wp(v, v.ai_wp)
		villagers.append(v)

func _add_poi(p: Dictionary) -> void:
	var kind: String = p.get("kind", "look")
	var pos: Vector3 = p.pos
	var face = p.get("facing", 0.0)
	var yaw: float = face if face is float or face is int else atan2(face.x - pos.x, face.z - pos.z)
	var n: int = p.get("slots", 2 if kind == "chat" else 1)
	var sp: float = p.get("spacing", 0.75)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var poi := {"kind": kind, "slots": [], "facing": [], "used": [], "near_wp": _nearest_wp(pos)}
	for s in n:
		if kind == "chat":   # stand in a ring, everyone facing the middle
			var a := yaw + TAU * s / n
			var off := Vector3(sin(a), 0, cos(a)) * sp * 0.6
			poi.slots.append(pos + off)
			poi.facing.append(a + PI)
		else:
			poi.slots.append(pos + right * (s - (n - 1) * 0.5) * sp)
			poi.facing.append(yaw)
		poi.used.append(null)
	pois.append(poi)
	return

func _nearest_wp(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in waypoints.size():
		var d := waypoints[i].distance_squared_to(p)
		if d < bd: bd = d; best = i
	return best

func _go_wp(v, i: int) -> void:
	v.ai_state = ROAM
	v.ai_wp = i
	v.act = ""
	v.target = waypoints[i] + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6))
	v.has_target = true

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var n := villagers.size()
	# separation steering: O(n^2) is fine at <= 12 villagers
	for i in n:
		var a = villagers[i]
		var push := Vector3.ZERO
		var settling: bool = a.ai_state == GO_POI and a.arrived(1.2)
		if a.ai_state != ACT and not settling:
			for j in n:
				if i == j: continue
				var off: Vector3 = a.position - villagers[j].position
				off.y = 0.0
				var d := off.length()
				if d < SEP_RADIUS and d > 0.001:
					push += off / d * (1.0 - d / SEP_RADIUS) * 1.8
					# sidestep: nudge right so head-on walkers slip past each other
					push += Vector3(-off.z, 0, off.x).normalized() * 0.25 * (1.0 - d / SEP_RADIUS)
		a.steer = push
	for v in villagers:
		_think(v, delta)
		v.tick(delta)
	_update_actors()

func _think(v, delta: float) -> void:
	v.ai_timer -= delta
	v.wave_cool -= delta
	match v.ai_state:
		ROAM:
			if v.arrived(0.45):
				_choose(v)
			elif v.wave_cool <= 0.0:
				_maybe_greet(v)
		GO_POI:
			if v.arrived(0.12):
				v.ai_state = ACT
				var poi: Dictionary = pois[v.ai_poi]
				v.position = v.position.lerp(poi.slots[v.ai_slot], 0.5)
				v.target = poi.slots[v.ai_slot]
				v.act_facing = poi.facing[v.ai_slot]
				var r: Vector2 = DUR[poi.kind]
				v.ai_timer = _rng.randf_range(r.x, r.y)
		ACT:
			var poi: Dictionary = pois[v.ai_poi]
			v.act = poi.kind
			if poi.kind == "chat":
				var partner = _partner(poi, v)
				if partner == null:
					v.act = "look"
					v.ai_timer -= delta   # nobody came: get bored twice as fast
				else:
					v.look_at_point(partner.position)
			if v.ai_timer <= 0.0:
				poi.used[v.ai_slot] = null
				v.ai_poi = -1
				_go_wp(v, poi.near_wp)
		PAUSE:
			if v.ai_timer <= 0.0:
				_go_wp(v, v.ai_wp)

func _partner(poi: Dictionary, v):
	for o in poi.used:
		if o != null and o != v and o.ai_state == ACT: return o
	return null

## Utility pick at a waypoint: keep strolling, pause, or visit a nearby POI.
func _choose(v) -> void:
	var best_score := _rng.randf_range(0.5, 1.0)    # baseline: keep strolling
	var best_poi := -1
	var best_slot := -1
	for pi in pois.size():
		var poi: Dictionary = pois[pi]
		if waypoints[poi.near_wp].distance_to(v.position) > POI_REACH: continue
		var slot: int = poi.used.find(null)
		if slot < 0: continue
		var score: float = v.ai_prefs.get(poi.kind, 0.3) * _rng.randf_range(0.6, 1.6)
		if poi.kind == "chat" and poi.used.count(null) < poi.used.size():
			score += 0.8   # someone is already waiting to talk
		if score > best_score:
			best_score = score; best_poi = pi; best_slot = slot
	if best_poi >= 0:
		var poi: Dictionary = pois[best_poi]
		poi.used[best_slot] = v
		v.ai_poi = best_poi
		v.ai_slot = best_slot
		v.ai_state = GO_POI
		v.target = poi.slots[best_slot]
		return
	if _rng.randf() < 0.12:
		v.ai_state = PAUSE
		v.ai_timer = _rng.randf_range(1.5, 3.5)
		v.has_target = false
		return
	var nb: Array = links[v.ai_wp]
	if nb.is_empty(): return
	var next: int = nb[_rng.randi() % nb.size()]
	if next == v.ai_prev_wp and nb.size() > 1: next = nb[(nb.find(next) + 1) % nb.size()]
	v.ai_prev_wp = v.ai_wp
	_go_wp(v, next)

func _maybe_greet(v) -> void:
	for o in villagers:
		if o == v: continue
		var d: float = v.position.distance_to(o.position)
		if d < 3.2 and d > 1.0 and _rng.randf() < 0.004:
			v.wave()
			v.look_at_point(o.position)
			v.wave_cool = 14.0
			return

## Four nearest villagers to the camera push grass / leaves (common.gdshaderinc).
func _update_actors() -> void:
	var cam := get_viewport().get_camera_3d()
	var ref := cam.global_position if cam else global_position
	for k in 4:
		_near_d[k] = INF
		_near_i[k] = -1
	for i in villagers.size():
		var d := villagers[i].global_position.distance_squared_to(ref)
		for k in 4:   # insertion into a fixed 4-slot list, no allocation
			if d < _near_d[k]:
				var j := 3
				while j > k:
					_near_d[j] = _near_d[j - 1]; _near_i[j] = _near_i[j - 1]; j -= 1
				_near_d[k] = d; _near_i[k] = i
				break
	for k in 4:
		var val := Vector4(0, -100, 0, 0)
		if _near_i[k] >= 0:
			var p := villagers[_near_i[k]].global_position
			val = Vector4(p.x, p.y, p.z, PUSH_RADIUS)
		RenderingServer.global_shader_parameter_set(ACTORS[k], val)

func _exit_tree() -> void:
	for k in 4:
		RenderingServer.global_shader_parameter_set(ACTORS[k], Vector4(0, -100, 0, 0))
