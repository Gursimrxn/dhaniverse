class_name Guide
extends Node3D
## Where to go next, said the same way everywhere: one gold diamond over the place, the minimap's goal, and the island's standing
## "Next" line. After Gran's letter and before any quest it's the Bounty Board. With quests on, it's the next step of the one you're
## tracking (the last one you took, kept on this machine). Between quests: the Common Table when energy is under LOW, your chest at
## your door when it's ready (once you've done a quest), else back to the board. Within FOLD m the diamond folds away, and the thing's
## own green key hint takes over.

const FOLD := 8.0                  # m
const LOW := 40                    # energy: time to eat
const THINK_EVERY := 0.3           # s between working it out again
const FAR_FROM := 14.0             # m: past this the diamond grows with the distance
const TRACKED := "tracked_quest"   # the settings key it's kept under
const DONE := "done_today"         # the quests finished today on this machine, for the board's chalk

var town: Dhaniverse
var client: TownClient
var player: CharacterBody3D
var world: Node3D
var tracked := ""
var loot: LootCrate                # a crate out goes before everything: it won't wait
var _diamond := Node3D.new()
var _goal := {}                    # {words, at: Callable -> Vector3, over: m, waiting}
var _think_in := 0.0
var _t := 0.0
var _map_at := Vector2(INF, INF)
var _done := {}
var _day := -1

func _ready() -> void:
	tracked = str(world._setting(TRACKED, ""))
	var saved = world._setting(DONE, {})
	if saved is Dictionary:
		_day = int(saved.get("day", -1))
		for q in saved.get("quests", []): _done[str(q)] = true
	_diamond.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF    # moved every frame here
	_diamond.add_child(QuestMarks.diamond())
	_diamond.visible = false
	add_child(_diamond)
	client.event.connect(_on_event)

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"QuestTaken": track(str(e.quest))
		"QuestDone": _note_done(str(e.quest))

## Follow this quest: its next step gets the diamond.
func track(quest: String) -> void:
	tracked = quest
	world._save_setting(TRACKED, quest)
	_think_in = 0.0     # the diamond, the route and the tracker move to it now

## Was this quest finished today (the real day), on this machine?
func done_today(quest: String) -> bool:
	return _day == int(client.city.get("real_day", -2)) and _done.has(quest)

func _note_done(quest: String) -> void:
	var day := int(client.city.get("real_day", -1))
	if day != _day:
		_day = day
		_done.clear()
	_done[quest] = true
	world._save_setting(DONE, {"day": _day, "quests": _done.keys()})

## What the island, the minimap and the quest tracker all show: the next thing's words, and how far off it is (m; INF for nowhere).
func next_words() -> String:
	return str(_goal.get("words", ""))

func next_distance() -> float:
	if not _goal.has("at"): return INF
	var at: Vector3 = _goal.at.call()
	return Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()

## The next thing to do: the tracked quest's step, or the board, the table or the chest.
func _think() -> void:
	_goal = {}
	if client.you.is_empty() or world.opening.playing or (world.title and world.title.is_up): return
	if loot and loot.where() != Vector3.INF:
		_goal = {"words": "the loot crate, %s" % loot.place_words(), "at": loot.where, "over": 1.6}
		return
	var q := TownState.quest(client.you, tracked)
	if q.is_empty() or TownState.next_step(q).is_empty():
		q = {}
		for other in client.you.get("quests", []):
			if not TownState.next_step(other).is_empty():
				q = other
				tracked = str(other.quest)
				break
	if not q.is_empty():
		var s := TownState.next_step(q)
		var place := str(s.get("place", ""))
		_goal = {"words": TownState.step_says(q, s), "waiting": bool(s.get("waiting", false))}
		if town.knows(place):
			_goal.at = func(): return town.place_at(place)
			_goal.over = QuestMarks.OVER_PERSON if town.is_person(place) else QuestMarks.OVER
		return
	if int(client.you.get("energy", 0)) < LOW:
		_goal = {"words": "the Common Table", "at": func(): return world.food_counter.global_position, "over": QuestMarks.OVER}
	elif _has_done_a_quest() and TownState.chest_ready(client.you, client.now_ms()):
		_goal = {"words": "your chest, at your door", "at": func(): return town.chest.global_position, "over": 1.8}
	else:
		_goal = {"words": "the Bounty Board", "at": town.board.front, "over": BountyBoard.FEET + BountyBoard.SIZE.y + 1.4}

func _has_done_a_quest() -> bool:
	return client.you.get("firsts", []).any(func(f): return f is Dictionary and str(f.get("first", "")) == "first_quest")

## The island's standing line: [words, metres] (metres -1 when it isn't anywhere), or [] for nothing to say.
func next_line() -> Array:
	if _goal.is_empty(): return []
	if not _goal.has("at"): return [_goal.words, -1]
	var at: Vector3 = _goal.at.call()
	return [_goal.words, Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()]

func _process(delta: float) -> void:
	_think_in -= delta
	if _think_in <= 0.0:
		_think_in = THINK_EVERY
		_think()
	var showing: bool = not _goal.is_empty() and _goal.has("at") and not town.board.is_open
	if not showing:
		_diamond.visible = false
		_set_map(Vector2(INF, INF))
		return
	_t += delta
	var at: Vector3 = _goal.at.call()
	_set_map(Vector2(at.x, at.z))
	var d := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
	var k := smoothstep(FOLD - 1.5, FOLD + 1.0, d)     # folds into where the key hint shows as you come within FOLD
	_diamond.visible = k > 0.01
	if not _diamond.visible: return
	_diamond.global_position = at + Vector3.UP * (float(_goal.over) - (1.0 - k) * 0.8 + QuestMarks.BOB * sin(_t * 2.2))
	_diamond.rotation.y = _t * QuestMarks.SPIN
	_diamond.scale = Vector3.ONE * k * (0.75 if _goal.get("waiting", false) else 1.0) * clampf(d / FAR_FROM, 1.0, 2.5)   # still a mark from far off

## The minimap's goal follows it, a person walking too.
func _set_map(at: Vector2) -> void:
	if at == _map_at or (at.is_finite() and _map_at.is_finite() and at.distance_to(_map_at) < 0.5): return
	_map_at = at
	town.set_goal(at if at.is_finite() else Vector2.INF)
