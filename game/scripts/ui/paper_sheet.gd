class_name PaperSheet
extends Control
## A sheet of printed paper held up over the game: the paper, a loan, a letter from the bank. Put what it says in `page`, and its
## buttons in `actions`, which sit under it on the scene, as on the loan board. Nothing pauses behind it.
## Sizes are the boards' (GameLoan, GameArrival) at 1280x720: 1rem is 8.9px.

const OPEN_TIME := 0.18
const RISE := 21.0               # px it comes up from as it opens
const MARGIN := 28.0
const GAP := 21.0
const PAPER := Color("fffdf6")
const INK := Color("262727")
const MUTED := Color("5c5642")   # labels and small print on paper
const ABOVE_THE_WORLD := 50      # z index: over tags in the world, under the blast
const BRAND_STRIPE := ["ffecbd", "ff6600", "e52efe", "7079ff", "74bcde", "a1ffb4"]
const BRAND_STOPS := [0.0, 0.14, 0.33, 0.66, 0.83, 1.0]

var page := VBoxContainer.new()
var actions := HBoxContainer.new()
var tilt := 0.0                  # degrees
var _backdrop := ColorRect.new()
var _panel := PanelContainer.new()
var _look := StyleBoxFlat.new()
var _rise := 0.0
var _stripe: GradientTexture1D

## width: of the sheet. text_width() is what's left inside it.
func _init(width := 760.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://shaders/ui/paper_backdrop.gdshader")
	_backdrop.material = blur
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_look.bg_color = PAPER
	_look.set_corner_radius_all(5)
	_look.set_content_margin_all(MARGIN)
	_look.shadow_color = Color(0, 0, 0, 0.5)
	_look.shadow_size = 57
	_look.shadow_offset = Vector2(0, 28)
	_panel.add_theme_stylebox_override("panel", _look)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size.x = width
	_panel.draw.connect(_draw_stripe)
	page.add_theme_constant_override("separation", int(GAP))
	_panel.add_child(page)
	add_child(_panel)
	actions.add_theme_constant_override("separation", int(GAP))
	add_child(actions)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = ABOVE_THE_WORLD
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## The resident card's look: rounder, tilted, the brand's stripe across the top.
func card() -> void:
	_look.set_corner_radius_all(21)
	_look.content_margin_top = MARGIN + 11.0
	tilt = -2.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(BRAND_STOPS)
	g.colors = PackedColorArray(BRAND_STRIPE.map(func(c): return Color(c)))
	_stripe = GradientTexture1D.new()
	_stripe.gradient = g

func text_width() -> float:
	return _panel.custom_minimum_size.x - MARGIN * 2.0

func open() -> void:
	visible = true
	_rise = RISE
	_panel.modulate.a = 0.0
	_place()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_rise", 0.0, OPEN_TIME)
	t.tween_property(_panel, "modulate:a", 1.0, OPEN_TIME)

func close() -> void:
	visible = false

func _process(_delta: float) -> void:
	if visible: _place()

## The sheet and its buttons, together in the middle.
func _place() -> void:
	_panel.reset_size()
	actions.reset_size()
	actions.visible = actions.get_child_count() > 0
	var below := actions.size.y + GAP if actions.visible else 0.0
	_panel.rotation_degrees = tilt
	_panel.pivot_offset = _panel.size * 0.5
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, (size.y - _panel.size.y - below) * 0.5 + _rise)
	actions.position = _panel.position + Vector2(0.0, _panel.size.y + GAP)
	actions.modulate.a = _panel.modulate.a

func _draw_stripe() -> void:
	if _stripe == null: return
	var w := _panel.size.x
	var r := 21.0
	var h := 11.0
	var edge := PackedVector2Array()
	for i in 7:                  # down the rounded corner, so the stripe keeps the card's shape
		var y := h * i / 6.0
		edge.append(Vector2(r - sqrt(r * r - (r - y) * (r - y)), y))
	var points := PackedVector2Array()
	for i in range(edge.size() - 1, -1, -1): points.append(edge[i])
	for p in edge: points.append(Vector2(w - p.x, p.y))
	var uvs := PackedVector2Array()
	for p in points: uvs.append(Vector2(p.x / w, 0.5))
	_panel.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, _stripe)

## Words on a sheet.
static func words(text: String, font: Font, font_size: int, wrap_width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	if wrap_width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = wrap_width
	return label

## A small capital label on a sheet, as the boards' NAME and I BORROW.
static func caption(text: String) -> Label:
	var l := words(text, spaced(Brand.FONT_BODY, 11, 0.08), 11)
	l.add_theme_color_override("font_color", MUTED)
	return l

## A font with the boards' letter-spacing, in em.
static func spaced(font: Font, font_size: int, em: float) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = font
	v.spacing_glyph = roundi(font_size * em)
	return v

## A key to press. Dark on paper and in the cream button; a ring on the scene.
static func key_cap(letter: String, ghost := false) -> Label:
	var l := words(letter, Brand.FONT_DISPLAY, 12)
	var cap := StyleBoxFlat.new()
	cap.bg_color = Color.TRANSPARENT if ghost else INK
	cap.border_color = Color("6b6656")
	cap.set_border_width_all(2 if ghost else 0)
	cap.set_corner_radius_all(7)
	cap.content_margin_left = 7
	cap.content_margin_right = 7
	l.add_theme_stylebox_override("normal", cap)
	l.add_theme_color_override("font_color", Brand.CREAM_MUTED if ghost else Brand.CREAM)
	l.custom_minimum_size = Vector2(25, 25)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## A button under the sheet, as the loan board's: the cream "Sign for" pill, or the plain "Not today" (ghost).
## `fill`, 0 to 1, is how far a held key has got.
class Pill extends PanelContainer:
	var fill := 0.0:
		set(v):
			if v != fill: queue_redraw()
			fill = v
	var _fill_look := StyleBoxFlat.new()

	func _init(key: String, text: String, ghost := false) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var look := StyleBoxFlat.new()
		look.bg_color = Color.TRANSPARENT if ghost else Brand.CREAM
		look.set_corner_radius_all(99)
		look.content_margin_left = 0 if ghost else 11
		look.content_margin_right = 0 if ghost else 21
		add_theme_stylebox_override("panel", look)
		custom_minimum_size.y = 39 if ghost else 50
		_fill_look.bg_color = Brand.ORANGE
		_fill_look.set_corner_radius_all(99)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7 if ghost else 11)
		row.add_child(PaperSheet.key_cap(key, ghost))
		var said := PaperSheet.words(text, Brand.FONT_BODY, 14 if ghost else 16)
		if ghost: said.add_theme_color_override("font_color", Brand.CREAM_MUTED)
		row.add_child(said)
		add_child(row)

	func _draw() -> void:
		if fill > 0.0: _fill_look.draw(get_canvas_item(), Rect2(0, 0, size.x * fill, size.y))

## Is a text field taking the keys? Then letter and number keys are the player's writing, not commands.
static func is_typing(from: Node) -> bool:
	return from.get_viewport().gui_get_focus_owner() is LineEdit
