class_name LootCrate
extends Node3D
## The urgent loot crate (ux09, protocol 3 city.loot): a meal bought with your own money drops one at one of SPOTS, for anyone to reach
## first in the time it has. It falls out of the sky with a gold beam over it that's seen across town, the island calls it, the quest
## tracker counts it down, the guide's diamond and the minimap's route point at it, and the few townsfolk nearest run for it too.
## E at the crate claims it (ClaimLoot); the server says who got there first, and the prize comes as a reward.

const SPOTS := [Vector2(-21.5, -4.0), Vector2(-80.0, -10.6), Vector2(14.0, 6.5), Vector2(-27.0, 6.5), Vector2(-12.0, -12.0), Vector2(-96.0, 44.0)]   # the server's six, in its order
const SPOT_NAMES := ["Tally Square", "by the Bounty Board", "outside the Common Table", "outside the bank", "outside the Market Hall", "on the landing"]
const FALL := 0.9                  # s from the sky to the ground
const RUNNERS := 3                 # townsfolk who run for it
const BEAM_H := 26.0

var client: TownClient
var world: Node
var things: TownThings
var people: TownPeople
var _id := 0                       # the crate shown, 0 for none
var _box := Node3D.new()
var _beam := MeshInstance3D.new()
var _beam_mat := StandardMaterial3D.new()
var _thing := {}

func _ready() -> void:
	_build()
	visible = false
	client.city_changed.connect(_read)
	client.synced.connect(_read)
	client.event.connect(_on_event)
	client.refused.connect(_on_refused)
	_thing = things.add({"at": func(): return global_position, "reach": 2.2, "over": 1.3, "hint": _hint, "press": _claim, "priority": 2})

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Brand.TIMBER
	wood.roughness = 0.8
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("F0C33A")
	gold.metallic = 0.8
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color("F0C33A")
	gold.emission_energy_multiplier = 0.4
	for part in [[Vector3(0.9, 0.62, 0.62), Vector3(0, 0.31, 0), wood], [Vector3(0.94, 0.08, 0.66), Vector3(0, 0.12, 0), gold],
			[Vector3(0.94, 0.08, 0.66), Vector3(0, 0.5, 0), gold], [Vector3(0.14, 0.66, 0.66), Vector3(0, 0.31, 0), gold]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.position = part[1]
		mi.material_override = part[2]
		_box.add_child(mi)
	add_child(_box)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.25
	beam.bottom_radius = 0.45
	beam.height = BEAM_H
	beam.cap_top = false
	beam.cap_bottom = false
	_beam.mesh = beam
	_beam.position.y = BEAM_H * 0.5
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.94, 0.76, 0.23, 0.35)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

## The crate out now, as the server last said: {id, spot, prize, ends_at, claimed_by, out}, or empty.
func current() -> Dictionary:
	var loot = client.city.get("loot")
	if not loot is Dictionary or not bool(loot.get("out", false)): return {}
	if client.now_ms() >= int(loot.get("ends_at", 0)): return {}
	return loot

## Where the crate is (world), for the guide and the tracker; INF when none is out.
func where() -> Vector3:
	return global_position if visible and _id != 0 else Vector3.INF

func place_words() -> String:
	var loot := current()
	return SPOT_NAMES[int(loot.spot) % SPOTS.size()] if not loot.is_empty() else ""

func _read() -> void:
	var loot := current()
	if loot.is_empty():
		if _id != 0: _vanish(false)
		return
	if int(loot.id) != _id: _drop(loot)

## It falls from the sky at its spot, the beam comes on, the island calls it and the nearest townsfolk run for it.
func _drop(loot: Dictionary) -> void:
	_id = int(loot.id)
	var at: Vector2 = SPOTS[int(loot.spot) % SPOTS.size()]
	global_position = Vector3(at.x, world.height_at(at.x, at.y), at.y)
	visible = true
	_box.scale = Vector3.ONE
	_beam_mat.albedo_color.a = 0.0
	var t := create_tween().set_parallel()
	if HudMotion.on:
		_box.position.y = 22.0
		t.tween_property(_box, "position:y", 0.0, FALL).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		_box.position.y = 0.0
	t.tween_property(_beam_mat, "albedo_color:a", 0.35, 0.6).set_delay(FALL * 0.5)
	if Island.up: Island.up.urgent("Loot crate!", "%s · %s · first one there" % [Usdc.text(int(loot.prize)), SPOT_NAMES[int(loot.spot) % SPOTS.size()]])
	if people: people.rush_to(global_position, RUNNERS)

## Claimed or gone: the crate pops (yours) or shrinks away, the beam goes out, and the runners walk on.
func _vanish(mine: bool) -> void:
	_id = 0
	if people: people.stop_rush()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(_box, "scale", Vector3.ONE * (1.4 if mine else 0.01), 0.35)
	t.tween_property(_beam_mat, "albedo_color:a", 0.0, 0.35)
	t.chain().tween_callback(func(): if _id == 0: visible = false)

func _hint() -> String:
	var loot := current()
	if loot.is_empty() or int(loot.id) != _id: return ""
	return "Claim the crate · %s" % Usdc.text(int(loot.prize))

func _claim() -> void:
	if _id != 0: client.send({"type": "ClaimLoot", "id": _id})

func _on_event(e: Dictionary) -> void:
	match str(e.type):
		"LootClaimed":
			var mine := str(e.get("account", "")) == client.player
			if int(e.id) == _id: _vanish(mine)
			if Island.up:
				if mine: Island.up.urgent("Yours!", "%s from the loot crate · on its way to your wallet" % Usdc.text(int(e.prize)))
				else: Island.up.town("%s reached the crate first" % str(e.account), "Next time: it falls after a paid meal", true)
		"LootGone":
			if int(e.id) == _id: _vanish(false)

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") == "ClaimLoot" and Island.up: Island.up.town("Too late", Refusals.say(refusal, client.now_ms()))

func _process(_delta: float) -> void:
	if _id != 0 and HudMotion.on: _beam.rotation.y += _delta * 0.6
	if _id != 0 and current().is_empty(): _vanish(false)     # its time ran out between the server's words
