class_name TownPassGate
extends Control
## The Town Pass at the gangway, as on the design board (ux05, scaled from 1440x810 to the 1280x720 canvas): in the film, not a
## website. The bars are down, a pill at the top says what the gate wants, your ferry ticket is in your hand with its stamp space
## waiting, and World ID's own panel sits over the shot with a code to scan with the World App on your phone. Nothing opens in a
## browser: the server's one-time link comes back drawn as that code (TownPass's qr). A rehearsal town stamps a rehearsal pass with E.
## Esc is "later": the gate opens anyway and your pay waits, held, until the pass is stamped (at the town hall's desk, or the phone).
## Asked for once at sign-up (wanted), and again when someone who left before finishing comes back.

signal through(stamped: bool)    # the gate is open: with the pass, or later

const BAR := 79.0
const TICKET_AT := Vector2(80, 267)
const TICKET_W := 356.0
const PANEL_RIGHT := 98.0
const PANEL_TOP := 133.0
const PANEL_W := 338.0
const QR := 174.0
const INK := Color("262727")
const GREY := Color("5d5e5e")
const STAMP := Color("9d9477")
const MUTED := Color(0, 0, 0, 0.5)
const WORLD_APP := "https://world.org/download"

var client: TownClient
var desk: TownPassDesk
var _stamped := false
var _key_up := false             # E let go since it opened: the press that stamps is a new one
var _name := Label.new()
var _day := Label.new()
var _stamp := Label.new()
var _stamp_look := StyleBoxFlat.new()
var _qr := Control.new()
var _status := Label.new()
var _unlocks := Label.new()
var _panel := PanelContainer.new()
var _ticket := PanelContainer.new()

## Should this player be held at the gangway?
static func wanted(c: TownClient) -> bool:
	return c.town_pass and not c.you.is_empty() and not bool(c.you.get("human", false))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	visible = false
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top: bar.offset_bottom = BAR
		else: bar.offset_top = -BAR
		add_child(bar)
	add_child(_what_it_wants())
	add_child(_build_ticket())
	var under := GameHud.on_scene(Label.new(), Brand.FONT_BODY, 12)
	under.text = "Your name, inked as you typed it. The stamp space waits."
	under.position = Vector2(124, 524)
	add_child(under)
	add_child(_build_panel())
	add_child(_build_buttons())
	client.you_changed.connect(_refresh)
	client.synced.connect(_refresh)
	client.event.connect(_on_event)
	desk.waiting_changed.connect(func(_w): _refresh())

## The island's one line, over the bars: a gold diamond and what the gate wants.
func _what_it_wants() -> Control:
	var pill := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_expand_margin_all(3)
	look.set_corner_radius_all(99)
	look.content_margin_left = 16
	look.content_margin_right = 16
	look.content_margin_top = 9
	look.content_margin_bottom = 9
	pill.add_theme_stylebox_override("panel", look)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	var diamond := Control.new()
	diamond.custom_minimum_size = Vector2(16, 16)
	diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diamond.draw.connect(func():
		var pts := PackedVector2Array([Vector2(8, 1), Vector2(15, 8), Vector2(8, 15), Vector2(1, 8)])
		diamond.draw_colored_polygon(pts, Color("F0C33A"))
		pts.append(pts[0])
		diamond.draw_polyline(pts, INK, 1.5, true))
	row.add_child(diamond)
	var words := Label.new()
	words.text = "The gate wants to see you’re one person"
	words.add_theme_font_override("font", Brand.FONT_BODY)
	words.add_theme_font_size_override("font_size", 13)
	words.add_theme_color_override("font_color", Brand.CREAM)
	row.add_child(words)
	pill.add_child(row)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.offset_top = 20
	return pill

## The ferry ticket in your hand: the ferry, your name inked, the day, and the dashed space the stamp lands in.
func _build_ticket() -> Control:
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.CREAM
	look.set_corner_radius_all(4)
	look.content_margin_left = 21
	look.content_margin_right = 21
	look.content_margin_top = 20
	look.content_margin_bottom = 21
	look.shadow_color = Color(0, 0, 0, 0.55)
	look.shadow_size = 30
	look.shadow_offset = Vector2(0, 23)
	_ticket.add_theme_stylebox_override("panel", look)
	_ticket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticket.position = TICKET_AT
	_ticket.custom_minimum_size.x = TICKET_W
	_ticket.rotation_degrees = -4.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_child(_small("DHANIVERSE FERRY", 10, GREY, 0.16))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_small("ONE WAY", 10, GREY, 0.16))
	column.add_child(head)
	var passenger := _small("PASSENGER", 9, GREY, 0.14)
	passenger.custom_minimum_size.y = 34
	passenger.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	column.add_child(passenger)
	_name.add_theme_font_override("font", Brand.FONT_EDITORIAL_ITALIC)
	_name.add_theme_font_size_override("font_size", 36)
	_name.add_theme_color_override("font_color", INK)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = INK
	line.border_width_bottom = 2
	line.content_margin_bottom = 5
	_name.add_theme_stylebox_override("normal", line)
	column.add_child(_name)
	var foot := HBoxContainer.new()
	foot.custom_minimum_size.y = 46
	_day.add_theme_font_override("font", Brand.FONT_BODY)
	_day.add_theme_font_size_override("font_size", 11)
	_day.add_theme_color_override("font_color", GREY)
	_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_day)
	_stamp.text = "TOWN PASS"
	_stamp.add_theme_font_override("font", Brand.FONT_DISPLAY)
	_stamp.add_theme_font_size_override("font_size", 9)
	_stamp.add_theme_color_override("font_color", STAMP)
	_stamp_look.bg_color = Color(0, 0, 0, 0)
	_stamp_look.border_color = STAMP
	_stamp_look.set_border_width_all(2)
	_stamp_look.set_corner_radius_all(6)
	_stamp_look.content_margin_left = 9
	_stamp_look.content_margin_right = 9
	_stamp_look.content_margin_top = 4
	_stamp_look.content_margin_bottom = 4
	_stamp.add_theme_stylebox_override("normal", _stamp_look)
	_stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stamp.rotation_degrees = -4.0
	_stamp.draw.connect(_dash_stamp)
	foot.add_child(_stamp)
	column.add_child(foot)
	_ticket.add_child(column)
	var hole := Control.new()       # the punch hole on the right edge
	hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hole.draw.connect(func(): hole.draw_circle(Vector2.ZERO, 12.5, Color.BLACK))
	_ticket.add_child(hole)
	_ticket.resized.connect(func(): hole.position = Vector2(_ticket.size.x, 48))
	return _ticket

## The stamp space's dashed edge, until the stamp lands and fills it.
func _dash_stamp() -> void:
	if _stamped: return
	var r := Rect2(Vector2.ZERO, _stamp.size)
	for side in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		_stamp.draw_dashed_line(side[0], side[1], STAMP, 2.0, 5.0)

static func _small(text: String, px: int, colour: Color, spacing: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", PaperSheet.spaced(Brand.FONT_BODY, px, spacing))
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", colour)
	return label

## World ID's panel, in its own light look: the code to scan, what's happening, and what the pass unlocks.
func _build_panel() -> Control:
	var look := StyleBoxFlat.new()
	look.bg_color = Color.WHITE
	look.set_corner_radius_all(25)
	look.set_content_margin_all(21)
	look.shadow_color = Color(0, 0, 0, 0.5)
	look.shadow_size = 40
	look.shadow_offset = Vector2(0, 27)
	_panel.add_theme_stylebox_override("panel", look)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -PANEL_RIGHT
	_panel.offset_top = PANEL_TOP
	_panel.custom_minimum_size.x = PANEL_W
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Verify with World ID"
	title.add_theme_font_override("font", Brand.FONT_BODY)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color.BLACK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var kit := Label.new()
	kit.text = "IDKit"
	kit.add_theme_font_override("font", PhonePage.FONT_REGULAR)
	kit.add_theme_font_size_override("font_size", 11)
	kit.add_theme_color_override("font_color", MUTED)
	head.add_child(kit)
	column.add_child(head)
	var gap := Control.new()
	gap.custom_minimum_size.y = 16
	column.add_child(gap)
	_qr.custom_minimum_size = Vector2(QR, QR)
	_qr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_qr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qr.draw.connect(_draw_qr)
	column.add_child(_qr)
	_status.add_theme_font_override("font", PhonePage.FONT_REGULAR)
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PANEL_W - 42.0, 30)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_status)
	var note := PanelContainer.new()
	var note_look := StyleBoxFlat.new()
	note_look.bg_color = Color("FAFAF8")
	note_look.set_corner_radius_all(14)
	note_look.content_margin_left = 12
	note_look.content_margin_right = 12
	note_look.content_margin_top = 11
	note_look.content_margin_bottom = 11
	note.add_theme_stylebox_override("panel", note_look)
	_unlocks.add_theme_font_override("font", PhonePage.FONT_REGULAR)
	_unlocks.add_theme_font_size_override("font_size", 11)
	_unlocks.add_theme_color_override("font_color", Color(0, 0, 0, 0.7))
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unlocks.custom_minimum_size.x = PANEL_W - 66.0
	note.add_child(_unlocks)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 6
	column.add_child(gap2)
	column.add_child(note)
	_panel.add_child(column)
	return _panel

## The code, module by module, on its soft grey card; on a rehearsal town, the key that stamps one instead.
func _draw_qr() -> void:
	var card := StyleBoxFlat.new()
	card.bg_color = Color("F4F4F2")
	card.set_corner_radius_all(16)
	_qr.draw_style_box(card, Rect2(Vector2.ZERO, _qr.size))
	var rows: Array = desk.qr
	if client.debug or rows.is_empty():
		var font: Font = Brand.FONT_DISPLAY
		var word := "E" if client.debug else "…"
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		_qr.draw_string(font, Vector2((QR - w) * 0.5, QR * 0.5 + 14.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, INK)
		return
	var n := rows.size()
	var cell := (QR - 24.0) / n
	for y in n:
		var row := str(rows[y])
		for x in row.length():
			if row[x] == "1": _qr.draw_rect(Rect2(12.0 + x * cell, 12.0 + y * cell, cell + 0.3, cell + 0.3), INK)

func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -PANEL_RIGHT
	row.offset_top = 544
	var w := (PANEL_W - 18.0) / 3.0 - 12.0
	var get_app := GlassButton.new("world app ↗", "", w)
	get_app.pressed.connect(func(): OS.shell_open(WORLD_APP))     # only on a click: the game never opens a page by itself
	# The same pass page the code leads to, opened on this computer: for World ID's simulator (a staging town), or a town on
	# this machine, whose address a phone can't reach.
	var here := GlassButton.new("open here ↗", "", w)
	here.pressed.connect(func(): if desk.url != "": OS.shell_open(desk.url))
	var later := GlassButton.new("later", "ESC", w)
	later.pressed.connect(_later)
	row.add_child(get_app)
	row.add_child(here)
	row.add_child(later)
	return row

func open() -> void:
	if visible: return
	_stamped = false
	_key_up = false
	_stamp_look.bg_color = Color(0, 0, 0, 0)
	_stamp.add_theme_color_override("font_color", STAMP)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not client.debug and desk.qr.is_empty(): desk.ask()
	_refresh()

func is_open() -> bool:
	return visible

func _refresh() -> void:
	if not visible: return
	var you := client.you
	if bool(you.get("human", false)):
		_stamp_lands()
		return
	_name.text = str(you.get("name", client.player))
	_day.text = "day %d · dawn" % int(client.city.get("day", 1))
	_unlocks.text = "Unlocks real pay in USDC. It tells the town you’re one person, never who."
	if you.get("wallet") == null: _status.text = "Your wallet is being made on the chain…"
	elif client.debug: _status.text = "A rehearsal town: press E to stamp a rehearsal pass"
	elif desk.qr.is_empty(): _status.text = "Asking the town hall for your code…"
	else: _status.text = "Scan with World App · waiting for your phone"
	_qr.queue_redraw()

func _process(_delta: float) -> void:
	if visible and not Input.is_action_pressed("interact"): _key_up = true

func _input(e: InputEvent) -> void:
	if not visible or _stamped or not e is InputEventKey or not e.pressed or e.echo: return
	if e.keycode == KEY_ESCAPE:
		_later()
	elif e.is_action_pressed("interact") and _key_up and client.debug and client.you.get("wallet") != null:
		client.rehearse({"type": "PassTown"})
		_status.text = "Stamping…"
	else:
		return
	get_viewport().set_input_as_handled()

func _on_event(e: Dictionary) -> void:
	if e.get("type") == "HumanVerified" and str(e.get("account", "")) == client.player: _stamp_lands()

## Verified: the stamp lands in its space, green and solid, and the gate opens.
func _stamp_lands() -> void:
	if not visible or _stamped: return
	_stamped = true
	_stamp_look.bg_color = Brand.GREEN
	_stamp_look.border_color = Brand.GREEN
	_stamp.text = "TOWN PASS ✓"
	_stamp.add_theme_color_override("font_color", Brand.CREAM)
	_stamp.pivot_offset = _stamp.size * 0.5
	_status.text = "You’re one person. Welcome ashore."
	var t := create_tween()
	if HudMotion.on:
		_stamp.scale = Vector2.ONE * 1.6
		t.tween_property(_stamp, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.1)
	t.tween_callback(_close.bind(true))

## Later: the gate opens anyway, and what the town owes you waits, held, until the pass is stamped.
func _later() -> void:
	_close(false)

func _close(stamped: bool) -> void:
	if not visible: return
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): visible = false)
	through.emit(stamped)
