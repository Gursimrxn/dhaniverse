class_name FerryTicket
extends Control
## The first thing the player touches: their ferry ticket, held up in the opening shot, with the passenger's name still blank.
## They write their name on it. It is never a form in a room.

signal named(who: String)        # the server has accepted this name

const MAX_NAME := 20
const REFUSALS := {"NameTaken": "Someone in town already goes by that.", "BadName": "Use 3 to 20 letters or numbers."}
const STUB := Vector2(120, 200)
const HOLE_GAP := 13.0

var client: TownClient
var _sheet := PaperSheet.new(680.0)
var _field := LineEdit.new()
var _note := PaperSheet.words("", Brand.FONT_BODY, 16)
var _sent := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	_sheet.card()
	add_child(_sheet)
	var line := StyleBoxEmpty.new()
	line.content_margin_bottom = 4
	_field.add_theme_stylebox_override("normal", line)
	_field.add_theme_stylebox_override("focus", line)
	_field.add_theme_font_override("font", PaperSheet.spaced(Brand.FONT_BODY, 32, -0.02))
	_field.add_theme_font_size_override("font_size", 32)
	_field.add_theme_color_override("font_color", PaperSheet.INK)
	_field.add_theme_color_override("font_placeholder_color", Color("b9ae8e"))
	_field.add_theme_color_override("caret_color", PaperSheet.INK)
	_field.placeholder_text = "Write your name"
	_field.max_length = MAX_NAME
	_field.context_menu_enabled = false
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.draw.connect(func():              # the boards' dashed line to write on, green while writing
		var y := _field.size.y - 1.0
		_field.draw_dashed_line(Vector2(0, y), Vector2(_field.size.x, y), Brand.GREEN if _field.has_focus() else Color("b9ae8e"), 2.0, 6.0))
	_field.text_changed.connect(_lower_case)
	_field.text_submitted.connect(_submit)
	_note.add_theme_color_override("font_color", Brand.ORANGE)
	_sheet.actions.add_child(PaperSheet.Pill.new("Enter", "That's me"))
	var name_block := VBoxContainer.new()
	name_block.add_theme_constant_override("separation", 7)
	name_block.add_child(PaperSheet.caption("PASSENGER"))
	name_block.add_child(_field)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", int(PaperSheet.GAP))
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part in [PaperSheet.words("TALLYPORT FERRY", PaperSheet.spaced(Brand.FONT_DISPLAY, 12, 0.1), 12), name_block, _note]:
		main.add_child(part)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.add_child(main)
	row.add_child(_perforation())
	row.add_child(_stub())
	_sheet.page.add_child(row)
	if client: client.refused.connect(_on_refused)

## The line of holes the stub tears along.
func _perforation() -> Control:
	var holes := Control.new()
	holes.custom_minimum_size = Vector2(4, STUB.y)
	holes.draw.connect(func():
		var y := 0.0
		while y < holes.size.y:
			holes.draw_circle(Vector2(2, y), 2.0, Color(PaperSheet.INK, 0.45))
			y += HOLE_GAP)
	return holes

func _stub() -> Control:
	var stub := VBoxContainer.new()
	stub.custom_minimum_size.x = STUB.x
	stub.alignment = BoxContainer.ALIGNMENT_CENTER
	stub.add_theme_constant_override("separation", 8)
	var mark := TextureRect.new()
	mark.texture = preload("res://assets/ui/coin_mark.svg")
	mark.modulate = PaperSheet.INK
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(56, 55)
	var one_way := PaperSheet.words("ONE WAY", PaperSheet.spaced(Brand.FONT_DISPLAY, 12, 0.1), 12)
	one_way.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stub.add_child(mark)
	stub.add_child(one_way)
	return stub

func open() -> void:
	_sheet.open()
	_field.grab_focus()

func close() -> void:
	_sheet.close()

## The server has said yes to the name just sent.
func accept() -> void:
	_field.release_focus()
	named.emit(_sent)

func _lower_case(text: String) -> void:
	var low := text.to_lower()
	if low != text:
		_field.text = low
		_field.caret_column = low.length()
	_note.text = ""

func _submit(text: String) -> void:
	_sent = text
	if text != "": client.send({"type": "ClaimName", "name": text})

func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if command.get("type") != "ClaimName" or not _sheet.visible: return
	_note.text = REFUSALS.get(refusal.type, "That name won't do.")
	_field.grab_focus()
