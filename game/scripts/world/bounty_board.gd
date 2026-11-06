class_name BountyBoard
extends Node3D
## The Bounty Board in the square: a notice board with a card pinned up for each thing the town will pay you for. Sponsored quests from the
## chain (city.bounty, the live ones), today's errands, today's mystery and Grandma's Ledger. Walk up and press the key, and the board's
## cards are held up to read (BoardSheet): who's paying, what it costs in energy, what it pays in USDC, how many places are left, when it
## ends, and whether its card is also on Arkiv (GET /arkiv/campaigns, when the publisher answers). Enter takes the chosen one.

const SIZE := Vector2(3.4, 1.9)    # the board, m
const FEET := 0.75                 # its bottom edge over the ground
const CARD := Vector2(0.62, 0.78)
const CARDS := 8                   # pinned at once
const PINS := {"sponsored": Color("FF6600"), "errand": Color("0f8f88"), "mystery": Color("E100FF"), "grandma": Color("F0C33A")}
const KIND_WORDS := {"sponsored": "Sponsored", "errand": "Errand", "mystery": "Today's mystery", "grandma": "Once a season"}
const ARKIV_EVERY := 10.0          # s: the server caches it this long anyway

var client: TownClient
var player: CharacterBody3D
var tags: Control
var paint := Callable()            # lights what's built here as the town is lit (Tallyport.paint)
var sheet := BoardSheet.new(820.0, "Take this quest")
var _cards := Node3D.new()
var _said := ""
var _offers: Array = []
var _arkiv := {}                   # campaign id (string) -> its Arkiv card
var _arkiv_source := ""
var _http: HTTPRequest
var _asked_at := -INF

func setup(ui: Control) -> void:
	tags = ui
	_build()
	add_child(_cards)
	sheet.player = player
	ui.add_child(sheet)
	sheet.chosen.connect(_take)
	client.city_changed.connect(_pin_up)
	client.you_changed.connect(_pin_up)
	client.synced.connect(_pin_up)
	client.refused.connect(_on_refused)
	client.replied.connect(_on_replied)
	_http = HTTPRequest.new()
	_http.timeout = 4.0
	add_child(_http)
	_http.request_completed.connect(_on_arkiv)

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Brand.TIMBER
	wood.roughness = 0.8
	var cork := StandardMaterial3D.new()
	cork.albedo_color = Color("6b4a32")
	cork.roughness = 0.95
	for x in [-SIZE.x * 0.5 - 0.06, SIZE.x * 0.5 + 0.06]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, FEET + SIZE.y + 0.5, 0.12)
		post.mesh = pm
		post.material_override = wood
		post.position = Vector3(x, (FEET + SIZE.y + 0.5) * 0.5, 0.0)
		add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE.x, SIZE.y, 0.08)
	board.mesh = bm
	board.material_override = cork
	board.position = Vector3(0, FEET + SIZE.y * 0.5, 0)
	add_child(board)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(SIZE.x + 0.5, 0.1, 0.5)
	roof.mesh = rm
	roof.material_override = wood
	roof.position = Vector3(0, FEET + SIZE.y + 0.42, 0.08)
	add_child(roof)
	var head := Label3D.new()
	head.text = "BOUNTY BOARD"
	head.font = Brand.FONT_DISPLAY
	head.font_size = 96
	head.pixel_size = 0.0032
	head.modulate = Brand.CREAM
	head.outline_size = 0
	head.position = Vector3(0, FEET + SIZE.y + 0.22, 0.06)
	add_child(head)
	var collide := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x + 0.3, FEET + SIZE.y, 0.3)
	cs.shape = box
	cs.position.y = (FEET + SIZE.y) * 0.5
	collide.add_child(cs)
	add_child(collide)

## A card for each offer, pinned up in rows. Rebuilt only when what's on offer changes.
func _pin_up() -> void:
	_offers = TownState.offers(client.you, client.city)
	if sheet.is_open: _fill_sheet()
	var said := JSON.stringify(_offers.map(func(o): return [o.quest, o.pays, o.on, o.card.get("slots_left", 0)]))
	if said == _said: return
	_said = said
	for c in _cards.get_children(): c.queue_free()
	var n := mini(_offers.size(), CARDS)
	var per_row := 4
	for i in n:
		var o: Dictionary = _offers[i]
		var col := i % per_row
		var row := i / per_row
		var at := Vector3(-SIZE.x * 0.5 + 0.47 + col * 0.82, FEET + SIZE.y - 0.5 - row * 0.9, 0.05)
		_cards.add_child(_card(o, at, (i * 0.37) - floorf(i * 0.37) - 0.5))
	if paint.is_valid(): paint.call(_cards)

func _card(o: Dictionary, at: Vector3, tilt: float) -> Node3D:
	var card := Node3D.new()
	card.position = at
	card.rotation.z = tilt * 0.08
	var paper := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = CARD
	paper.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("fffdf6") if not o.on else Color("e7f0dc")
	m.roughness = 1.0
	paper.material_override = m
	card.add_child(paper)
	var pin := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.03
	pm.height = 0.06
	pin.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = PINS.get(o.by, Brand.ORANGE)
	pin.material_override = pmat
	pin.position = Vector3(0, CARD.y * 0.5 - 0.06, 0.02)
	card.add_child(pin)
	var lines := [[str(KIND_WORDS.get(o.by, "")).to_upper(), Brand.FONT_BODY, 22, 0.25], [str(o.title), Brand.FONT_BODY, 34, 0.12],
		[Usdc.text(int(o.pays)) if int(o.pays) >= 0 else "Her strongbox", Brand.FONT_DISPLAY, 36, -0.12], ["%d energy" % int(o.energy), Brand.FONT_BODY, 24, -0.25]]
	for l in lines:
		var t := Label3D.new()
		t.text = l[0]
		t.font = l[1]
		t.font_size = l[2]
		t.pixel_size = 0.0018
		t.modulate = Brand.PLATE
		t.outline_size = 0
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.width = CARD.x / 0.0018 * 0.85
		t.position = Vector3(0, l[3], 0.005)
		t.visibility_range_end = 18.0
		card.add_child(t)
	return card

## The interact key at the board.
func hint() -> String:
	if client.you.is_empty(): return ""
	var n := _offers.size()
	return "Read the Bounty Board" if n > 0 else ""

func open() -> void:
	_ask_arkiv()
	sheet.pick = 0
	_fill_sheet()
	sheet.open()

func _fill_sheet() -> void:
	var now_s := Time.get_unix_time_from_system()
	var rows := []
	for o in _offers:
		var sub := []
		var badge := ""
		match str(o.by):
			"sponsored":
				var c: Dictionary = o.card
				var sponsor := str(c.get("sponsor", ""))
				sub.append("From %s" % (TownState.short_address(sponsor) if sponsor.begins_with("0x") else sponsor))
				sub.append("%d of %d places left" % [int(c.get("slots_left", 0)), int(c.get("slots", 0))])
				var ends := float(c.get("ends", 0)) - now_s
				if ends > 0: sub.append("ends " + TownState.soon(int(ends * 1000.0)))
				if _arkiv.has(str(int(c.get("id", -1)))): badge = "on Arkiv"
			"errand": sub.append("An errand · %d of %d left today" % [int(client.you.get("errands_left", 0)), int(client.city.get("errands", {}).get("per_day", 3))])
			"mystery":
				sub.append("Today's mystery" + (" · a sponsor pays for it" if o.get("boosted_by") != null else ""))
				if int(client.you.get("mystery_left", 1)) <= 0: sub.append("taken today")
			"grandma": sub.append("Once a season · three pages and a strongbox")
		sub.append("costs %d energy" % int(o.energy) if int(o.energy) > 0 else "costs no energy")
		if o.on: badge = "on it"
		rows.append({"title": o.title, "sub": " · ".join(sub), "story": str(o.story),
			"figure": Usdc.text(int(o.pays)) if int(o.pays) >= 0 else "Strongbox", "figure_sub": "pays" if int(o.pays) >= 0 else "USDC and a title",
			"badge": badge, "dim": o.on})
	var source := "Sponsors' quests come from the chain" + (", and their cards are also published on Arkiv." if _arkiv_source != "" else ".")
	var pass_word := "" if bool(client.you.get("human", false)) else " Payouts wait for your Town Pass."
	sheet.set_words("Tally Square · Bounty Board", "Work for the town", "Every quest costs energy and pays in USDC. %s%s You have %d energy." % [source, pass_word, int(client.you.get("energy", 0))])
	sheet.set_rows(rows)
	sheet.set_go("Take this quest" if not rows.is_empty() else "")

func _take(i: int) -> void:
	if i >= _offers.size(): return
	var o: Dictionary = _offers[i]
	if o.on:
		sheet.say("You're on this one: it's in your quest log (phone, Quests).", false)
		return
	client.send({"type": "TakeQuest", "quest": str(o.quest)})
	sheet.say("Taking it…", false)

func _on_replied(command: Dictionary, _reply: Dictionary) -> void:
	if command.get("type") != "TakeQuest" or not sheet.is_open: return
	var q := TownState.quest(client.you, str(command.quest))
	var first := QuestMarks.step_words(TownState.next_step(q)) if not q.is_empty() else ""
	sheet.say("Taken. First: %s. It's on your map and in your quest log." % first if first != "" else "Taken. It's in your quest log.", false)
	get_tree().create_timer(1.6).timeout.connect(sheet.close)

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") != "TakeQuest" or not sheet.is_open: return
	sheet.say(Refusals.say(refusal, client.now_ms()))

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
	if sheet.is_open: _fill_sheet()
