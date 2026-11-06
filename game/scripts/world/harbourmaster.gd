class_name Harbourmaster
extends Node3D
## The harbourmaster, on the landing where the ferry comes in. Waves you over, knows your name, hands you things. What happens when
## is scripts/world/opening.gd.

const PersonScript := preload("res://scripts/life/person.gd")
const LOOK := {"top": "28324a", "tee": "e8e2d4", "skin": "94603f", "hair": "a8a8a8", "bottom": "2a2a30", "shoes": "4b3a2c", "open_top": true, "tall": 1.1, "wide": 1.18, "cap": true, "hat": "28324a", "beard": true}
const HELD := 1.6                  # s he holds what he's given
const SAID_FOR := 5.0              # s a line stays
const WALK := 1.1                  # m/s
const ROUNDS: Array[Vector2] = [Vector2(-102.5, 46.0), Vector2(-100.0, 52.0), Vector2(-96.0, 49.5), Vector2(-102.0, 56.0), Vector2(-101.0, 41.0)]   # about the landing
const PAUSE := Vector2(5.0, 16.0)  # s at each

var player: CharacterBody3D
var person: Node3D
var height_at := Callable()
var cinema: Cinema
var going_about := false           # once he's done with you, he has a landing to run
var _to := Vector3.INF
var _pause := 2.0

func setup(tags: Control) -> void:
	person = PersonScript.new()
	add_child(person)
	person.setup("folk", LOOK)

func say(words: String, seconds := SAID_FOR) -> void:
	cinema.say(words, seconds)

func wave() -> void:
	person.wave()

func _process(delta: float) -> void:
	if player == null: return
	var speed := 0.0
	if going_about and _to == Vector3.INF:
		_pause -= delta
		if _pause <= 0.0:
			var p: Vector2 = ROUNDS.pick_random()
			_to = Vector3(p.x, height_at.call(p.x, p.y), p.y)
			_pause = randf_range(PAUSE.x, PAUSE.y)
	if _to != Vector3.INF:
		var way := _to - global_position
		if Vector2(way.x, way.z).length() < 0.15:
			_to = Vector3.INF
		else:
			global_position += way.normalized() * WALK * delta
			speed = WALK
			rotation.y = lerp_angle(rotation.y, atan2(way.x, way.z), 1.0 - exp(-5.0 * delta))
	elif global_position.distance_to(player.global_position) < 18.0:     # turns to whoever is coming
		rotation.y = lerp_angle(rotation.y, atan2(player.global_position.x - global_position.x, player.global_position.z - global_position.z), 1.0 - exp(-3.0 * delta))
	person.step(speed, delta)

## From this hand to his: a sheet of paper, held a moment.
func hand_over() -> void:
	var sheet := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.21, 0.01, 0.28)
	sheet.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Brand.CREAM
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheet.material_override = m
	var from := person.global_position + Vector3.UP * 0.75
	person.gesture("Interact")
	player.avatar.reach(from)
	player.avatar.set_carrying(true)
	player.avatar.hold(sheet, from)
	get_tree().create_timer(HELD).timeout.connect(func():
		sheet.queue_free()
		player.avatar.set_carrying(false))
