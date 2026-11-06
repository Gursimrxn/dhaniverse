class_name LinkNotice
extends PanelContainer
## Says plainly when the game can't reach the town's server: there is no second set of rules to fall back on, so nothing the
## player does counts until it's back. Stand-in look, on the brand's plate.

const GRACE := 3.0               # s without a link before it says so: not on every start-up, not on a blink
const DOWN := "Can't reach the town's server. Trying again…"
const KICKED := "This town is open in another window."
const TOP := 72.0                # px: under the island

var client: TownClient
var _down_for := 0.0
var _label := Label.new()

func _ready() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(99)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	add_theme_stylebox_override("panel", s)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", Brand.FONT_BODY)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Brand.CREAM)
	add_child(_label)
	visible = false

func _process(delta: float) -> void:
	_down_for = 0.0 if client.up or not client.trying else _down_for + delta
	visible = _down_for > GRACE
	if not visible: return
	_label.text = KICKED if client.kicked else DOWN
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, TOP)
