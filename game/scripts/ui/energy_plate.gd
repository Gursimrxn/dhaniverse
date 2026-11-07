class_name EnergyPlate
extends VBoxContainer
## The HUD's top left, as on the design board: your face, your name and your energy, with when the next point comes back by itself and
## when the free thali is ready; under it your wallet: its USDC, your Town Pass, your tickets for the week's draw, your streak, whether
## your chest is ready and what the town owes you. It only shows what the server gave it, counted down on the real clock between its words.

const AT := Vector2(21, 21)
const ROLL := 0.4                  # s the USDC figure takes to roll to a new amount
const RISE := 0.9                  # s the gain beside it takes to rise and go
const SPEND := Color("FF8A3D")

var client: TownClient
var energy := EnergyPips.new()
var _face := PlayerFace.new()
var _you: Control                  # the face and the plate beside it
var _name := Label.new()
var _energy_line := RichTextLabel.new()
var _points := Label.new()         # the energy as a number, beside its pips
var _wallet := PanelContainer.new()
var _usdc := Label.new()
var _usdc_note := Label.new()
var _disc := Panel.new()           # the blue $ disc money always wears
var _unit := Label.new()
var _gain := Label.new()           # "+0.04", rising off the figure as it rolls
var _target := -1                  # USDC units the figure is rolling to
var _shown := 0.0
var _rolling: Tween
var _status := RichTextLabel.new()
var _carry := HBoxContainer.new()  # ux13: what a quest has you carrying, beside the money: the IOU and the quest token
var _iou := Label.new()
var _cargo := Label.new()
var _tick := 0.0
var pass_waiting := Callable()     # true while a Town Pass link is open in the browser (TownPassDesk.waiting)

func _ready() -> void:
	position = AT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 11)
	_you = _top_row()
	add_child(_you)
	add_child(_wallet_plate())

## The phone is out (ux10): your face and energy step back, the wallet plate stays, dimmed, beside the phone's own wallet.
func phone_out(out: bool) -> void:
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_you, "modulate:a", 0.0 if out else 1.0, 0.2)
	t.tween_property(_wallet, "modulate:a", 0.55 if out else 1.0, 0.2)

func _plate(left: int, right: int, vertical: int, radius := 99) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Brand.PLATE
	s.border_color = Brand.CREAM
	s.set_border_width_all(3)
	s.set_corner_radius_all(radius)
	s.content_margin_left = left
	s.content_margin_right = right
	s.content_margin_top = vertical
	s.content_margin_bottom = vertical
	return Brand.as_plate(s)

## The board's small print: words in Satoshi, the numbers in them in Bitroad.
static func small_print(label: RichTextLabel, font_size := 12) -> RichTextLabel:
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", Brand.FONT_BODY)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", Brand.CREAM_MUTED)
	return label

static func mono(text: String) -> String:
	return "[font=%s]%s[/font]" % [Brand.FONT_NUMBER.resource_path, text]

## The face, overlapping a plate with your name and energy.
func _top_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -11)
	row.add_child(_face)
	_face.z_index = 1
	_face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plate := PanelContainer.new()
	var look := _plate(25, 14, 11, 18)
	look.corner_radius_top_left = 0
	look.corner_radius_bottom_left = 0
	plate.add_theme_stylebox_override("panel", look)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	_name.add_theme_font_override("font", Brand.FONT_BODY)
	_name.add_theme_font_size_override("font_size", 15)
	_name.add_theme_color_override("font_color", Brand.CREAM)
	column.add_child(_name)
	var meter := HBoxContainer.new()     # ux02: the number, then its ten pips
	meter.add_theme_constant_override("separation", 8)
	_points.add_theme_font_override("font", Brand.FONT_BODY)
	_points.add_theme_font_size_override("font_size", 17)
	_points.add_theme_color_override("font_color", Brand.CREAM)
	meter.add_child(_points)
	energy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.add_child(energy)
	column.add_child(meter)
	column.add_child(small_print(_energy_line))
	plate.add_child(column)
	row.add_child(plate)
	return row

## Your wallet's plate: the USDC big, then a line for each thing waiting on you.
func _wallet_plate() -> Control:
	var look := _plate(14, 14, 9, 18)
	_wallet.add_theme_stylebox_override("panel", look)
	_wallet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	_usdc.add_theme_font_override("font", Brand.FONT_BODY)    # money in Satoshi Bold: Bitroad's slashed zero misreads
	_usdc.add_theme_font_size_override("font_size", 20)
	_usdc.add_theme_color_override("font_color", Brand.CREAM)
	var disc := StyleBoxFlat.new()
	disc.bg_color = Brand.BLUE
	disc.set_corner_radius_all(11)
	_disc.add_theme_stylebox_override("panel", disc)
	_disc.custom_minimum_size = Vector2(22, 22)
	_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dollar := Label.new()
	dollar.text = "$"
	dollar.add_theme_font_override("font", Brand.FONT_BODY)
	dollar.add_theme_font_size_override("font_size", 13)
	dollar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dollar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dollar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_disc.add_child(dollar)
	_unit.text = "USDC"
	_unit.add_theme_font_override("font", Brand.FONT_BODY)
	_unit.add_theme_font_size_override("font_size", 11)
	_unit.add_theme_color_override("font_color", Brand.CREAM_MUTED)
	_unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gain.add_theme_font_override("font", Brand.FONT_BODY)
	_gain.add_theme_font_size_override("font_size", 14)
	_gain.modulate.a = 0.0
	_unit.add_child(_gain)
	_usdc_note.add_theme_font_override("font", Brand.FONT_BODY)
	_usdc_note.add_theme_font_size_override("font_size", 11)
	_usdc_note.add_theme_color_override("font_color", Brand.ORANGE)
	_usdc_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for part in [_disc, _usdc, _unit, _usdc_note]: top.add_child(part)
	column.add_child(top)
	_carry.add_theme_constant_override("separation", 6)
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry.add_child(_chip(_iou, Brand.CREAM, Brand.PLATE, Color(0, 0, 0, 0)))
	_carry.add_child(_chip(_cargo, Color("3a2a10"), Color("F0C33A"), Color("F0C33A")))
	column.add_child(_carry)
	column.add_child(small_print(_status))
	_wallet.add_child(column)
	return _wallet

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or client == null or client.you.is_empty(): return
	_tick = 0.5
	_read()

## What the server last said about you.
func _read() -> void:
	var you := client.you
	if you.is_empty(): return
	var now := client.now_ms()
	var points := int(you.get("energy", 0))
	_name.text = str(you.get("name", ""))
	_face.set_fill(points / float(maxi(int(you.get("energy_max", 100)), 1)))
	energy.show_energy(points)
	var regen := TownState.left_ms(you.get("energy_regen_at"), now)
	_points.text = str(points)
	var line := "Free thali ready at the Common Table" if TownState.free_meal_ready(you, now) \
		else "Free thali in %s" % mono(TownState.clock(TownState.left_ms(you.get("free_meal_at"), now)))
	if you.get("energy_regen_at") != null: line = "+1 energy in %s" % mono(TownState.clock(regen))
	if you.get("meal_pending") != null: line = "[color=#%s]A meal on its way to the chain[/color]" % Brand.ORANGE.to_html(false)
	_energy_line.text = line     # ux02: one line under the pips
	_write_wallet(you, now)

func _write_wallet(you: Dictionary, now: int) -> void:
	var usdc = you.get("usdc")
	_disc.visible = usdc != null
	_unit.visible = usdc != null
	if usdc == null: _usdc.text = "Wallet coming"
	else: _roll_to(int(usdc))
	_usdc_note.text = ""
	# ux02: one line under the amount, only when money is held for you or the Town Pass is missing.
	var warm := Brand.ORANGE.to_html(false)
	var line := ""
	if int(you.get("pending", 0)) > 0:
		var why := {}
		for r in you.get("pending_rewards", []): why[str(r.get("waiting", ""))] = true
		var said: String = "stamp your Town Pass" if why.has("town_pass") else ("the chain retries tomorrow" if why.has("chain") else "paid from tomorrow's budget")
		line = "Held for you [color=#FFF8E3]$%s[/color] · %s" % [Usdc.amount(int(you.pending)), said]
	elif not bool(you.get("human", false)):
		line = "[color=#%s]%s[/color]" % [warm, "Town Pass: waiting for World ID" if pass_waiting.is_valid() and pass_waiting.call() else "No Town Pass yet"]
	_status.text = line
	_status.visible = line != ""
	var carry := TownState.carrying(you)
	_iou.text = "IOU $%s · harbourmaster" % Usdc.amount(int(carry.owe))
	_iou.visible = int(carry.owe) > 0
	_cargo.text = "%s %s" % [TokenAmount.about(str(carry.cargo), int(carry.decimals)), str(carry.symbol)]
	_cargo.visible = str(carry.cargo) != "0"
	_carry.visible = _iou.visible or _cargo.visible

## A small pill on the wallet plate.
func _chip(label: Label, fill: Color, ink: Color, ring: Color) -> Label:
	var look := StyleBoxFlat.new()
	look.bg_color = fill
	look.border_color = ring
	look.set_border_width_all(1 if ring.a > 0.0 else 0)
	look.set_corner_radius_all(99)
	look.content_margin_left = 8
	look.content_margin_right = 8
	look.content_margin_top = 2
	look.content_margin_bottom = 2
	label.add_theme_stylebox_override("normal", look)
	label.add_theme_font_override("font", Brand.FONT_BODY)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## From now on, what this client hears.
func listen(to: TownClient) -> void:
	client = to
	client.you_changed.connect(_read)
	client.synced.connect(_read)

## A new amount: the figure rolls to it, and what changed rises off it, mint for money in, orange for money out.
func _roll_to(units: int) -> void:
	if units == _target: return
	var from := _target
	_target = units
	if _rolling: _rolling.kill()
	if from < 0 or not HudMotion.on:
		_show(units)
		return
	_rolling = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_rolling.tween_method(_show, _shown, float(units), ROLL)
	var change := units - from
	_gain.text = ("+" if change > 0 else "-") + Usdc.amount(absi(change))
	_gain.add_theme_color_override("font_color", Brand.MINT if change > 0 else SPEND)
	_gain.position = Vector2(_unit.size.x + 8.0, 0.0)
	_gain.modulate.a = 1.0
	var t := create_tween().set_parallel()
	t.tween_property(_gain, "position:y", -18.0, RISE).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_gain, "modulate:a", 0.0, RISE * 0.45).set_delay(RISE * 0.55)

## The figure at a point in its roll, to as many places as the amount it's rolling to has (at least two).
func _show(units: float) -> void:
	_shown = units
	var places := maxi(Usdc.amount(_target).get_slice(".", 1).length(), 2)
	_usdc.text = "%.*f" % [places, units / Usdc.UNITS]
