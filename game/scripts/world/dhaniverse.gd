class_name Dhaniverse
extends Node3D
## Tallyport's things in the world (protocol 3): the Bounty Board and the Price Call board in the square, your chest at your door, the
## exchange on the landing and the Spice Merchant in the Market Hall, the sign painter, the town hall's clerk, the bank's clerk, your
## quests' markers and Grandma's pages, and the neighbour who brings a thali when you're stuck. The places the server names in a quest
## step (PROTOCOL.md: `place`) are found here. Everything is used with the interact key, on the thing (TownThings).

## Where each place is (x, y, z): y 0 means on the ground there, else the floor indoors. The rest are people, found where they stand.
const PLACES := {
	"square": Vector3(-24.5, 0.0, -6.0),
	"market": Vector3(-20.0, 0.31, -19.0),
	"table": Vector3(12.0, 0.01, 14.2),
	"bank": Vector3(-22.88, 0.76, 15.9),
	"homes": Vector3(-42.6, 0.0, 37.4),
	"strongbox": Vector3(-42.6, 0.0, 38.2),
}
const PEOPLE := ["harbourmaster", "kiosk", "spice-merchant", "painter", "stall", "hall"]
const BOARD_AT := Vector3(-84.0, 0.0, -13.6)       # the Bounty Board: across the main street from the road up from the landing, its face down that road
const PRICE_AT := Vector3(-31.5, 0.0, -11.2)       # the Price Call board
const CHEST_AT := Vector3(-38.9, 0.0, 38.1)        # your chest, at your door
const PAINTER_AT := Vector3(-26.0, 0.0, -13.2)
const SIGN_AT := Vector3(-28.2, 0.0, -13.6)
const CLERK_AT := Vector3(-62.6, 0.0, 7.4)         # by the Arrival Hall's door
const BANK_CLERK_AT := Vector3(-22.88, 0.76, 18.1)
const EXCHANGE := 1                # Kiosks.SHUT: the landing's second, by the jetty
const SPICE := 8                   # Kiosks.SHUT: one at the back of the Market Hall
const BEHIND_COUNTER := Vector3(1.45, 0.0, 0.85)   # in a kiosk's frame: where its keeper stands, by its front corner
const AT_COUNTER := Vector3(0.0, 0.0, 1.7)         # where a customer stands
const BANK_CLERK_LOOK := {"top": "eaf0f4", "tee": "eaf0f4", "skin": "b9805a", "hair": "2b2018", "bottom": "2a2a30", "shoes": "2a2a30", "open_top": false, "tall": 1.02}

var world: Node3D
var client: TownClient
var player: CharacterBody3D
var cinema: Cinema
var sound: Sound
var keeper: Harbourmaster
var hud: GameHud
var things := TownThings.new()
var marks := QuestMarks.new()
var guide := Guide.new()
var board := BountyBoard.new()
var price_board := PriceBoard.new()
var chest := DoorChest.new()
var spice := SpiceRun.new()
var painter := SignPainter.new()
var desk := TownPassDesk.new()
var bank_clerk: TownNpc
var _ground := {}                  # place -> its point, found once

## ui: the world's UI layer. kiosks: the market's, already set up with `named`.
func setup(ui: Control, kiosks: Kiosks) -> void:
	things.player = player
	things.busy = _busy
	add_child(things)
	things.setup(ui)
	for part in [board, price_board, chest, spice, painter, desk]:
		part.client = client
		part.player = player
		if "tell" in part: part.tell = tell
		add_child(part)
	board.world = world
	board.global_position = _on_ground(BOARD_AT)
	board.setup(ui)
	things.add({"at": board.front, "reach": 3.6, "over": 2.2, "hint": board.hint, "press": board.open})
	price_board.global_position = _on_ground(PRICE_AT)
	price_board.setup(ui)
	things.add({"at": func(): return price_board.global_position + Vector3(0, 0, 0.9), "reach": 2.4, "over": 2.4, "hint": price_board.hint, "press": price_board.open})
	chest.sound = sound
	chest.global_position = _on_ground(CHEST_AT)
	chest.setup(ui)
	things.add({"at": func(): return chest.global_position, "reach": 1.9, "over": 1.3, "hint": chest.hint, "press": chest.open_daily})
	things.add({"at": func(): return chest.global_position + DoorChest.WEEKLY_AT, "reach": 1.5, "over": 1.0, "hint": chest.weekly_hint, "press": chest.open_weekly})
	var ex: Transform3D = kiosks.placed[EXCHANGE]
	var sp: Transform3D = kiosks.placed[SPICE]
	spice.setup(ui, ex.translated_local(BEHIND_COUNTER), sp.translated_local(BEHIND_COUNTER))
	things.add({"at": func(): return ex * AT_COUNTER, "reach": 2.2, "over": 2.4, "hint": spice.swap_hint, "press": spice.open_swap})
	things.add({"at": func(): return sp * AT_COUNTER, "reach": 2.2, "over": 2.4, "hint": spice.deliver_hint, "press": spice.deliver})
	painter.setup(ui, Transform3D(Basis(), _on_ground(PAINTER_AT)), Transform3D(Basis(), _on_ground(SIGN_AT)))
	things.add({"at": func(): return painter.board_at() + Vector3(0, 0, 0.9), "reach": 2.2, "over": 2.7, "hint": painter.sign_hint, "press": painter.open})
	desk.setup(ui, Transform3D(Basis(Vector3.UP, PI), _on_ground(CLERK_AT)))
	things.add({"at": desk.desk_at, "reach": 2.2, "over": 2.0, "hint": desk.hint, "press": desk.ask})
	bank_clerk = TownNpc.new()
	bank_clerk.player = player
	add_child(bank_clerk)
	bank_clerk.setup("Arthur, the bank's clerk", BANK_CLERK_LOOK, ui)
	bank_clerk.global_transform = Transform3D(Basis(Vector3.UP, PI), BANK_CLERK_AT)
	marks.town = self
	marks.client = client
	add_child(marks)
	guide.town = self
	guide.client = client
	guide.player = player
	guide.world = world
	add_child(guide)
	board.done_today = guide.done_today
	board.paint = paint
	for part in [board, price_board, chest, painter, desk]: paint(part)
	chest.tier_look = _own_look.get(chest.tier_mat)
	client.event.connect(_on_event)
	client.refused.connect(_on_refused)

## The keys and the screen are someone else's: a sheet, a film, the stall, the food counter, the phone.
func _busy() -> bool:
	if player.frozen or world.any_sheet_open() or world.director.busy: return true
	if world.stall.in_rush or world.stall.behind: return true
	return world.food_counter._here

func tell(line: String) -> void:
	cinema.say(line, clampf(line.length() * 0.06, 3.5, 7.0))

func sound_play(what: String) -> void:
	if sound: sound.play(what)

func set_goal(at: Vector2) -> void:
	if hud: hud.set_goal(at)

func knows(place: String) -> bool:
	return PLACES.has(place) or place in PEOPLE

func is_person(place: String) -> bool:
	return place in ["harbourmaster", "spice-merchant", "painter", "hall"]

## Where a quest's place is now (a person moves).
func place_at(place: String) -> Vector3:
	match place:
		"harbourmaster": return keeper.person.global_position if keeper and keeper.person else Vector3.ZERO
		"kiosk": return spice.keeper.global_position
		"spice-merchant": return spice.merchant.global_position
		"painter": return painter.painter.global_position
		"stall": return painter.board_at()
		"hall": return desk.clerk.global_position
	if not _ground.has(place): _ground[place] = _on_ground(PLACES.get(place, Vector3.ZERO))
	return _ground[place]

func greet(place: String) -> void:
	match place:
		"harbourmaster": if keeper: keeper.wave()
		"spice-merchant": spice.merchant.greet()
		"painter": painter.painter.greet()
		"hall": desk.clerk.greet()
		"bank": bank_clerk.greet()

## What's built here out of plain shapes, lit as the town's own buildings are (world.gd's _town_mat: the valley's sky light is in the
## shaders, so a plain StandardMaterial3D in shade goes black). A material marked "own" gets a copy of its own, for whoever recolours it.
var _own_look := {}                # a StandardMaterial3D marked own -> its town material

func paint(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var sm := m.material_override as StandardMaterial3D
		if sm == null or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or not (m.mesh is PrimitiveMesh or m.mesh is ArrayMesh): continue
		if m.mesh is PrimitiveMesh: (m.mesh as PrimitiveMesh).material = sm
		else: (m.mesh as ArrayMesh).surface_set_material(0, sm)
		if sm.has_meta("own"):
			if not _own_look.has(sm): _own_look[sm] = (world._town_mat(m.mesh, 0) as Material).duplicate()
			m.material_override = _own_look[sm]
		else:
			m.material_override = world._town_mat(m.mesh, 0)

## y 0: the ground there. Otherwise as given (a floor indoors).
func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, world.height_at(p.x, p.z) if p.y == 0.0 else p.y, p.z)

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") in ["QuestStep", "AbandonQuest"]: tell(Refusals.say(refusal, client.now_ms()))

# --- the neighbour with a thali (RescueComing, RescueMeal) ----------------------------------------------------------------------

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"RescueMeal": _rescue(int(e.get("energy", 0)), bool(e.get("direct", false)))
		"QuestStepDone":
			if str(e.get("step", "")) == "clerk" and str(e.get("quest", "")) == "grandma": bank_clerk.greet()
		"QuestDone":
			if str(e.get("quest", "")) == "grandma":     # her strongbox: the season's grand chest
				var r: Dictionary = e.get("reward", {})
				var paid := int(r.get("usdc", 0))
				# Bitroad, the kicker's face, has no apostrophe
				world.blast.show_reveal(str(r.get("title", "Grandma's Heir")) if r.get("title") != null else "Grandma's Heir",
					"Her strongbox is open%s. Every page, found." % ((": " + Usdc.text(paid)) if paid > 0 else ""), "HER LEDGER · THE STRONGBOX")

## The neighbour walks up with a thali, hands it over and goes. With `direct` the town's safety net was empty and the energy came
## anyway: they still come, with the same plate.
func _rescue(energy: int, direct: bool) -> void:
	var v := Visitor.new()
	v.player = player
	v.cinema = cinema
	add_child(v)
	v.come(["You look done in. Here, a thali, on the town.", "Eat. That's %d energy back%s." % [energy, " — the town's covering it" if direct else ""]])
	var plate := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.17
	pm.bottom_radius = 0.13
	pm.height = 0.05
	plate.mesh = pm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("c8ccd0")
	steel.metallic = 0.8
	steel.roughness = 0.3
	plate.material_override = steel
	plate.position = Vector3(0, 1.0, 0.32)
	v.add_child(plate)
	paint(v)
	v.arrived.connect(func():
		if not is_instance_valid(plate): return
		var from := plate.global_position
		plate.get_parent().remove_child(plate)
		player.avatar.reach(from)
		player.avatar.set_carrying(true)
		player.avatar.hold(plate, from)
		get_tree().create_timer(1.8).timeout.connect(func():
			if is_instance_valid(plate): plate.queue_free()
			player.avatar.set_carrying(false)), CONNECT_ONE_SHOT)
