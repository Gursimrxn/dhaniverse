class_name TownPassDesk
extends Node3D
## The town hall's clerk, at a desk by the Arrival Hall's door, and the Town Pass (PROTOCOL.md, The Town Pass): one pass for one real
## person, proven with World ID. Asking for it (TownPass) gets a one-time link and the same link as a QR code (qr), which the Town
## Pass gate (TownPassGate) draws for the World App on the player's phone: nothing opens in a browser. The game waits for
## HumanVerified, when everything the town owed you is paid and your name is registered. Pressing E at the desk, or the phone's
## wallet page, opens the gate (open_gate).

const LOOK := {"top": "28324a", "tee": "eaf0f4", "skin": "c58c5c", "hair": "3a2a20", "bottom": "2a2a30", "shoes": "2a2a30", "open_top": false, "tall": 1.0, "bun": true}

signal waiting_changed(waiting: bool)

var client: TownClient
var player: CharacterBody3D
var tell := Callable()
var clerk: TownNpc
var waiting := false               # a link was given: waiting for World ID
var qr: Array = []                 # the link's QR code, row by row ("1" dark), for the gate to draw
var url := ""                      # the link itself: the gate's "open here", for World ID's simulator on this computer
var open_gate := Callable()        # the Town Pass gate's open: what pressing E at the desk does

func setup(ui: Control, clerk_at: Transform3D) -> void:
	clerk = TownNpc.new()
	clerk.player = player
	add_child(clerk)
	clerk.setup("The town hall's clerk", LOOK, ui)
	clerk.offers = "Town Pass, World ID"
	clerk.global_transform = clerk_at
	var desk := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.4, 0.95, 0.6)
	desk.mesh = dm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Brand.TIMBER
	desk.material_override = wood
	add_child(desk)
	desk.global_transform = clerk_at.translated_local(Vector3(0, 0.475, 0.75))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dm.size
	cs.shape = box
	body.add_child(cs)
	desk.add_child(body)
	var plate := Label3D.new()
	plate.text = "TOWN PASS"
	plate.font = Brand.FONT_DISPLAY
	plate.font_size = 56
	plate.pixel_size = 0.0025
	plate.modulate = Brand.CREAM
	plate.outline_size = 0
	plate.position = Vector3(0, 0.1, 0.31)
	desk.add_child(plate)
	client.replied.connect(_on_replied)
	client.refused.connect(_on_refused)
	client.event.connect(_on_event)

func desk_at() -> Vector3:
	return clerk.global_position + clerk.global_basis * Vector3(0, 0, 1.6)

func hint() -> String:
	if client.you.is_empty() or bool(client.you.get("human", false)): return ""
	return "Waiting for World ID…" if waiting else "Get your Town Pass"

## E at the desk: the gate, with its code (or asking for one straight away, before the gate exists).
func press() -> void:
	if open_gate.is_valid(): open_gate.call()
	else: ask()

## Ask for a one-time link and its code: the gate draws it when the server sends it.
func ask() -> void:
	if bool(client.you.get("human", false)): return
	if clerk: clerk.greet()
	client.send({"type": "TownPass"})

func _on_replied(command: Dictionary, reply: Dictionary) -> void:
	if command.get("type") != "TownPass": return
	var link := str(reply.get("url", ""))
	if link == "": return
	url = link
	qr = reply.get("qr", [])
	waiting = true
	waiting_changed.emit(true)
	if DisplayServer.get_name() == "headless": print("town pass: ", url)    # a test reads it here

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") == "TownPass" and tell.is_valid(): tell.call(Refusals.say(refusal, client.now_ms()))

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	if e.type == "HumanVerified" and waiting:
		waiting = false
		waiting_changed.emit(false)
