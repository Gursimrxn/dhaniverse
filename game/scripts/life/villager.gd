class_name Villager
extends Node3D
## A townsperson: a Person body (scripts/life/person.gd: a rigged character, recoloured, its clips played at
## the speed it walks) steered by LifeDirector.tick. Acts (sit / shop / chat / look) face a point and idle;
## chatting talks with its hands now and then; it waves back at the player.

const PersonScript := preload("res://scripts/life/person.gd")
const OUTFITS := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Male", "Casual3_Female", "Casual_Bald",
	"Doctor_Male_Young", "Doctor_Female_Young", "Doctor_Male_Old", "Doctor_Female_Old", "OldClassy_Male", "OldClassy_Female",
	"Suit_Male", "Suit_Female", "Worker_Male", "Worker_Female", "Cowboy_Female", "Casual_Male", "Casual_Female", "Kimono_Female"]
const TOPS := ["0f8f88", "ef6f5e", "e9b23c", "9db48a", "7d9cc0", "8a5a8c", "3f5f8f", "e58f6b", "5fa58e", "f2e6c9", "c8553d", "355c7d"]
const BOTTOMS := ["3f5f8f", "4b3d36", "2f3a4a", "b49b74", "5b6b4a", "6b4f6b", "2b2b33"]
const SHOES := ["3a2a20", "2b2b33", "6b4a32", "e8e2d6", "8a3b2f"]

var height_at: Callable           # (x, z) -> ground y; invalid = keep y
var walk_speed := 1.25
var target := Vector3.ZERO
var has_target := false
var steer := Vector3.ZERO         # separation push, written by the director
var vel := Vector3.ZERO
var act := ""                     # "", "sit", "shop", "chat", "look"
var act_facing := 0.0             # yaw to face while acting
var tris := 6300
# the director's bookkeeping
var ai_state := 0
var ai_timer := 0.0
var ai_wp := 0
var ai_prev_wp := -1
var ai_poi := -1
var ai_slot := -1
var ai_prefs := {}
var wave_cool := 0.0

var body: Node3D
var _vis: Node3D
var _talk := 0.0
var _look_goal := 0.0
var _look_t := 0.0

func build(seed: int, outfit := "", look := {}) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pick := func(a: Array) -> String: return a[rng.randi() % a.size()]
	if outfit == "": outfit = pick.call(OUTFITS)
	if look.is_empty():
		look = {"skin": pick.call(PersonScript.SKINS), "hair": pick.call(PersonScript.HAIRS), "top": pick.call(TOPS),
			"bottom": pick.call(BOTTOMS), "shoes": pick.call(SHOES), "hat": pick.call(TOPS)}
	walk_speed = rng.randf_range(0.8, 1.15)
	_talk = rng.randf_range(2.0, 6.0)
	_vis = Node3D.new()
	add_child(_vis)
	body = PersonScript.new()
	_vis.add_child(body)
	body.setup(outfit, look)
	_vis.scale = Vector3.ONE * rng.randf_range(0.92, 1.04)

func tick(delta: float) -> void:
	var desired := Vector3.ZERO
	if has_target:
		var to := target - position
		to.y = 0.0
		var d := to.length()
		if d > 0.05:
			desired = to / d * walk_speed * clampf(d / 0.8, 0.2, 1.0)   # ease into arrival
	desired += steer
	vel = vel.lerp(desired, 1.0 - exp(-5.0 * delta))
	vel.y = 0.0
	position += vel * delta
	if height_at.is_valid():
		position.y = lerpf(position.y, height_at.call(position.x, position.z), 1.0 - exp(-20.0 * delta))
	var spd := vel.length()
	if spd > 0.2 and act == "":
		_vis.rotation.y = lerp_angle(_vis.rotation.y, atan2(vel.x, vel.z), 1.0 - exp(-7.0 * delta))
	elif act != "":
		_vis.rotation.y = lerp_angle(_vis.rotation.y, act_facing, 1.0 - exp(-5.0 * delta))
	# chatting: a gesture every few seconds
	if act == "chat":
		_talk -= delta
		if _talk <= 0.0:
			_talk = randf_range(3.0, 7.0)
			body.gesture("Interact")
	body.sit(act == "sit" and arrived(0.35))
	_look_t = maxf(_look_t - delta, 0.0)
	body.look_target = Vector2(_look_goal if _look_t > 0.0 else 0.0, 0.0)
	body.step(spd, delta)

func arrived(r := 0.2) -> bool:
	return Vector2(target.x - position.x, target.z - position.z).length() < r

func wave() -> void:
	body.wave()

func facing_yaw() -> float:
	return _vis.rotation.y

func look_at_point(p: Vector3) -> void:
	_look_goal = clampf(wrapf(atan2(p.x - position.x, p.z - position.z) - _vis.rotation.y, -PI, PI), -1.0, 1.0)
	_look_t = 1.5
