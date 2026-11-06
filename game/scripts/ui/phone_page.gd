class_name PhonePage
extends VBoxContainer
## One page on the phone. It shows what the client last heard from the server, and works nothing out for itself.
## The phone's screen is the landing's light look: near-white, black type in Satoshi, soft white cards, black pills.

const INK := Color("111111")                  # words on the screen
const MUTED := Color(0, 0, 0, 0.55)           # small print
const ROW := Color("FFFFFF")                  # a card on the screen
const LINE := Color(0, 0, 0, 0.07)            # a card's edge, a rule
const GOOD := Color("337E43")                 # money in, done, yours
const WARN := Color("B64A06")                 # orange that reads on white
const MONEY := Color("0011FF")
const WIDTH := 292.0             # what's inside the phone's screen

const FONT_LIGHT := preload("res://assets/fonts/Satoshi-Light.woff2")
const FONT_REGULAR := preload("res://assets/fonts/Satoshi-Regular.woff2")
const FONT_MEDIUM := preload("res://assets/fonts/Satoshi-Medium.woff2")

var client: TownClient

## Called when the page opens, and when the server's word changes.
func refresh() -> void:
	pass

func clear_page() -> void:
	for old in get_children():
		remove_child(old)
		old.queue_free()

## Words on the screen. Big sizes set in Medium, the rest in Regular.
static func words(text: String, font_size := 15, colour := INK, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT_MEDIUM if font_size >= 20 else FONT_REGULAR)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH
	return label

## A page's title: lowercase, as the landing sets its headings.
static func heading(text: String) -> Label:
	var label := words(text.to_lower(), 26, INK, false)
	label.add_theme_constant_override("line_spacing", -4)
	return label

## The landing's small label: Satoshi Light in capitals.
static func caps(text: String, colour := INK) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", FONT_LIGHT)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", colour)
	return label

## A soft white card, holding whatever is put in it.
static func row() -> PanelContainer:
	var panel := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = ROW
	look.border_color = LINE
	look.set_border_width_all(1)
	look.set_corner_radius_all(16)
	look.shadow_color = Color(0, 0, 0, 0.05)
	look.shadow_size = 6
	look.shadow_offset = Vector2(0, 3)
	look.content_margin_left = 14
	look.content_margin_right = 14
	look.content_margin_top = 11
	look.content_margin_bottom = 11
	panel.add_theme_stylebox_override("panel", look)
	return panel

## A pill button in the screen's look: black when chosen, clear otherwise.
static func chip(text: String, on := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT_MEDIUM)
	b.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "hover", "pressed"]:
		var look := StyleBoxFlat.new()
		look.bg_color = Color("111111") if on else (Color(0, 0, 0, 0.08) if state != "normal" else Color(0, 0, 0, 0))
		look.set_corner_radius_all(99)
		look.content_margin_left = 11
		look.content_margin_right = 11
		look.content_margin_top = 6
		look.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, look)
		b.add_theme_color_override("font_" + state + "_color" if state != "normal" else "font_color", Brand.CREAM if on else INK)
	return b

## The landing's money pill: green with white-ish caps, as "Send money" on its bank card.
static func action(text: String, primary := true) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", FONT_MEDIUM)
	b.add_theme_font_size_override("font_size", 11)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var look := StyleBoxFlat.new()
		look.bg_color = (GOOD if primary else Color(0.35, 0.35, 0.35, 0.55)).lightened(0.08 if state == "hover" else 0.0)
		look.set_corner_radius_all(99)
		look.content_margin_top = 11
		look.content_margin_bottom = 11
		b.add_theme_stylebox_override(state, look)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b
