class_name QuestCrate
extends Node3D
## The quest crate (ux09): a quest done drops one at your feet (CrateDropped; you.crate while it waits), in the same wood, brass or gold
## as the chest at your door. E opens it (OpenCrate): the lid swings up on a back ease, the light spills, and each prize flies to the
## plate it belongs to: the energy to you, the tickets after it, a golden drop to the wallet with the gold light and the bell. Under
## three seconds; the server drew it all before it landed.

const FALL := 0.6                  # s from the sky to your feet
const LID_OPEN := -1.9
const BESIDE := 1.5                # m to your side it lands: never between you and what you face
const FLY := 0.7                   # s a prize takes to reach its plate

var client: TownClient
var world: Node
var things: TownThings
var sound: Sound
var _tier := ""                    # the crate out now, "" for none
var _box := Node3D.new()
var _lid := Node3D.new()
var _mat := StandardMaterial3D.new()
var _glow := OmniLight3D.new()
var _label := Label3D.new()
var _opening := false

func _ready() -> void:
	_build()
	visible = false
	client.event.connect(_on_event)
	client.you_changed.connect(_read)
	client.synced.connect(_read)
	things.add({"at": func(): return global_position, "reach": 2.0, "over": 1.2, "hint": _hint, "press": func(): client.send({"type": "OpenCrate"}), "priority": 0})

func _build() -> void:
	var band := StandardMaterial3D.new()
	band.albedo_color = Color("2a2522")
	band.metallic = 0.6
	band.roughness = 0.4
	for part in [[Vector3(0.8, 0.46, 0.56), Vector3(0, 0.23, 0), _mat], [Vector3(0.84, 0.06, 0.6), Vector3(0, 0.08, 0), band], [Vector3(0.84, 0.06, 0.6), Vector3(0, 0.38, 0), band]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		mi.mesh = b
		mi.position = part[1]
		mi.material_override = part[2]
		_box.add_child(mi)
	_lid.position = Vector3(0, 0.46, -0.28)          # hinged along the back
	var lid := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(0.84, 0.12, 0.6)
	lid.mesh = top
	lid.position = Vector3(0, 0.06, 0.28)
	lid.material_override = _mat
	_lid.add_child(lid)
	_box.add_child(_lid)
	_glow.light_color = Color("F0C33A")
	_glow.omni_range = 3.5
	_glow.light_energy = 0.0
	_glow.position = Vector3(0, 0.7, 0)
	_box.add_child(_glow)
	_label.font = Brand.FONT_DISPLAY
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 1.0, 0)
	_label.modulate = Brand.CREAM
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.6)
	_box.add_child(_label)
	add_child(_box)

func _hint() -> String:
	return "Open the %s crate" % _tier if _tier != "" and not _opening else ""

## A crate waiting (after a reconnect too): out at your feet if it isn't already.
func _read() -> void:
	var tier = client.you.get("crate")
	if tier == null or _opening: return
	if str(tier) != _tier: _drop(str(tier))

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"CrateDropped": _drop(str(e.get("tier", "wood")))
		"CrateOpened": _open(e)

## It falls beside you in its tier's material and settles with a bounce.
func _drop(tier: String) -> void:
	_tier = tier
	var p: Vector3 = world.player.global_position
	var yaw: float = world.player.body_yaw()
	var at := p + Vector3(cos(yaw), 0.0, -sin(yaw)) * BESIDE
	global_position = Vector3(at.x, world.height_at(at.x, at.z), at.z)
	rotation.y = yaw + PI
	_mat.albedo_color = DoorChest.TIER_COLOURS.get(tier, DoorChest.TIER_COLOURS.wood)
	_mat.metallic = 0.7 if tier != "wood" else 0.0
	_mat.roughness = 0.35 if tier != "wood" else 0.75
	_label.text = "%s CRATE" % tier.to_upper()
	_lid.rotation.x = 0.0
	_box.scale = Vector3.ONE
	visible = true
	if HudMotion.on:
		_box.position.y = 6.0
		create_tween().tween_property(_box, "position:y", 0.0, FALL).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		_box.position.y = 0.0
	if sound: sound.play("stamp")
	if Island.up: Island.up.town("A %s crate." % tier, "The quest's crate, at your feet · E opens it")

## The lid, the light, and the prizes flying to their plates.
func _open(e: Dictionary) -> void:
	_opening = true
	var c: Dictionary = e.get("contents", {})
	if sound: sound.play("paper")
	var t := create_tween()
	t.tween_property(_lid, "rotation:x", LID_OPEN, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_glow, "light_energy", 3.5, 0.3)
	t.tween_callback(_prize.bind("+%d energy" % int(c.get("energy", 0)), Brand.MINT, "you"))
	t.tween_interval(0.3)
	if int(c.get("tickets", 0)) > 0:
		t.tween_callback(_prize.bind("+%d ticket%s" % [int(c.tickets), "" if int(c.tickets) == 1 else "s"], Brand.CREAM, "you"))
		t.tween_interval(0.4)
	if bool(c.get("voucher", false)):
		t.tween_callback(_prize.bind("+1 meal voucher", Brand.CREAM, "you"))
		t.tween_interval(0.4)
	if int(c.get("golden_drop", 0)) > 0:
		t.tween_callback(func():
			if sound: sound.play("bell")
			_glow.light_energy = 7.0
			_prize("%s GOLDEN DROP" % Usdc.text(int(c.golden_drop)), Color("F0C33A"), "wallet"))
		t.tween_interval(0.6)
	t.tween_interval(0.6)
	t.tween_property(_box, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_glow, "light_energy", 0.0, 0.35)
	t.tween_callback(func():
		visible = false
		_tier = ""
		_opening = false)

## One prize: its words rise off the crate on the screen and fly to the plate they belong to ("you" or "wallet").
func _prize(words: String, colour: Color, to: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var plate: Control = world.energy_plate
	if cam == null or plate == null: return
	var label := GameHud.on_scene(Label.new(), Brand.FONT_DISPLAY, 18, colour)
	label.text = words
	world.ui.add_child(label)
	label.reset_size()
	var from := cam.unproject_position(global_position + Vector3.UP * 0.9) - label.size * 0.5
	var target := plate.global_position + (Vector2(150, 40) if to == "you" else Vector2(60, 110))
	label.position = from
	var t := label.create_tween()
	t.tween_property(label, "position", from + Vector2(0, -40), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position", target, FLY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(label, "scale", Vector2.ONE * 0.6, FLY)
	t.tween_property(label, "modulate:a", 0.0, 0.2)
	t.tween_callback(label.queue_free)
	if to == "wallet" and sound: t.tween_callback(func(): sound.play("coin"))
