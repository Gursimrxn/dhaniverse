class_name PhonePage
extends VBoxContainer
## One page on the phone. It shows what the client last heard from the server, and works nothing out for itself.

const MUTED := Color("C9C1A6")
const ROW := Color("333434")
const WIDTH := 300.0             # what's inside the phone's frame

var client: TownClient

## Called when the page opens, and when the server's word changes.
func refresh() -> void:
	pass

func clear_page() -> void:
	for old in get_children():
		remove_child(old)
		old.queue_free()

static func words(text: String, font_size := 16, colour := Brand.CREAM, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Brand.FONT_BODY)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH
	return label

## A rounded dark row, holding whatever is put in it.
static func row() -> PanelContainer:
	var panel := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = ROW
	look.set_corner_radius_all(12)
	look.content_margin_left = 12
	look.content_margin_right = 12
	look.content_margin_top = 9
	look.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", look)
	return panel

## A small button in the phone's look. `on` marks the chosen one.
static func chip(text: String, on := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Brand.FONT_BODY)
	b.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed"]:
		var look := StyleBoxFlat.new()
		look.bg_color = Brand.CREAM if on or state == "hover" else ROW
		look.set_corner_radius_all(99)
		look.content_margin_left = 11
		look.content_margin_right = 11
		look.content_margin_top = 4
		look.content_margin_bottom = 4
		b.add_theme_stylebox_override(state, look)
		b.add_theme_color_override("font_" + state + "_color" if state != "normal" else "font_color", Brand.PLATE if on or state == "hover" else Brand.CREAM)
	return b
