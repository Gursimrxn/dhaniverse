class_name TownNpc
extends Node3D
## One of the town's people who stays at their post: the Spice Merchant at his kiosk, the exchange's keeper, the sign painter, the town
## hall's clerk, the bank's clerk. They breathe, turn their head to whoever comes close, and wave when spoken to. Their name floats over
## them when you're near, so a quest's "the Spice Merchant" can be found.

const PersonScript := preload("res://scripts/life/person.gd")
const LOOKS_WITHIN := 7.0          # m: closer than this they turn their head to you
const NAME_WITHIN := 9.0           # m: their name shows
const NAME_OVER := 2.15            # m

var player: Node3D
var title := ""
var person: Node3D
var _tag: KeyHint

## look: Person's folk look (colours by role).
func setup(who: String, look: Dictionary, tags: Control) -> void:
	title = who
	person = PersonScript.new()
	add_child(person)
	person.setup("folk", look)
	_tag = KeyHint.new()
	tags.add_child(_tag)

func _process(delta: float) -> void:
	if person == null: return
	var near := false
	if player:
		var to := player.global_position - global_position
		var yaw := wrapf(atan2(to.x, to.z) - global_rotation.y, -PI, PI)
		near = to.length() < LOOKS_WITHIN
		person.look_target = Vector2(clampf(yaw, -1.1, 1.1), 0.0) if near else Vector2.ZERO
		var shown := to.length() < NAME_WITHIN
		if shown != _tag.visible: _tag.show_hint("", title if shown else "")
		_tag.at = global_position + Vector3.UP * NAME_OVER
	person.step(0.0, delta)

func greet() -> void:
	if person: person.wave()

func _exit_tree() -> void:
	if is_instance_valid(_tag): _tag.queue_free()
