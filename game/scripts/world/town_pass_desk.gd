class_name TownPassDesk
extends Node3D
## The town hall's clerk, at a desk by the Arrival Hall's door, and the Town Pass (PROTOCOL.md, The Town Pass): one pass for one real
## person, proven with World ID. Asking for it (TownPass) gets a one-time link; it opens in the system browser, and the game waits for
## HumanVerified, when everything the town owed you is paid and your name (sam.tallyport.eth) is registered. The phone's wallet page
## asks the same way (ask()).

const LOOK := {"top": "28324a", "tee": "eaf0f4", "skin": "c58c5c", "hair": "3a2a20", "bottom": "2a2a30", "shoes": "2a2a30", "open_top": false, "tall": 1.0, "bun": true}

signal waiting_changed(waiting: bool)

var client: TownClient
var player: CharacterBody3D
var tell := Callable()
var clerk: TownNpc
var waiting := false               # a link was opened: waiting for World ID

func setup(ui: Control, clerk_at: Transform3D) -> void:
	clerk = TownNpc.new()
	clerk.player = player
	add_child(clerk)
	clerk.setup("The town hall's clerk", LOOK, ui)
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

## Ask for a one-time link. It opens in the browser when the server sends it.
func ask() -> void:
	if bool(client.you.get("human", false)): return
	if clerk: clerk.greet()
	client.send({"type": "TownPass"})

func _on_replied(command: Dictionary, reply: Dictionary) -> void:
	if command.get("type") != "TownPass": return
	var url := str(reply.get("url", ""))
	if url == "": return
	waiting = true
	waiting_changed.emit(true)
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--no-browser"): print("town pass: ", url)    # a test reads it here
	else: OS.shell_open(url)
	if tell.is_valid():
		tell.call("The pass page is open in your browser: prove you're one real person with World ID." + (" A rehearsal pass is offered." if client.debug else ""))

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") == "TownPass" and tell.is_valid(): tell.call(Refusals.say(refusal, client.now_ms()))

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	if e.type == "HumanVerified" and waiting:
		waiting = false
		waiting_changed.emit(false)
