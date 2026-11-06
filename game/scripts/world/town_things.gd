class_name TownThings
extends Node
## The things in town you can walk up to and use with the interact key: the Bounty Board, the Price Call board, your chest, the exchange
## kiosk, the Spice Merchant, the sign painter, the town hall's clerk, a quest's page on the ground. Objects are the interface: standing at
## one shows its key and what it does, on the thing itself, and only the nearest in reach. Each thing is
## {at: Callable -> Vector3, reach: m, hint: Callable -> String ("" when there's nothing to do now), press: Callable, over: m,
## priority: the higher goes first when two are in reach}.

const OVER := 1.9                  # m over the thing's foot: where its hint sits

var player: CharacterBody3D
var busy := Callable()             # true while the screen or the keys are someone else's (a sheet, a film, a run)
var _things: Array[Dictionary] = []
var _hint := KeyHint.new()
var _near := {}                    # the thing in reach now

## tags: the world's UI layer, where hints live.
func setup(tags: Control) -> void:
	_hint.always_words = true
	tags.add_child(_hint)

func add(thing: Dictionary) -> Dictionary:
	thing.merge({"reach": 2.4, "over": OVER, "priority": 0}, false)
	_things.append(thing)
	return thing

func remove(thing: Dictionary) -> void:
	_things.erase(thing)
	if _near == thing: _near = {}

func _process(_delta: float) -> void:
	_near = {}
	var words := ""
	if player and not (busy.is_valid() and busy.call()):
		var best := INF
		for t in _things:
			var at: Vector3 = t.at.call()
			var d := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
			if d > float(t.reach) or absf(at.y - player.global_position.y) > 2.5: continue
			var score := d - 100.0 * float(t.priority)      # a quest's step at a thing goes before the thing's own use
			if score >= best: continue
			var w: String = t.hint.call()
			if w == "": continue
			best = score
			_near = t
			words = w
	if _near.is_empty():
		_hint.show_hint("", "")
		return
	_hint.show_hint("E", words)
	_hint.at = (_near.at.call() as Vector3) + Vector3.UP * float(_near.over)

func _unhandled_input(e: InputEvent) -> void:
	if _near.is_empty() or not e.is_action_pressed("interact") or e.is_echo(): return
	if busy.is_valid() and busy.call(): return
	get_viewport().set_input_as_handled()
	_near.press.call()
