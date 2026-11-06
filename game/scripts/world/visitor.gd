class_name Visitor
extends Node3D
## Someone who comes to find the player: walks up, says it, walks off. You can walk away from them; they'll say it anyway.

const PersonScript := preload("res://scripts/life/person.gd")
const LOOK := {"top": "2f7c7a", "tee": "e8e2d4", "skin": "b9805a", "hair": "2b2018", "bottom": "2a2a30", "shoes": "2a2a30", "hat": "", "open_top": true, "tall": 0.98}
const FROM := 11.0                 # m away they start
const STOPS := 1.7                 # m from him
const WALK := 2.0                  # m/s: they've come on purpose
const LINE_FOR := 4.2              # s each line stays

signal gone
signal arrived

var player: CharacterBody3D
var _person: Node3D
var cinema: Cinema
var _lines: Array = []
var _left := 0.0
var _going := false
var _said_first := false

func come(lines: Array) -> void:
	_lines = lines
	_person = PersonScript.new()
	add_child(_person)
	_person.setup("folk", LOOK)
	var a := randf() * TAU
	global_position = player.global_position + Vector3(cos(a), 0.0, sin(a)) * FROM

func _process(delta: float) -> void:
	var to := player.global_position - global_position
	var far := Vector2(to.x, to.z).length()
	var speed := 0.0
	if _going:
		global_position -= Vector3(to.x, 0.0, to.z).normalized() * WALK * delta
		speed = WALK
		rotation.y = atan2(-to.x, -to.z)
		if far > FROM * 2.0:
			queue_free()
	elif far > STOPS and _left <= 0.0:
		global_position += Vector3(to.x, 0.0, to.z).normalized() * WALK * delta
		speed = WALK
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
	else:
		if _left <= 0.0:
			if not _said_first:
				_said_first = true
				arrived.emit()
			_left = LINE_FOR
			cinema.say(str(_lines.pop_front()), LINE_FOR)
		_left -= delta
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-5.0 * delta))
		if _left <= 0.0 and _lines.is_empty():
			_going = true
			gone.emit()
	global_position.y = lerpf(global_position.y, player.global_position.y, 1.0 - exp(-6.0 * delta))
	_person.step(speed, delta)
