class_name MorningPaper
extends Control
## The Dhaniverse Tally, written by the server from what really happened. When a new one comes out, a folded corner shows
## its headline for a while; N opens today's paper at any time, and N or Esc closes it. Nothing pauses behind it.

const NAME := "The Dhaniverse Tally"
const SHOW_NEW_FOR := 14.0       # s

var client: TownClient
var _corner := PanelContainer.new()
var _corner_headline := PaperSheet.words("", Brand.FONT_BODY, 17)
var _corner_left := 0.0
var _sheet := PaperSheet.new()
var _day := PaperSheet.words("", Brand.FONT_BODY, 15)
var _headline := PaperSheet.words("", Brand.FONT_EDITORIAL_ITALIC, 40, _sheet.text_width())
var _stories := VBoxContainer.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_corner()
	_build_sheet()
	if client: client.event.connect(_on_event)

func _build_corner() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.CREAM
	s.border_color = Brand.PLATE
	s.set_border_width_all(3)
	s.set_corner_radius_all(14)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	_corner.add_theme_stylebox_override("panel", s)
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	title.add_child(PaperSheet.key_cap("N"))
	title.add_child(PaperSheet.words(NAME, Brand.FONT_EDITORIAL, 22))
	column.add_child(title)
	column.add_child(_corner_headline)
	_corner.add_child(column)
	_corner.visible = false
	add_child(_corner)

func _build_sheet() -> void:
	add_child(_sheet)
	var masthead := PaperSheet.words(NAME, Brand.FONT_EDITORIAL_ITALIC, 54)
	masthead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := ColorRect.new()
	rule.color = PaperSheet.INK
	rule.custom_minimum_size.y = 3
	_stories.add_theme_constant_override("separation", 10)
	for part in [masthead, _day, rule, _headline, _stories]: _sheet.page.add_child(part)

func _on_event(e: Dictionary) -> void:
	if e.type != "PaperPublished": return
	_corner_headline.text = str(e.headline)
	_corner_left = SHOW_NEW_FOR
	_corner.visible = true
	if _sheet.visible: _fill(e)

func _fill(paper: Dictionary) -> void:
	_day.text = "Day %d" % int(paper.day)
	_headline.text = str(paper.headline)
	for old in _stories.get_children(): old.queue_free()
	for story in paper.stories:
		_stories.add_child(PaperSheet.words(str(story), Brand.FONT_PROSE, 21, _sheet.text_width()))

func toggle() -> void:
	if _sheet.visible:
		_sheet.close()
		return
	var paper = client.city.get("paper") if client else null
	if paper != null: show_paper(paper)

## Opens this front page.
func show_paper(paper: Dictionary) -> void:
	_fill(paper)
	_corner.visible = false
	_sheet.open()

func _input(e: InputEvent) -> void:
	if not e is InputEventKey or PaperSheet.is_typing(self) and e.keycode != KEY_ESCAPE: return
	if not e.is_pressed() or e.is_echo(): return
	if e.keycode == KEY_N or (e.keycode == KEY_ESCAPE and _sheet.visible):
		if not _sheet.visible and not Screens.free_to_open(): return
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _corner.visible: return
	_corner_left -= delta
	if _corner_left <= 0.0:
		_corner.visible = false
		return
	_corner.reset_size()
	_corner.position = Vector2(21, size.y - _corner.size.y - 21)
