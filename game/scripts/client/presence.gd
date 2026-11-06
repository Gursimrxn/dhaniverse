class_name Presence
extends Node
## Everyone else in town: says where this body is a few times a second, and keeps one OtherPlayer per name the server mentions.
## Being seen isn't game state, so none of this goes through a command or the log.

const OtherPlayerScript := preload("res://scripts/life/other_player.gd")
const SEND_EVERY := 0.2            # s
const STILL_EVERY := 2.0           # s between saying so while standing still: someone joining must still see them

var client: TownClient
var player: CharacterBody3D
var tags: Control
var height_at := Callable()
var others := {}                   # name -> OtherPlayer
var _send_in := 0.0
var _still_for := 0.0
var _said_at := Vector3.INF

func _ready() -> void:
	client.presence.connect(_on_presence)
	client.left.connect(_on_left)
	client.link_changed.connect(func(up: bool): if not up: _clear())

func _process(delta: float) -> void:
	_send_in -= delta
	if _send_in > 0.0 or not client.up: return
	_send_in = SEND_EVERY
	var p := player.global_position
	_still_for += SEND_EVERY
	if p.distance_to(_said_at) < 0.02 and _still_for < STILL_EVERY: return
	_still_for = 0.0
	_said_at = p
	client.move({"type": "move", "x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01), "yaw": snappedf(player.body_yaw(), 0.01), "anim": "scooter" if player.on_scooter else ("walk" if player.velocity.length() > 0.3 else "idle")})

func _on_presence(players: Array) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var on_list := {}
	for d in players:
		var who := str(d.name)
		if who == client.player: continue
		on_list[who] = true
		if not others.has(who): others[who] = _add(who, d)
		(others[who] as OtherPlayer).heard(d, now)
	for who in others.keys():          # the list is the whole truth
		if not on_list.has(who): _on_left(who)

func _add(who: String, d: Dictionary) -> OtherPlayer:
	var o: OtherPlayer = OtherPlayerScript.new()
	add_child(o)
	o.setup(who, str(d.get("title", "")), bool(d.get("resident", false)), tags)
	return o

func _on_left(who: String) -> void:
	if not others.has(who): return
	(others[who] as OtherPlayer).leave()
	others.erase(who)

## The whole town has heard something: everyone in it stops and looks up.
func react(pleased: bool) -> void:
	for o in others.values(): (o as OtherPlayer).react(pleased)

func _clear() -> void:
	for who in others.keys(): _on_left(who)
