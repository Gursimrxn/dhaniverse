class_name BountyBoard
extends Node3D
## The Bounty Board, where the road from the landing meets the town: a big notice board under a little roof with two warm lamps, a
## paper card pinned up for each thing the town will pay you for. Sponsored quests from the chain (city.bounty, the live ones), today's
## errands, today's mystery and Grandma's Ledger. Each card says what it is (its badge), who pays, what it costs in energy, the fixed
## USDC it pays and how many places are left; one done today is chalked "done", one you're on is only a torn stub on its pin.
## E at the board: the camera eases up to it, the plates dim, and the island turns into the board's bar. Left and Right choose (the
## card lifts off the cork), hold E to tear it off (TakeQuest), Esc steps back. The board's cards are also on Arkiv when its publisher
## answers (GET /arkiv/campaigns).

const SIZE := Vector2(6.4, 2.7)    # the cork, m
const FEET := 0.8                  # its bottom edge over the ground
const CARD := Vector2(0.9, 0.72)
const COLS := 6
const CARDS := 12                  # pinned at once
const STUB := 0.1                  # m of a card left on its pin once torn off
const HOLD := 0.8                  # s E is held to tear a card off
const FLY := 0.8                   # s the camera takes to ease up to the board
const LIFT := 0.3                  # s the chosen card takes to lift
const MARGIN := 0.5                # m the camera keeps clear round the board, its posts and its head
const FOCUS_H := SIZE.y + 0.8       # m framed: the cork, the ledge and the head plank
const FOCUS_Y := FEET + SIZE.y * 0.5 + 0.55
const PAPER := Color("FFF8E3")
const INK := Color("262727")
const MUTED := Color("5d5e5e")
const PIN := Color("9d9477")
const GOLD := Color("F0C33A")
const LAMP := Color("ffc879")
## kind -> [badge colour, badge words colour]: orange Rush, magenta a sponsored swap, green ENS, blue the mystery, ink the errands.
const BADGES := {"rush": [Color("FF6600"), INK], "swap": [Color("E100FF"), INK], "ens": [Color("337E43"), PAPER], "mystery": [Color("0011FF"), PAPER],
	"errand": [INK, PAPER], "grandma": [Color("F0C33A"), INK]}
const ARKIV_EVERY := 10.0          # s: the server caches it this long anyway

var client: TownClient
var player: CharacterBody3D
var world: Node3D
var tags: Control
var paint := Callable()            # lights what's built here as the town is lit (Dhaniverse.paint)
var is_open := false
var pick := 0
var done_today := Callable()       # quest id -> true when it was finished today (Guide)
var _cards := Node3D.new()
var _said := ""
var _offers: Array = []
var _built: Array = []             # each offer's card: {node, body, base: Transform3D}
var _arkiv := {}                   # campaign id (string) -> its Arkiv card
var _arkiv_source := ""
var _http: HTTPRequest
var _asked_at := -INF
var _hold := 0.0
var _armed := false                # E was let go since the board opened: a new press is a hold
var _taking := -1                  # the card a TakeQuest went for, waiting on its answer
var _lifts := {}                   # card index -> its tween
var _dimmed: Array = []

func setup(ui: Control) -> void:
	tags = ui
	_build()
	add_child(_cards)
	client.city_changed.connect(_pin_up)
	client.you_changed.connect(_pin_up)
	client.synced.connect(_pin_up)
	client.refused.connect(_on_refused)
	client.replied.connect(_on_replied)
	_http = HTTPRequest.new()
	_http.timeout = 4.0
	add_child(_http)
	_http.request_completed.connect(_on_arkiv)
	set_process(false)

## Where to stand to use it, d m in front of its face.
func front(d := 1.0) -> Vector3:
	return global_transform * Vector3(0, 0, d)

## Over the board's roof: where the gold marker floats when the board is where to go next.
func top() -> Vector3:
	return global_transform * Vector3(0, FEET + SIZE.y + 1.5, 0)

# --- the thing itself ------------------------------------------------------------------------------------------------------------

func _build() -> void:
	var wood := _mat(Brand.TIMBER, 0.8)
	var dark := _mat(Color("6e4528"), 0.85)
	var cork := _mat(Color("6b4a32"), 0.95)
	var slate := _mat(Brand.SLATE, 0.7)
	var tall := FEET + SIZE.y + 0.75
	for side in [-1.0, 1.0]:
		_box(Vector3(0.16, tall, 0.16), Vector3(side * (SIZE.x * 0.5 + 0.1), tall * 0.5, 0.0), wood)
		_lamp(side)
	_box(Vector3(SIZE.x, SIZE.y, 0.1), Vector3(0, FEET + SIZE.y * 0.5, 0), cork)
	_box(Vector3(SIZE.x + 0.08, 0.08, 0.14), Vector3(0, FEET - 0.02, 0.02), dark)              # a ledge under the cork
	_box(Vector3(SIZE.x + 0.36, 0.5, 0.12), Vector3(0, FEET + SIZE.y + 0.3, 0.0), dark)        # the head plank
	for slope in [-1.0, 1.0]:      # a little gable roof, its ridge along the board
		var roof := _box(Vector3(SIZE.x + 0.9, 0.06, 0.62), Vector3(0, FEET + SIZE.y + 0.82, slope * 0.27), slate)
		roof.rotation.x = slope * 0.5
	var head := Label3D.new()
	head.text = "BOUNTY BOARD"
	head.font = Brand.FONT_DISPLAY
	head.font_size = 128
	head.pixel_size = 0.0028
	head.modulate = Brand.CREAM
	head.outline_size = 0
	head.position = Vector3(0, FEET + SIZE.y + 0.3, 0.065)
	add_child(head)
	var collide := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x + 0.4, FEET + SIZE.y, 0.3)
	cs.shape = box
	cs.position.y = (FEET + SIZE.y) * 0.5
	collide.add_child(cs)
	add_child(collide)

## A lantern on an arm off the post's top, lit warm, so the board reads from down the road and after dark.
func _lamp(side: float) -> void:
	var x := side * (SIZE.x * 0.5 + 0.1)
	var y := FEET + SIZE.y + 0.15
	var iron := _mat(Color("2b2b2b"), 0.5)
	_box(Vector3(0.04, 0.04, 0.34), Vector3(x, y + 0.42, 0.17), iron)
	_box(Vector3(0.18, 0.03, 0.18), Vector3(x, y + 0.36, 0.34), iron)
	var glass := _mat(LAMP, 0.4)
	glass.emission_enabled = true
	glass.emission = LAMP
	glass.emission_energy_multiplier = 2.2
	_box(Vector3(0.14, 0.2, 0.14), Vector3(x, y + 0.24, 0.34), glass)
	var light := OmniLight3D.new()
	light.light_color = LAMP
	light.light_energy = 1.4
	light.omni_range = 5.5
	light.shadow_enabled = false
	light.position = Vector3(x, y + 0.2, 0.5)
	add_child(light)

func _mat(colour: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	return m

func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi

# --- the cards ---------------------------------------------------------------------------------------------------------------------

## A card for each offer, pinned up in two rows. Rebuilt only when what's on offer changes.
func _pin_up() -> void:
	if _taking >= 0: return        # a card's being torn off: the board changes once it's off
	_offers = TownState.offers(client.you, client.city).slice(0, CARDS)
	var said := JSON.stringify(_offers.map(func(o): return [o.quest, o.pays, o.on, o.card.get("slots_left", 0), _left(o), _done(o), on_arkiv(o)]))
	if said == _said: return
	_said = said
	for c in _cards.get_children(): c.queue_free()
	_built.clear()
	_lifts.clear()
	for i in _offers.size():
		var at := Vector3(-SIZE.x * 0.5 + 0.55 + (i % COLS) * 1.06, FEET + SIZE.y * 0.5 + 0.59 - (i / COLS) * 1.18, 0.06)
		var tilt := (fmod(i * 0.37, 1.0) - 0.5) * 0.1
		_built.append(_card(_offers[i], Transform3D(Basis(Vector3.BACK, tilt), at)))
	if paint.is_valid(): paint.call(_cards)
	pick = clampi(pick, 0, maxi(_offers.size() - 1, 0))
	if is_open: _choose(pick, true)

## What kind of card: its badge and the word on it.
static func badge(o: Dictionary) -> Array:
	match str(o.by):
		"sponsored":
			var t := str(o.card.get("template", ""))
			if t == "spice_run": return ["swap", "swap"]
			if t == "paint_sign": return ["ens", "ens"]
			return ["swap", "paid"]
		"mystery": return ["mystery", "?!"]
		"grandma": return ["grandma", "gran"]
	var words := str(o.title).to_lower().trim_prefix("the ").split(" ", false)    # "The Chai Round" -> "chai"
	return ["errand", words[0].left(5) if not words.is_empty() else "job"]

## Who pays for it, in a few words.
func _who(o: Dictionary) -> String:
	match str(o.by):
		"sponsored":
			var s := str(o.card.get("sponsor", ""))
			return "paid by %s" % (TownState.short_address(s) if s.begins_with("0x") else s)
		"mystery": return "a sponsor pays" if o.get("boosted_by") != null else "the house pays"
		"grandma": return "her ledger · once a season"
	return "errand · the house pays"

## How many places are left, in words, or "".
func _left(o: Dictionary) -> String:
	match str(o.by):
		"sponsored": return "%d left" % int(o.card.get("slots_left", 0))
		"errand": return "%d of %d today" % [int(client.you.get("errands_left", 0)), int(client.city.get("errands", {}).get("per_day", 3))]
		"mystery": return "1 a day"
	return ""

func _done(o: Dictionary) -> bool:
	if done_today.is_valid() and done_today.call(str(o.quest)): return true
	return str(o.by) == "mystery" and not o.on and int(client.you.get("mystery_left", 1)) <= 0

func _card(o: Dictionary, base: Transform3D) -> Dictionary:
	var card := Node3D.new()
	card.transform = base
	_cards.add_child(card)
	var stub := _paper(Vector2(CARD.x, STUB), Vector3(0, CARD.y * 0.5 - STUB * 0.5, 0), card, true)
	var pin := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.028
	pm.height = 0.056
	pin.mesh = pm
	pin.material_override = _mat(PIN, 0.4)
	(pin.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # its own, unpainted: it turns gold when chosen
	pin.position = Vector3(0, CARD.y * 0.5 - 0.05, 0.02)
	card.add_child(pin)
	var built := {"node": card, "base": base, "pin": pin, "stub": stub}
	if o.on: return built          # you're on it: torn off, only the stub's left
	var body := Node3D.new()
	card.add_child(body)
	built.body = body
	_paper(Vector2(CARD.x, CARD.y - STUB), Vector3(0, -STUB * 0.5, 0), body, false)
	var kind := badge(o)
	var look: Array = BADGES[kind[0]]
	# a Label3D's origin is where its line starts (left), ends (right) or is centred: the width only wraps it
	var l := -CARD.x * 0.5 + 0.06
	var r := CARD.x * 0.5 - 0.06
	var top := CARD.y * 0.5 - STUB - 0.1
	_box(Vector3(0.16, 0.16, 0.004), Vector3(l + 0.08, top, 0.004), _mat(look[0], 0.9), body)
	_words(body, kind[1], Brand.FONT_DISPLAY, 34, look[1], Vector3(l + 0.08, top, 0.009), HORIZONTAL_ALIGNMENT_CENTER, 0.16)
	var left := _left(o)
	if left != "": _words(body, left, Brand.FONT_BODY, 26, MUTED, Vector3(r, top + 0.04, 0.005), HORIZONTAL_ALIGNMENT_RIGHT, 0.5)
	if on_arkiv(o): _words(body, "on Arkiv", Brand.FONT_BODY, 24, Brand.GREEN, Vector3(r, top - 0.03, 0.005), HORIZONTAL_ALIGNMENT_RIGHT, 0.5)
	var title := _words(body, str(o.title).to_lower(), Brand.FONT_EDITORIAL, 58 if str(o.title).length() <= 16 else 46, INK, Vector3(l, -0.08, 0.005), HORIZONTAL_ALIGNMENT_LEFT, r - l)
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_words(body, _who(o), Brand.FONT_BODY, 24, MUTED, Vector3(l, -0.14, 0.005), HORIZONTAL_ALIGNMENT_LEFT, r - l)
	var cost := "%d energy" % int(o.energy) if int(o.energy) > 0 else "no energy"
	_words(body, cost, Brand.FONT_BODY, 28, INK, Vector3(l, -CARD.y * 0.5 + 0.07, 0.005), HORIZONTAL_ALIGNMENT_LEFT, 0.5)
	var pays := "$" + Usdc.amount(int(o.pays)) if int(o.pays) >= 0 else "a strongbox"
	_words(body, pays, Brand.FONT_BODY, 40, Brand.BLUE, Vector3(r, -CARD.y * 0.5 + 0.075, 0.005), HORIZONTAL_ALIGNMENT_RIGHT, 0.5)
	if _done(o):
		var chalk := _words(body, "done", Brand.FONT_EDITORIAL, 160, Color(Brand.GREEN, 0.85), Vector3(0.02, -0.06, 0.012), HORIZONTAL_ALIGNMENT_CENTER, CARD.x)
		chalk.rotation.z = 0.21
	return built

## A sheet of the card's paper; the stub's lower edge is torn.
func _paper(size: Vector2, at: Vector3, parent: Node3D, torn: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if torn:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.BACK)
		var teeth := 14
		for k in teeth:
			var x0 := -size.x * 0.5 + size.x * k / teeth
			var x1 := x0 + size.x / teeth
			var dip := -size.y * 0.5 - (0.018 if k % 2 == 0 else 0.0)
			for v in [Vector3(x0, size.y * 0.5, 0), Vector3(x1, size.y * 0.5, 0), Vector3(x0, dip, 0), Vector3(x1, size.y * 0.5, 0), Vector3(x1, -size.y * 0.5 - 0.009, 0), Vector3(x0, dip, 0)]:
				st.add_vertex(v)
		var m := _mat(PAPER, 1.0)
		st.set_material(m)
		mi.mesh = st.commit()
		mi.material_override = m
	else:
		var q := QuadMesh.new()
		q.size = size
		mi.mesh = q
		mi.material_override = _mat(PAPER, 1.0)
	mi.position = at
	parent.add_child(mi)
	return mi

func _words(parent: Node3D, text: String, font: Font, px: int, ink: Color, at: Vector3, align: HorizontalAlignment, width: float) -> Label3D:
	var t := Label3D.new()
	t.text = text
	t.font = font
	t.font_size = px
	t.pixel_size = 0.0018
	t.modulate = ink
	t.outline_size = 0
	t.horizontal_alignment = align
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.width = width / t.pixel_size
	t.position = at
	t.visibility_range_end = 32.0
	parent.add_child(t)
	return t

# --- in focus ----------------------------------------------------------------------------------------------------------------------

## The interact key at the board.
func hint() -> String:
	if client.you.is_empty(): return ""
	return "Read the Bounty Board" if not _offers.is_empty() else ""

## E at the board: the camera eases up to its face, the player stands still, the plates dim, the island holds the keys.
func open() -> void:
	if is_open or _offers.is_empty(): return
	_ask_arkiv()
	is_open = true
	_armed = false
	_hold = 0.0
	_taking = -1
	set_process(true)
	player.frozen = true
	var to := global_position - player.global_position
	player.rest_yaw = atan2(to.x, to.z)
	player.rig.hold_view(atan2(-to.x, -to.z))
	_dim(true)
	if Island.up: Island.up.board_bar(true)
	var first := 0
	for i in _offers.size():
		if not _offers[i].on and not _done(_offers[i]):
			first = i
			break
	_choose(first, true)
	var eye := get_viewport().get_camera_3d()
	var fov := eye.fov
	var to_eye := _focus_eye(fov)
	var from := eye.global_position
	await world.director.fly([from, to_eye], [from - eye.global_basis.z * from.distance_to(to_eye), _focus_at()], FLY, fov, false)
	if is_open: player.avatar.visible = false      # the camera is where they stand: nothing between it and the cards

## Far enough back that the whole board fits, with MARGIN round it, at this fov.
func _focus_eye(fov: float) -> Vector3:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var half_v := tan(deg_to_rad(fov) * 0.5)
	var d := maxf((SIZE.x * 0.5 + 0.2 + MARGIN) / (half_v * aspect), (FOCUS_H * 0.5 + MARGIN) / half_v)
	return global_transform * Vector3(0, FOCUS_Y, d)

## The middle of what's framed (the cork and the head plank), a little high so the island's bar doesn't cover the head.
func _focus_at() -> Vector3:
	return global_transform * Vector3(0, FOCUS_Y, 0)

## Esc, or a card taken: the camera lands back on the player.
func close() -> void:
	if not is_open: return
	is_open = false
	set_process(false)
	_hold = 0.0
	_unlift(pick)
	_dim(false)
	if Island.up: Island.up.board_bar(false)
	player.avatar.visible = true
	player.rest_yaw = null
	player.rig.hold_view(null)
	await world.director.land(FLY)
	if not is_open:
		player.frozen = false
		player.rig.take_cursor_back()

## The HUD's plates fade back to a third while the board has the screen; the island stays.
func _dim(on: bool) -> void:
	if on: _dimmed = [world.energy_plate, world.hud]
	for p in _dimmed:
		if is_instance_valid(p): create_tween().tween_property(p, "modulate:a", 0.35 if on else 1.0, 0.25).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _input(e: InputEvent) -> void:
	if not is_open: return
	if e.is_action_released("interact"):
		_armed = true
		return
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo: return
	match k.keycode:
		KEY_LEFT, KEY_A: _choose(pick - 1)
		KEY_RIGHT, KEY_D: _choose(pick + 1)
		KEY_UP, KEY_W: _choose(pick - COLS)
		KEY_DOWN, KEY_S: _choose(pick + COLS)
		KEY_ESCAPE: close()
		_:
			if not e.is_action("interact"): return
	get_viewport().set_input_as_handled()

## Holding E fills the island's ring; let go early and it drains. Full: the card's taken.
func _process(delta: float) -> void:
	if _taking >= 0: return
	var held := _armed and Input.is_action_pressed("interact")
	_hold = clampf(_hold + delta / HOLD if held else _hold - delta / (HOLD * 0.4), 0.0, 1.0)
	if Island.up: Island.up.board_hold(_hold)
	if _hold >= 1.0: take(pick)

func _choose(i: int, quiet := false) -> void:
	if _offers.is_empty() or _taking >= 0: return
	i = clampi(i, 0, _offers.size() - 1)
	if i == pick and not quiet: return
	_unlift(pick)
	pick = i
	_hold = 0.0
	if Island.up: Island.up.board_card(str(_offers[i].title).to_lower(), _energy_words(_offers[i]))
	_lift(i)

func _energy_words(o: Dictionary) -> String:
	if o.on: return "you're on this one"
	if _done(o): return "done today"
	return "%d energy of your %d" % [int(o.energy), int(client.you.get("energy", 0))]

## The chosen card comes off the cork towards the camera.
func _lift(i: int) -> void:
	if i >= _built.size(): return
	var c: Dictionary = _built[i]
	(c.pin.material_override as StandardMaterial3D).albedo_color = GOLD
	_move(i, Transform3D(Basis().scaled(Vector3.ONE * 1.12), c.base.origin + Vector3(0, 0.02, 0.22)))

func _unlift(i: int) -> void:
	if i >= _built.size(): return
	var c: Dictionary = _built[i]
	if is_instance_valid(c.pin): (c.pin.material_override as StandardMaterial3D).albedo_color = PIN
	_move(i, c.base)

func _move(i: int, to: Transform3D) -> void:
	var node: Node3D = _built[i].node
	if not is_instance_valid(node): return
	if _lifts.has(i): (_lifts[i] as Tween).kill()
	_lifts[i] = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_lifts[i].tween_property(node, "transform", to, LIFT)

## Tear it off: TakeQuest goes to the server, and the card comes away when it says yes (_on_replied).
func take(i: int) -> void:
	if i >= _offers.size() or _taking >= 0: return
	pick = i
	var o: Dictionary = _offers[i]
	if o.on:
		_refuse("You're on this one: it's in your quest log.")
		return
	_taking = i
	client.send({"type": "TakeQuest", "quest": str(o.quest)})

func _refuse(words: String) -> void:
	_hold = 0.0
	_taking = -1
	_pin_up()
	if Island.up:
		Island.up.board_hold(0.0)
		Island.up.board_say(words)

func _on_replied(command: Dictionary, _reply: Dictionary) -> void:
	if command.get("type") != "TakeQuest" or _taking < 0: return
	var i := _taking
	_taking = -1
	if i < _built.size() and _built[i].has("body"): _tear(_built[i])
	_pin_up()                      # what came in while it was being taken: the taken one is a stub now
	if is_open:
		await get_tree().create_timer(0.45).timeout
		close()
		_into_hand()

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") != "TakeQuest" or _taking < 0: return
	_refuse(Refusals.say(refusal, client.now_ms()))

## The card comes off its stub and swings down past the camera, into the hand.
func _tear(c: Dictionary) -> void:
	var body: Node3D = c.body
	var from := body.global_transform
	body.get_parent().remove_child(body)
	add_child(body)
	body.global_transform = from
	var eye := _focus_eye(get_viewport().get_camera_3d().fov)
	var to := from.origin.lerp(eye, 0.55) + Vector3.DOWN * 1.3
	var t := create_tween().set_parallel()
	t.tween_property(body, "global_position", to, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.tween_property(body, "rotation:z", body.rotation.z - 0.6, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.tween_property(body, "rotation:x", -0.9, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(body.queue_free)
	if world.sound: world.sound.play("paper")

## Back in the player's view, the card's in their hand a moment, then pocketed.
func _into_hand() -> void:
	var card := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.18, 0.006, 0.14)
	card.mesh = b
	var m := _mat(PAPER, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	card.material_override = m
	var from := front(0.3) + Vector3.UP * 1.6
	player.avatar.set_carrying(true)
	player.avatar.hold(card, from)
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(card): card.queue_free()
		player.avatar.set_carrying(false))

# --- Arkiv -------------------------------------------------------------------------------------------------------------------------

## The Arkiv copy of the board, through the server (PROTOCOL.md, HTTP). If it isn't answering, the board is city.bounty alone.
func _ask_arkiv() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t - _asked_at < ARKIV_EVERY or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	_asked_at = t
	if _http.request(client.http_base() + "/arkiv/campaigns") != OK: _asked_at = -INF

func _on_arkiv(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var got = JSON.parse_string(body.get_string_from_utf8())
	if not got is Dictionary: return
	_arkiv.clear()
	for c in got.get("cards", []):
		if c is Dictionary and c.has("id"): _arkiv[str(c.id).trim_suffix(".0")] = c
	_arkiv_source = str(got.get("source", "arkiv")) if not _arkiv.is_empty() else ""
	_pin_up()

## Is this sponsored card's campaign also published on Arkiv?
func on_arkiv(o: Dictionary) -> bool:
	return str(o.by) == "sponsored" and _arkiv.has(str(int(o.card.get("id", -1))))
