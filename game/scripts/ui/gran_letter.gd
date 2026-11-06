class_name GranLetter
extends Control
## The letter the harbourmaster hands over on the dock: Gran's money went somewhere, and the pages of her ledger are hidden around
## town. A story beat with no choice in it: E folds it away. Its words are in Strings.

signal read                      # folded away

var _sheet := PaperSheet.new(720.0)
var _body := PaperSheet.words("", Brand.FONT_PROSE, 22, _sheet.text_width())
var _key_up := false             # E let go since it opened: the press that folds it is a new one

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet)
	var ps := PaperSheet.words(Strings.GRAN_POSTSCRIPT, Brand.FONT_EDITORIAL_ITALIC, 21)
	ps.add_theme_color_override("font_color", PaperSheet.MUTED)
	_sheet.actions.add_child(PaperSheet.Pill.new("E", "Fold it away"))
	for part in [_body, ps]:
		_sheet.page.add_child(part)

func open(who: String) -> void:
	_body.text = Strings.GRAN_LETTER % who
	_key_up = false
	_sheet.open()

func close() -> void:
	_sheet.close()

func _process(_delta: float) -> void:
	if _sheet.visible and not Input.is_action_pressed("interact"): _key_up = true

func _unhandled_input(e: InputEvent) -> void:
	if not _sheet.visible or not _key_up or not e.is_action_pressed("interact"): return
	get_viewport().set_input_as_handled()
	_sheet.close()
	read.emit()
