class_name QuestMarks
extends Node3D
## Where your quests send you. Every open step that happens somewhere (PROTOCOL.md: a step's `place`, a place or a person) and that the
## client reports itself (talk, visit, paper, cargo, strongbox) can be done there with the interact key. Grandma's Ledger is different:
## its pages lie torn on the ground where the server says, and her strongbox waits at your door. The one gold marker, for the quest
## you're tracking, is the Guide's. What a step needs beyond walking there (the swap, the delivery, the sign, the Town Pass) is done at
## its own thing in town (Tallyport).

const SPIN := 1.6                  # radians a second
const BOB := 0.12                  # m
const OVER := 2.5                  # m over the spot: the marker
const OVER_PERSON := 2.75          # m over a person's feet: over their head and name
const GOLD := Color("F0C33A")
const PAGE := Color("f3ead2")

var town: Tallyport
var client: TownClient
var _marks := {}                   # place -> {node, thing}
var _said := ""                    # what the marks were built for
var _box: Node3D                   # Grandma's strongbox, at your door while her quest is on
var _pages := {}                   # step id -> a torn page on the ground, for each of Grandma's pages still to find

func _ready() -> void:
	client.you_changed.connect(_rebuild)
	client.synced.connect(_rebuild)
	client.event.connect(_on_event)

## What's open, by place: [[quest, step], ...]. The marks are only rebuilt when that changes.
func _rebuild() -> void:
	var by_place := {}
	for q in client.you.get("quests", []):
		for s in TownState.open_steps(q):
			if TownState.done_by(s) == "" and str(q.quest) != "grandma": continue    # the chain or the server counts it: nowhere to go
			var place := str(s.get("place", ""))
			if place == "" or not town.knows(place): continue
			if not by_place.has(place): by_place[place] = []
			by_place[place].append([q, s])
	var said := JSON.stringify(by_place.keys()) + JSON.stringify(by_place.values().map(func(v): return v.map(func(p): return "%s/%s/%s" % [p[0].quest, p[1].id, p[1].get("waiting", false)])))
	if said != _said:
		_said = said
		for place in _marks.keys():
			if not by_place.has(place): _drop(place)
		for place in by_place:
			if not _marks.has(place): _marks[place] = _make(place)
	for place in _marks: _marks[place].open = by_place.get(place, [])
	_lay_pages()

## Grandma's pages still to find, each lying where the server says it is.
func _lay_pages() -> void:
	var want := {}
	var q := TownState.quest(client.you, "grandma")
	for s in q.get("steps", []):
		if bool(s.get("done", false)) or str(s.get("kind", "")) == "strongbox" or not town.knows(str(s.get("place", ""))): continue
		want[str(s.id)] = str(s.place)
	for id in _pages.keys():
		if not want.has(id):
			(_pages[id] as Node3D).queue_free()
			_pages.erase(id)
	for id in want:
		if _pages.has(id): continue
		var page := page_mesh()
		add_child(page)
		town.paint(page.get_parent())
		var at := town.place_at(want[id])
		page.global_position = at + Vector3(0.9, 0.02, 0.6)
		page.rotation.y = randf() * TAU
		_pages[id] = page

func _make(place: String) -> Dictionary:
	var m := {"place": place, "open": []}
	m.thing = town.things.add({"at": func(): return town.place_at(place), "reach": 2.6, "priority": 1,
		"over": OVER_PERSON + 0.35 if town.is_person(place) else 1.6,
		"hint": func(): return _hint(m), "press": func(): _press(m)})
	return m

func _drop(place: String) -> void:
	var m: Dictionary = _marks[place]
	town.things.remove(m.thing)
	_marks.erase(place)

## The first of the open steps here that the client can report: its words on the hint.
func _doable(m: Dictionary) -> Array:
	for p in m.open:
		if TownState.done_by(p[1]) == "step": return p
	return []

func _hint(m: Dictionary) -> String:
	var p := _doable(m)
	if p.is_empty():
		for o in m.open:
			if str(o[1].get("kind", "")) == "meals": return "Grandma's page: three meals you pay for"
		return ""
	if bool(p[1].get("waiting", false)): return "Waiting for the chain…"
	return step_words(p[1])

func _press(m: Dictionary) -> void:
	var p := _doable(m)
	if p.is_empty():
		for o in m.open:
			if str(o[1].get("kind", "")) == "meals": town.cinema.say("This page fills in by itself: eat three meals you pay for yourself, after taking the quest.", 5.0)
		return
	if bool(p[1].get("waiting", false)): return
	if town.is_person(m.place): town.greet(m.place)
	client.send({"type": "QuestStep", "quest": str(p[0].quest), "step": str(p[1].id)})

## A step's text, short enough for a hint: its first sentence, whole words, about 40 letters.
static func step_words(step: Dictionary) -> String:
	var t := str(step.get("text", "")).strip_edges()
	var dot := t.find(". ")
	if dot > 0: t = t.left(dot)
	t = t.trim_suffix(".")
	if t.length() <= 44: return t
	var out := ""
	for w in t.split(" ", false):
		if (out + " " + w).length() > 42: break
		out = w if out == "" else out + " " + w
	return out + "…"

func _process(_delta: float) -> void:
	_strongbox()
	_fan()

## A gold diamond: an octahedron, lit from inside so it reads at dusk.
static func diamond() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.5
	s.radial_segments = 4
	s.rings = 1
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = GOLD
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## A torn page, lying where Grandma hid it.
static func page_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.24, 0.006, 0.32)
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = PAGE
	m.emission_enabled = true
	m.emission = PAGE
	m.emission_energy_multiplier = 0.25
	mi.material_override = m
	return mi

## Grandma's strongbox stands at your door while her quest is on, and opens when every page is found.
func _strongbox() -> void:
	var q := TownState.quest(client.you, "grandma")
	var want := not q.is_empty()
	if want == (_box != null): return
	if not want:
		_box.queue_free()
		_box = null
		return
	_box = Node3D.new()
	add_child(_box)
	var body := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.7, 0.45, 0.45)
	body.mesh = b
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("4a4f55")
	steel.metallic = 0.6
	steel.roughness = 0.4
	body.material_override = steel
	body.position.y = 0.225
	_box.add_child(body)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.72, 0.06, 0.47)
	band.mesh = bb
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("c9a24a")
	brass.metallic = 0.8
	band.material_override = brass
	band.position.y = 0.38
	_box.add_child(band)
	_box.global_position = town.place_at("strongbox")
	town.paint(_box)
	for i in 3:                    # the pages, in a fan on its lid, as they're found
		var page := page_mesh()
		page.name = "Page%d" % i
		page.position = Vector3(-0.2 + i * 0.2, 0.46 + i * 0.004, 0.0)
		page.rotation.y = -0.3 + i * 0.3
		_box.add_child(page)

## The pages found so far lie on the lid.
func _fan() -> void:
	if _box == null: return
	var q := TownState.quest(client.you, "grandma")
	var found := 0
	for s in q.get("steps", []):
		if bool(s.get("done", false)) and str(s.get("kind", "")) != "strongbox": found += 1
	for i in 3: (_box.get_node("Page%d" % i) as Node3D).visible = i < found

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	if e.type == "QuestStepDone" and str(e.get("quest", "")) == "grandma" and _box:
		town.sound_play("paper")
