extends CanvasLayer
## The tester's panel (F1): every feature within reach in minutes rather than real days. On a rehearsal server (snapshot.debug) it
## sends the server's rehearsal actions (PROTOCOL.md): Skip moves the city's clock on, Fund is a faucet of rehearsal USDC, FundBucket fills
## one of the house's pools, Town Pass stands in for World ID, Ready chest readies your chest, New campaign opens a sponsor's quest, and
## Next season starts the next one. Everywhere it sets the time of day and walks the player straight to any place. Testing only: it says
## so on its face.

var world: Node
var client: TownClient             # none in the Old Quarter, which has no server
var _box: VBoxContainer
var _root: PanelContainer
var _said := ""                    # the server's word on the last rehearsal that couldn't be done

func _ready() -> void:
	layer = 20
	_root = PanelContainer.new()
	# the HUD's sticker look (scripts/ui/hud.gd): white, charcoal outline, hard shadow, bold monospace
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	sb.border_color = Color("46434d")
	sb.set_border_width_all(3)
	sb.shadow_color = Color("46434d")
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(5, 5)
	_root.add_theme_stylebox_override("panel", sb)
	var th := Theme.new()
	th.default_font = preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
	th.default_font_size = 13
	var btn := sb.duplicate()
	btn.set_corner_radius_all(9)
	btn.set_content_margin_all(6)
	btn.set_border_width_all(2)
	btn.shadow_offset = Vector2(3, 3)
	th.set_stylebox("normal", "Button", btn)
	var hov: StyleBoxFlat = btn.duplicate()
	hov.shadow_offset = Vector2(4, 4)
	th.set_stylebox("hover", "Button", hov)
	var prs: StyleBoxFlat = btn.duplicate()
	prs.shadow_offset = Vector2(1, 1)
	th.set_stylebox("pressed", "Button", prs)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]: th.set_color(k, "Button", Color("2b2a30"))
	th.set_color("font_color", "Label", Color("2b2a30"))
	_root.theme = th
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -330
	_root.offset_right = -14
	_root.offset_top = 70
	_root.visible = false
	if client:
		client.city_changed.connect(func(): if _root.visible: _build())
		client.server_said.connect(func(m: String):
			_said = m
			if _root.visible: _build())
	add_child(_root)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	_build()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F1:
		_root.visible = not _root.visible
		if _root.visible: _build()
		get_viewport().set_input_as_handled()

func _title(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color("b07a12"))
	l.add_theme_font_size_override("font_size", 14)
	_box.add_child(l)

func _row(buttons: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(func(): b[1].call(); _build())
		h.add_child(btn)
	_box.add_child(h)

func _build() -> void:
	for c in _box.get_children(): c.queue_free()
	var head := Label.new()
	head.text = "TEST PANEL  ·  F1"
	head.add_theme_color_override("font_color", Color("2b2a30"))
	_box.add_child(head)
	if client:
		var st := Label.new()
		st.add_theme_font_size_override("font_size", 12)
		st.add_theme_color_override("font_color", Color("8a8692"))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.text = "day %d  ·  energy %d  ·  %s  ·  %s" % [int(client.city.get("day", 0)), int(client.you.get("energy", 0)), Usdc.text(int(client.you.get("usdc", 0)) if client.you.get("usdc") != null else 0), client.city.get("chain", "?")] 			if client.debug else "Not a rehearsal server: start it with --debug for the rehearsal actions."
		_box.add_child(st)
		if _said != "":
			var said := Label.new()
			said.text = _said
			said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			said.add_theme_font_size_override("font_size", 12)
			said.add_theme_color_override("font_color", Color("c44d00"))
			_box.add_child(said)
	if client and client.debug:
		var day := int(client.city.get("day_ms", 3600000))
		_title("Time (the server's clock)")
		_row([["+1 h", func(): _rehearse({"type": "Skip", "ms": 3600000})], ["+1 day", func(): _rehearse({"type": "Skip", "ms": day})], ["+7 days", func(): _rehearse({"type": "Skip", "ms": day * 7})]])
		_row([["Next season", func(): _rehearse({"type": "NextSeason"})]])
		_title("Money (rehearsal USDC)")
		_row([["+1 USDC", func(): _rehearse({"type": "Fund", "usdc": 1000000})], ["+0.01", func(): _rehearse({"type": "Fund", "usdc": 10000})], ["Town Pass", func(): _rehearse({"type": "PassTown"})]])
		_row([["Fill fixed", func(): _rehearse({"type": "FundBucket", "bucket": "fixed", "usdc": 5000000})], ["surprise", func(): _rehearse({"type": "FundBucket", "bucket": "surprise", "usdc": 5000000})], ["safety", func(): _rehearse({"type": "FundBucket", "bucket": "safety", "usdc": 5000000})]])
		_title("Chests and quests")
		_row([["Ready chest", func(): _rehearse({"type": "ReadyChest"})], ["+1 real day", func(): _rehearse({"type": "Skip", "ms": int(client.city.get("real_day_ms", 86400000))})]])
		_row([["Spice Run", func(): _campaign("spice_run", 1000000, 30)], ["Sign", func(): _campaign("paint_sign", 250000, 20)]])
		_row([["Town Pass q.", func(): _campaign("town_pass", 200000, 0)], ["Hold", func(): _campaign("hold_line", 500000, 20)]])
	if world and world.has_method("set_time_mode"):
		_title("Sky")
		_row([["Day", func(): world.set_time_mode("day")], ["Evening", func(): world.set_time_mode("evening")], ["Night", func(): world.set_time_mode("night")]])
		if world.has_method("cycle_season"):
			_row([["Next season", func(): world.cycle_season()], ["Next weather", func(): world.cycle_weather()]])
	if world and "sites" in world and not world.sites.is_empty():
		_title("Go to")
		var row: Array = []
		for site in world.sites:
			row.append([str(site.def.get("name", site.name)), func(): _go(site.door)])
			if row.size() == 2:
				_row(row)
				row = []
		if row.size() > 0: _row(row)

## A rehearsal action; what it changes comes back as the server's own events, `you` and `city`. One that couldn't be done is said here.
func _rehearse(action: Dictionary) -> void:
	_said = ""
	client.rehearse(action)

## A sponsor's campaign, as the console would open it: refused like the escrow refuses one that breaks its rules.
func _campaign(template: String, payout: int, energy: int) -> void:
	_rehearse({"type": "NewCampaign", "template": template, "payout": payout, "energy": energy, "slots": 10, "boosted": false})

func _go(p: Vector3) -> void:
	if world and world.player:
		world.player.global_position = p + Vector3(0, 0.5, 0)
		world.player.velocity = Vector3.ZERO
