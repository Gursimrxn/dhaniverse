class_name EnergyPlate
extends VBoxContainer
## The HUD's top left, as on the design board: your face, your name and your energy, with when the next point comes back by itself and
## when the free thali is ready; under it your wallet: its USDC, your Town Pass, your tickets for the week's draw, your streak, whether
## your chest is ready and what the town owes you. It only shows what the server gave it, counted down on the real clock between its words.

const AT := Vector2(21, 21)

var client: TownClient
var energy := EnergyPips.new()
var _face := PlayerFace.new()
var _name := Label.new()
var _energy_line := RichTextLabel.new()
var _wallet := PanelContainer.new()
var _usdc := Label.new()
var _usdc_note := Label.new()
var _status := RichTextLabel.new()
var _tick := 0.0
var pass_waiting := Callable()     # true while a Town Pass link is open in the browser (TownPassDesk.waiting)

func _ready() -> void:
	position = AT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 11)
	add_child(_top_row())
	add_child(_wallet_plate())

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
	_name.add_theme_font_size_override("font_size", 14)
	_name.add_theme_color_override("font_color", Brand.CREAM)
	column.add_child(_name)
	column.add_child(energy)
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
	_usdc.add_theme_font_override("font", Brand.FONT_NUMBER)
	_usdc.add_theme_font_size_override("font_size", 18)
	_usdc.add_theme_color_override("font_color", Brand.CREAM)
	_usdc_note.add_theme_font_override("font", Brand.FONT_BODY)
	_usdc_note.add_theme_font_size_override("font_size", 11)
	_usdc_note.add_theme_color_override("font_color", Brand.ORANGE)
	_usdc_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_usdc)
	top.add_child(_usdc_note)
	column.add_child(top)
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
	var lines := ["Energy %s%s" % [mono(str(points)), (" · +1 in %s" % mono(TownState.clock(regen))) if you.get("energy_regen_at") != null else ""]]
	lines.append("[color=#%s]Free thali ready[/color]" % Brand.MINT.to_html(false) if TownState.free_meal_ready(you, now)
		else "Free thali in %s" % mono(TownState.clock(TownState.left_ms(you.get("free_meal_at"), now))))
	if you.get("meal_pending") != null: lines.append("[color=#%s]A meal on its way to the chain[/color]" % Brand.ORANGE.to_html(false))
	_energy_line.text = "\n".join(lines)
	_write_wallet(you, now)

func _write_wallet(you: Dictionary, now: int) -> void:
	var usdc = you.get("usdc")
	_usdc.text = Usdc.text(int(usdc)) if usdc != null else "Wallet coming"
	var offline := str(client.city.get("chain", "offline")) == "offline"
	_usdc_note.text = "REHEARSAL" if offline else ""
	var mint := Brand.MINT.to_html(false)
	var warm := Brand.ORANGE.to_html(false)
	var gold := "F0C33A"
	var lines := []
	if bool(you.get("human", false)): lines.append("[color=#%s]Town Pass[/color]" % mint)
	elif pass_waiting.is_valid() and pass_waiting.call(): lines.append("[color=#%s]Town Pass: waiting for World ID[/color]" % warm)
	else: lines.append("[color=#%s]No Town Pass yet[/color]" % warm)
	var streak: Dictionary = you.get("streak", {})
	var tickets := int(you.get("tickets", 0))
	lines.append("%s ticket%s · streak %s of %s days" % [mono(str(tickets)), "" if tickets == 1 else "s", mono(str(int(streak.get("week_days", 0)))), mono(str(int(streak.get("need", 5))))])
	var chest: Dictionary = you.get("chest", {})
	if TownState.chest_ready(you, now): lines.append("[color=#%s]Your chest is ready, at your door[/color]" % gold)
	elif not chest.is_empty(): lines.append("Chest in %s" % mono(TownState.clock(TownState.left_ms(chest.get("ready_at"), now))))
	if TownState.weekly_ready(you, now): lines.append("[color=#%s]Weekly strongbox ready[/color]" % gold)
	if int(you.get("pending", 0)) > 0:
		var why := {}
		for r in you.get("pending_rewards", []): why[str(r.get("waiting", ""))] = true
		var said: String = "waiting for your Town Pass" if why.has("town_pass") else ("the chain retries tomorrow" if why.has("chain") else "paid from tomorrow's budget")
		lines.append("%s owed to you: %s" % [mono(Usdc.text(int(you.pending))), said])
	if you.get("rescue_at") != null: lines.append("[color=#%s]A neighbour's coming with a thali: %s[/color]" % [mint, mono(TownState.clock(TownState.left_ms(you.rescue_at, now)))])
	_status.text = "\n".join(lines)

## From now on, what this client hears.
func listen(to: TownClient) -> void:
	client = to
	client.you_changed.connect(_read)
	client.synced.connect(_read)
