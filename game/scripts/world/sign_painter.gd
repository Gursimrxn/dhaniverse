class_name SignPainter
extends Node3D
## The sign painter by the Market Hall's door, and your shop sign on its post beside him (quests.toml, paint_sign). The sign is written on
## your name as its `description` record (PaintSign), so it needs your name, which comes with the Town Pass. What it says, and the name it
## hangs from, are read back from `you`: it shows your sign as the chain has it.

const LOOK := {"top": "e9b23c", "tee": "e8e2d4", "skin": "a0683f", "hair": "2b2018", "bottom": "4b6ea6", "shoes": "2a2a30", "open_top": true, "apron": true, "apron_colour": "d8d0bc", "tall": 0.96}
const MOST := 80                   # PROTOCOL.md: 1 to 80 characters

var client: TownClient
var player: CharacterBody3D
var tell := Callable()
var painter: TownNpc
var sheet := BoardSheet.new(720.0, "Paint it")
var _board: Node3D
var _text: Label3D
var _name: Label3D
var _field := LineEdit.new()
var _pending := false

func setup(ui: Control, painter_at: Transform3D, board_at: Transform3D) -> void:
	painter = TownNpc.new()
	painter.player = player
	add_child(painter)
	painter.setup("The sign painter", LOOK, ui)
	painter.global_transform = painter_at
	_build(board_at)
	sheet.player = player
	sheet.keys_free = true
	ui.add_child(sheet)
	_field.max_length = MOST
	_field.placeholder_text = "What your sign says"
	_field.add_theme_font_override("font", Brand.FONT_BODY)
	_field.add_theme_font_size_override("font_size", 26)
	_field.add_theme_color_override("font_color", PaperSheet.INK)
	_field.add_theme_color_override("font_placeholder_color", Color("b9ae8e"))
	_field.add_theme_color_override("caret_color", PaperSheet.INK)
	var line := StyleBoxEmpty.new()
	line.content_margin_bottom = 4
	_field.add_theme_stylebox_override("normal", line)
	_field.add_theme_stylebox_override("focus", line)
	_field.draw.connect(func(): _field.draw_dashed_line(Vector2(0, _field.size.y - 1), Vector2(_field.size.x, _field.size.y - 1), Brand.GREEN, 2.0, 6.0))
	_field.text_submitted.connect(func(_t): _paint())
	sheet.extra().add_child(_field)
	sheet.chosen.connect(func(_i): _paint())
	sheet.closed.connect(func(): _field.release_focus())
	client.you_changed.connect(_show_sign)
	client.synced.connect(_show_sign)
	client.event.connect(_on_event)
	client.refused.connect(func(command: Dictionary, refusal: Dictionary):
		if command.get("type") == "PaintSign":
			_pending = false
			if sheet.is_open: sheet.say(Refusals.say(refusal, client.now_ms()))
			elif tell.is_valid(): tell.call(Refusals.say(refusal, client.now_ms())))

func _build(at: Transform3D) -> void:
	_board = Node3D.new()
	add_child(_board)
	_board.global_transform = at
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Brand.TIMBER
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, 2.4, 0.1)
	post.mesh = pm
	post.material_override = wood
	post.position = Vector3(-0.85, 1.2, 0)
	_board.add_child(post)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(1.8, 0.06, 0.06)
	arm.mesh = am
	arm.material_override = wood
	arm.position = Vector3(0.0, 2.35, 0)
	_board.add_child(arm)
	var plank := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.6, 0.05)
	plank.mesh = bm
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("fffdf6")
	plank.material_override = paint
	plank.position = Vector3(0.05, 1.95, 0)
	_board.add_child(plank)
	_text = Label3D.new()
	_text.font = Brand.FONT_EDITORIAL_ITALIC
	_text.font_size = 64
	_text.pixel_size = 0.0028
	_text.modulate = Brand.PLATE
	_text.outline_size = 0
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.width = 1.5 / 0.0028
	_text.position = Vector3(0.05, 2.0, 0.03)
	_board.add_child(_text)
	_name = Label3D.new()
	_name.font = Brand.FONT_BODY
	_name.font_size = 28
	_name.pixel_size = 0.0028
	_name.modulate = Brand.PLATE
	_name.outline_size = 0
	_name.position = Vector3(0.05, 1.74, 0.03)
	_board.add_child(_name)

func board_at() -> Vector3:
	return _board.global_position

func _show_sign() -> void:
	var sign := str(client.you.get("sign", ""))
	var ens = client.you.get("ens")
	_text.text = sign if sign != "" else "Your sign here"
	_text.modulate = Brand.PLATE if sign != "" else Color(Brand.PLATE, 0.35)
	_name.text = str(ens) if ens != null else "no name yet: it comes with the Town Pass"
	if sheet.is_open: _fill()

func _open_sign() -> Array:
	for q in client.you.get("quests", []):
		for s in TownState.open_steps(q):
			if str(s.get("kind", "")) == "sign": return [q, s]
	return []

func sign_hint() -> String:
	if client.you.is_empty(): return ""
	var p := _open_sign()
	if _pending or (not p.is_empty() and bool(p[1].get("waiting", false))): return "The painter is at work…"
	if not p.is_empty(): return "Paint your shop sign"
	return "Repaint your shop sign" if client.you.get("ens") != null else ""

func open() -> void:
	if _pending: return
	_field.text = str(client.you.get("sign", ""))
	sheet.pick = 0
	_fill()
	sheet.open()
	_field.grab_focus()
	_field.caret_column = _field.text.length()

func _fill() -> void:
	var ens = client.you.get("ens")
	sheet.set_words("Market Hall · the sign painter", "Your shop sign",
		("It's written on %s as its description, where anyone can read it and nobody can paint over it. One line, up to %d letters." % [str(ens), MOST]) if ens != null
		else "A sign is written on your name, and your name comes with the Town Pass. Get it at the town hall, then come back.")
	sheet.set_rows([])
	sheet.set_go("Paint it" if ens != null else "")

func _paint() -> void:
	if not sheet.is_open or _pending: return
	var t := _field.text.strip_edges()
	if t == "":
		sheet.say("Write something first.")
		return
	_pending = true
	painter.greet()
	client.send({"type": "PaintSign", "text": t})
	sheet.say("The painter's at it…", false)

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"SignPainting":
			_pending = true
			if sheet.is_open: sheet.say("Painting \"%s\". Waiting for the chain to write it on your name…" % str(e.get("text", "")), false)
			get_tree().create_timer(1.8).timeout.connect(sheet.close)
		"RecordsSet":
			if _pending:
				_pending = false
				if tell.is_valid(): tell.call("Your sign is up, written on %s." % str(client.you.get("ens", "your name")))
		"QuestStepDone":
			if str(e.get("step", "")) == "sign": _pending = false
		"QuestStepFailed":
			if str(e.get("step", "")) == "sign":
				_pending = false
				if tell.is_valid(): tell.call(Refusals.reason(e.get("reason")))
