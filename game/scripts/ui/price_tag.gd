class_name PriceTag
extends WorldTag
## A paper tag over the food, as on the town-event board: what it is, today's price in USDC, and how far the price moved since
## yesterday, green when it fell. It shows what the server says and works nothing out for itself.

const TAIL := Vector2(6, 7)      # half its width, and its height
const MARGIN := Vector2(11, 5)
const DEARER := Color("c44d00")
const FLIP := 0.4                # s the split-flap takes, both halves
const NUDGE := 3.6               # px the arrow nudges the way the price went

var _row := HBoxContainer.new()
var _name := Label.new()
var _price := Flap.new()
var _dir := Control.new()
var _moved := Label.new()
var _plate := StyleBoxFlat.new()
var _units := -1                 # the price last shown, in USDC base units; -1 before the first
var _moved_by := 0
var _up := true                  # the arrow's way: since yesterday
var _nudge := 0.0

func _init() -> void:
	super()
	_plate.bg_color = Brand.CREAM
	_plate.set_corner_radius_all(11)
	_plate.shadow_color = Color(0, 0, 0, 0.35)
	_plate.shadow_size = 7
	_plate.shadow_offset = Vector2(0, 7)
	_row.add_theme_constant_override("separation", 7)
	for part in [[_name, Brand.FONT_BODY, 12], [_moved, Brand.FONT_NUMBER, 12]]:
		var l: Label = part[0]
		l.add_theme_font_override("font", part[1])
		l.add_theme_font_size_override("font_size", part[2])
		l.add_theme_color_override("font_color", Brand.PLATE)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dir.custom_minimum_size = Vector2(9, 8)
	_dir.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dir.draw.connect(_draw_dir)
	for c in [_name, _price, _dir, _moved]: _row.add_child(c)
	_row.minimum_size_changed.connect(_fit)
	add_child(_row)

## units: today's price, in USDC base units. moved: how much it rose (above 0) or fell (below 0) since yesterday; 0 shows nothing.
## A new price flips in like a station board, and the arrow nudges the way it went.
func show_price(item: String, units: int, moved: int) -> void:
	if visible and units == _units and moved == _moved_by and item == _name.text: return    # the counter says it every frame
	_name.text = item
	_moved_by = moved
	var was := _units
	_units = units
	if was != units: _price.show_figure(Usdc.text(units), "" if was < 0 or was == units or not HudMotion.on else Usdc.text(was))
	# the board shows a percentage; what it moved by is what the counter passes, exactly
	_moved.text = ("+" if moved > 0 else "") + Usdc.amount(moved)
	_moved.add_theme_color_override("font_color", Brand.ORANGE if moved > 0 else Brand.GREEN)
	_moved.visible = moved != 0
	_dir.visible = moved != 0
	_up = moved > 0
	if was >= 0 and was != units and HudMotion.on:
		var way := -NUDGE if units > was else NUDGE
		var t := create_tween()
		t.tween_method(_set_nudge, 0.0, way, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_method(_set_nudge, way, 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_dir.queue_redraw()
	_fit()
	visible = true

func _set_nudge(v: float) -> void:
	_nudge = v
	_dir.queue_redraw()

## The arrow: up and burnt orange when it's dearer than yesterday, down and green when it's cheaper.
func _draw_dir() -> void:
	var s := _dir.size
	var y := _nudge + (s.y - 8.0) * 0.5
	var tri := [Vector2(0, 8), Vector2(9, 8), Vector2(4.5, 0)] if _up else [Vector2(0, 0), Vector2(9, 0), Vector2(4.5, 8)]
	_dir.draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(0, y), tri[1] + Vector2(0, y), tri[2] + Vector2(0, y)]), DEARER if _up else Brand.GREEN)

func _fit() -> void:
	_row.position = MARGIN
	_row.reset_size()
	size = _row.get_combined_minimum_size() + MARGIN * 2.0 + Vector2(0, TAIL.y)
	queue_redraw()

func clear() -> void:
	visible = false

## The plate, and its tail straight under it in the same cream: no outline.
func _draw() -> void:
	var bottom := size.y - TAIL.y
	var mid := size.x * 0.5
	draw_style_box(_plate, Rect2(0, 0, size.x, bottom))
	draw_colored_polygon(PackedVector2Array([Vector2(mid - TAIL.x, bottom - 0.5), Vector2(mid + TAIL.x, bottom - 0.5), Vector2(mid, size.y)]), Brand.CREAM)

## The price as a split-flap figure: four halves, each a window on a whole label. At rest the top and bottom show the price; on a
## change the old top folds down over the new one, then the new bottom folds down over the old.
class Flap extends Control:
	const SIZE := 16
	var _top := _half(false)
	var _bottom := _half(true)
	var _fold := _half(false, true)      # the old top, folding down
	var _land := _half(true, true)       # the new bottom, folding down after it
	var _turn: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for h in [_top, _bottom, _fold, _land]: add_child(h)

	func _half(lower: bool, flap := false) -> Control:
		var h: Control = ColorRect.new() if flap else Control.new()
		if flap: (h as ColorRect).color = Brand.CREAM
		h.clip_contents = true
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.visible = not flap
		var l := Label.new()
		l.add_theme_font_override("font", Brand.FONT_NUMBER)
		l.add_theme_font_size_override("font_size", SIZE)
		l.add_theme_color_override("font_color", Brand.PLATE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_meta("lower", lower)
		h.add_child(l)
		return h

	## old: the figure it flips from; empty shows the new one at once.
	func show_figure(now: String, old: String) -> void:
		var f: Font = Brand.FONT_NUMBER
		var w := maxf(f.get_string_size(now, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x, f.get_string_size(old, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x)
		var full := Vector2(ceilf(w) + 2.0, ceilf(f.get_height(SIZE)))
		custom_minimum_size = full
		for h: Control in [_top, _bottom, _fold, _land]:
			var l: Label = h.get_child(0)
			var lower: bool = l.get_meta("lower")
			h.position = Vector2(0, full.y * 0.5 if lower else 0.0)
			h.size = Vector2(full.x, full.y * 0.5)
			h.pivot_offset = Vector2(full.x * 0.5, 0.0 if lower else full.y * 0.5)
			l.position = Vector2(0, -full.y * 0.5 if lower else 0.0)
			l.size = full
		if _turn: _turn.kill()
		_label(_top).text = now
		_label(_land).text = now
		_label(_fold).text = old
		_label(_bottom).text = old if old != "" else now
		_fold.visible = old != ""
		_land.visible = false
		if old == "": return
		_fold.scale.y = 1.0
		_land.scale.y = 0.0
		_turn = create_tween()
		_turn.tween_property(_fold, "scale:y", 0.0, FLIP * 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_turn.tween_callback(func():
			_fold.visible = false
			_land.visible = true)
		_turn.tween_property(_land, "scale:y", 1.0, FLIP * 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_turn.tween_callback(func():
			_label(_bottom).text = now
			_land.visible = false)

	func _label(h: Control) -> Label:
		return h.get_child(0)
