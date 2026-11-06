class_name DoorChest
extends Node3D
## Your chest, at your door in the Homes' courtyard, and beside it the weekly strongbox with a notch for each day you came this week. The
## daily chest is ready once a day: wood, brass at a 3-day streak, gold at 7 (city.town_goal reached makes it one better). It glows when
## it's ready; the key opens it (OpenChest), the lid swings up when the server says what was in it (ChestOpened), and the contents are
## held up: energy, tickets, maybe a meal voucher, maybe a golden drop of USDC. Every tenth chest without one has one. All the server's.

const TIER_COLOURS := {"wood": Color("a26a3f"), "brass": Color("c9a24a"), "gold": Color("F0C33A")}
const TIER_WORDS := {"wood": "Wooden chest", "brass": "Brass chest", "gold": "Golden chest"}
const LID_OPEN := -1.9             # radians
const WEEKLY_AT := Vector3(1.05, 0.0, 0.1)   # the strongbox, beside the chest
const NOTCHES := 7

var client: TownClient
var player: CharacterBody3D
var sound: Sound
var tell := Callable()             # says a line to the player, on the scene (Cinema.say)
var sheet := BoardSheet.new(600.0, "Lovely")
var _body: MeshInstance3D
var _lid: Node3D
var _lid_mesh: MeshInstance3D
var tier_mat := StandardMaterial3D.new()   # the chest's wood or metal: its own copy in the town's look (tier_look) once painted
var tier_look: Material
var _glow: OmniLight3D
var _weekly: Node3D
var _weekly_lid: Node3D
var _notches: Array[MeshInstance3D] = []
var _label: Label3D
var _t := 0.0
var _opening := false

func setup(ui: Control) -> void:
	_build()
	sheet.player = player
	ui.add_child(sheet)
	sheet.chosen.connect(func(_i): sheet.close())
	client.event.connect(_on_event)
	client.refused.connect(func(command: Dictionary, refusal: Dictionary):
		if command.get("type") == "OpenChest" and tell.is_valid(): tell.call(Refusals.say(refusal, client.now_ms())))

func _build() -> void:
	tier_mat.roughness = 0.55
	tier_mat.albedo_color = Color("a36b41")
	tier_mat.set_meta("own", true)
	var band := StandardMaterial3D.new()
	band.albedo_color = Color("3b3a3a")
	band.metallic = 0.6
	_body = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.42, 0.52)
	_body.mesh = bm
	_body.material_override = tier_mat
	_body.position.y = 0.21
	add_child(_body)
	for x in [-0.28, 0.28]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.06, 0.44, 0.54)
		strap.mesh = sm
		strap.material_override = band
		strap.position = Vector3(x, 0.21, 0)
		add_child(strap)
	_lid = Node3D.new()                  # hinged at the back edge
	_lid.position = Vector3(0, 0.42, -0.26)
	add_child(_lid)
	_lid_mesh = MeshInstance3D.new()
	var lm := CylinderMesh.new()       # a rounded lid: half a cylinder, lying along x
	lm.top_radius = 0.26
	lm.bottom_radius = 0.26
	lm.height = 0.8
	lm.radial_segments = 16
	_lid_mesh.mesh = lm
	_lid_mesh.material_override = tier_mat
	_lid_mesh.rotation.z = PI * 0.5
	_lid_mesh.scale = Vector3(1.0, 1.0, 0.42)
	_lid_mesh.position = Vector3(0, 0.0, 0.26)
	_lid.add_child(_lid_mesh)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("ffd27a")
	_glow.omni_range = 2.2
	_glow.light_energy = 0.0
	_glow.position = Vector3(0, 0.7, 0.1)
	add_child(_glow)
	_weekly = Node3D.new()
	_weekly.position = WEEKLY_AT
	add_child(_weekly)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("4a4f55")
	iron.metallic = 0.5
	iron.roughness = 0.45
	var wb := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = Vector3(0.5, 0.32, 0.38)
	wb.mesh = wbm
	wb.material_override = iron
	wb.position.y = 0.16
	_weekly.add_child(wb)
	_weekly_lid = Node3D.new()
	_weekly_lid.position = Vector3(0, 0.32, -0.19)
	_weekly.add_child(_weekly_lid)
	var wl := MeshInstance3D.new()
	var wlm := BoxMesh.new()
	wlm.size = Vector3(0.52, 0.06, 0.4)
	wl.mesh = wlm
	wl.material_override = iron
	wl.position = Vector3(0, 0.03, 0.19)
	_weekly_lid.add_child(wl)
	for i in NOTCHES:                  # a notch for each day this week
		var n := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.035, 0.12, 0.01)
		n.mesh = nm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		n.material_override = m
		n.position = Vector3(-0.18 + i * 0.06, 0.17, 0.195)
		_weekly.add_child(n)
		_notches.append(n)
	_label = Label3D.new()
	_label.font = Brand.FONT_BODY
	_label.font_size = 40
	_label.pixel_size = 0.002
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.6)
	_label.modulate = Brand.CREAM
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.5, 1.15, 0)
	_label.visibility_range_end = 14.0
	add_child(_label)

func _process(delta: float) -> void:
	_t += delta
	var you := client.you
	if you.is_empty(): return
	var now := client.now_ms()
	var chest: Dictionary = you.get("chest", {})
	var tier := str(chest.get("tier", "wood"))
	if tier_look is ShaderMaterial:
		(tier_look as ShaderMaterial).set_shader_parameter("albedo", TIER_COLOURS.get(tier, TIER_COLOURS.wood))
		(tier_look as ShaderMaterial).set_shader_parameter("metal", 0.7 if tier != "wood" else 0.0)
		(tier_look as ShaderMaterial).set_shader_parameter("rough", 0.35 if tier != "wood" else 0.7)
	var ready := TownState.chest_ready(you, now)
	if not _opening:
		_glow.light_energy = (0.8 + 0.4 * sin(_t * 3.0)) if ready else 0.0
		_lid.rotation.x = 0.0 if not ready else -0.05 - 0.04 * (0.5 + 0.5 * sin(_t * 4.0))
	var streak: Dictionary = you.get("streak", {})
	var days := int(streak.get("week_days", 0))
	var need := int(streak.get("need", 5))
	for i in NOTCHES:
		(_notches[i].material_override as StandardMaterial3D).albedo_color = Color("F0C33A") if i < days else (Color("8a8f95") if i < need else Color("2a2d30"))
	var weekly := TownState.weekly_ready(you, now)
	_weekly_lid.rotation.x = -0.06 - 0.05 * (0.5 + 0.5 * sin(_t * 4.0)) if weekly else 0.0
	var left := TownState.left_ms(chest.get("ready_at"), now)
	_label.text = ("%s · ready" % TIER_WORDS.get(tier, "Chest")) if ready else "%s · %s" % [TIER_WORDS.get(tier, "Chest"), TownState.clock(left)]

func hint() -> String:
	if client.you.is_empty(): return ""
	var now := client.now_ms()
	if TownState.chest_ready(client.you, now): return "Open your %s" % str(TIER_WORDS.get(str(client.you.chest.get("tier", "wood")), "chest")).to_lower()
	return "Your chest: ready again %s" % TownState.soon(TownState.left_ms(client.you.get("chest", {}).get("ready_at"), now))

func weekly_hint() -> String:
	if client.you.is_empty(): return ""
	var streak: Dictionary = client.you.get("streak", {})
	if TownState.weekly_ready(client.you, client.now_ms()): return "Open the weekly strongbox"
	return "Weekly strongbox: %d of %d days this week" % [int(streak.get("week_days", 0)), int(streak.get("need", 5))]

func open_daily() -> void:
	client.send({"type": "OpenChest"})

func open_weekly() -> void:
	client.send({"type": "OpenChest", "weekly": true})

func _on_event(e: Dictionary) -> void:
	if e.type != "ChestOpened" or str(e.get("account", "")) != client.player: return
	_open(e)

## The lid swings up, light spills out, and what was inside is held up.
func _open(e: Dictionary) -> void:
	_opening = true
	var lid := _weekly_lid if bool(e.get("weekly", false)) else _lid
	if sound: sound.play("paper")
	var t := create_tween()
	t.tween_property(lid, "rotation:x", LID_OPEN, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_glow, "light_energy", 4.0, 0.3)
	t.tween_interval(0.5)
	t.tween_callback(func(): _show_contents(e))
	t.tween_interval(1.4)
	t.tween_property(lid, "rotation:x", 0.0, 0.6).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(_glow, "light_energy", 0.0, 0.6)
	t.tween_callback(func(): _opening = false)

func _show_contents(e: Dictionary) -> void:
	var c: Dictionary = e.get("contents", {})
	var weekly := bool(e.get("weekly", false))
	var tier := str(e.get("tier", "wood"))
	var rows := []
	var drop := int(c.get("golden_drop", 0))
	if drop > 0:
		rows.append({"title": "A golden drop", "sub": "USDC from the town's surprise pool" + ("" if bool(client.you.get("human", false)) else ". Held for you until you get your Town Pass"), "figure": Usdc.text(drop)})
	if int(c.get("energy", 0)) > 0: rows.append({"title": "Energy", "sub": "straight into you", "figure": "+%d" % int(c.energy)})
	if int(c.get("tickets", 0)) > 0: rows.append({"title": "Tickets", "sub": "for this week's draw", "figure": "+%d" % int(c.tickets)})
	if bool(c.get("voucher", false)): rows.append({"title": "A meal voucher", "sub": "a thali on the town, at the Common Table", "figure": "+1"})
	if c.has("usdc") and int(c.usdc) > 0: rows.append({"title": "Your streak bonus", "sub": "USDC for coming back", "figure": Usdc.text(int(c.usdc))})
	var chest: Dictionary = client.you.get("chest", {})
	var pity := "%d of %d chests since your last golden drop: the %dth always has one." % [int(chest.get("pity", 0)), int(chest.get("pity_every", 10)), int(chest.get("pity_every", 10))]
	sheet.set_words("Your door · the Homes" if not weekly else "Your door · the weekly strongbox", ("The weekly strongbox" if weekly else str(TIER_WORDS.get(tier, "Your chest"))) + (", opened." if not weekly else ", opened."), "" if weekly else pity)
	sheet.set_rows(rows)
	sheet.set_go("Lovely")
	sheet.open()
