class_name JobSlip
extends Control
## One quest, start to pay (ux03), its last two beats. A quest done prints its job slip, held up for HOLD s and then pocketed: the town,
## the quest, the tickets it gave and its pay, with the advance it repaid when it had one. Every cent paid prints a receipt that reads
## what it was for, the wallet after it and where it landed on the chain, and then flies to the wallet plate, whose number rolls.

const HOLD := 3.0                  # s the slip is held up
const RECEIPT_FOR := 1.6           # s a receipt stays before it flies
const INK := Color("262727")
const MUTED := Color("5d5e5e")

var client: TownClient
var wallet_at := Callable()        # where the wallet plate is on the screen, for the receipt to fly to
var _quests := {}                  # quest id -> its last state, for the slip once the quest has left the log
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	client.you_changed.connect(_remember)
	client.synced.connect(_remember)
	client.event.connect(_on_event)

func _remember() -> void:
	for q in client.you.get("quests", []): _quests[str(q.quest)] = q

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"QuestDone": _slip(e)
		"RewardPaid": _receipt(e)

func _paper(width: float) -> PanelContainer:
	var paper := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.CREAM
	look.set_corner_radius_all(3)
	look.content_margin_left = 18
	look.content_margin_right = 18
	look.content_margin_top = 14
	look.content_margin_bottom = 16
	look.shadow_color = Color(0, 0, 0, 0.45)
	look.shadow_size = 18
	look.shadow_offset = Vector2(0, 10)
	paper.add_theme_stylebox_override("panel", look)
	paper.custom_minimum_size.x = width
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return paper

static func _line(left: String, right: String, px := 13, ink := INK) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = left
	l.add_theme_font_override("font", Brand.FONT_BODY)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", ink)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_font_override("font", Brand.FONT_DISPLAY)
	r.add_theme_font_size_override("font_size", px + 1)
	r.add_theme_color_override("font_color", ink)
	row.add_child(r)
	return row

static func _caps(words: String, ink := MUTED) -> Label:
	var l := Label.new()
	l.text = words
	l.add_theme_font_override("font", PaperSheet.spaced(Brand.FONT_BODY, 10, 0.16))
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", ink)
	return l

## The job slip: held up beside you, then down into your pocket.
func _slip(e: Dictionary) -> void:
	var r: Dictionary = e.get("reward", {})
	var q: Dictionary = _quests.get(str(e.get("quest", "")), {})
	var paper := _paper(300.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.add_child(_caps("DHANIVERSE · JOB SLIP"))
	var title := Label.new()
	title.text = str(e.get("title", "a quest"))
	title.add_theme_font_override("font", Brand.FONT_EDITORIAL_ITALIC)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", INK)
	column.add_child(title)
	if int(r.get("tickets", 0)) > 0: column.add_child(_line("Tickets", "+%d" % int(r.tickets)))
	var pay := int(r.get("usdc", 0))
	var advanced := int(q.get("advanced", 0))
	if pay > 0:
		column.add_child(_line("Pay", "$%s" % Usdc.amount(pay)))
		if advanced > 0: column.add_child(_line("less your advance", "−$%s" % Usdc.amount(advanced), 12, MUTED))
		var human := bool(client.you.get("human", false))
		column.add_child(_line("into your wallet" if human else "held for your Town Pass", "$%s" % Usdc.amount(pay - advanced) if human else "", 12, Brand.GREEN if human else Brand.ORANGE))
	if r.get("title") != null and str(r.get("title", "")) != "": column.add_child(_line("A title", str(r.title), 12, MUTED))
	paper.add_child(column)
	add_child(paper)
	paper.reset_size()
	paper.pivot_offset = paper.size * 0.5
	paper.rotation_degrees = -3.0
	var shown := Vector2(size.x * 0.5 - paper.size.x - 40.0, size.y * 0.5 - paper.size.y * 0.5)
	paper.position = shown + Vector2(0, 60)
	paper.modulate.a = 0.0
	var t := paper.create_tween()
	t.tween_property(paper, "position", shown, 0.45 if HudMotion.on else 0.01).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(paper, "modulate:a", 1.0, 0.25)
	t.tween_interval(HOLD)
	t.tween_property(paper, "position", shown + Vector2(40, size.y * 0.6), 0.5 if HudMotion.on else 0.01).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(paper, "rotation_degrees", 12.0, 0.5)
	t.parallel().tween_property(paper, "modulate:a", 0.0, 0.5)
	t.tween_callback(paper.queue_free)

## The receipt: it prints under the map, says what the cent was for and where it landed, and flies to the wallet.
func _receipt(e: Dictionary) -> void:
	var landed := int(e.get("amount", 0)) - int(e.get("advance_repaid", 0))
	if landed <= 0: return
	var paper := _paper(230.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var city := client.city
	var now := Time.get_time_dict_from_system()
	column.add_child(_caps("RECEIPT · DAY %d · %02d:%02d" % [int(city.get("day", 1)), int(now.hour), int(now.minute)]))
	column.add_child(_line(str(e.get("why", "a reward")).capitalize(), "+$%s" % Usdc.amount(landed)))
	var usdc = client.you.get("usdc")
	if usdc != null: column.add_child(_line("Wallet", "$%s" % Usdc.amount(int(usdc)), 12, MUTED))
	var tx := str(e.get("tx", ""))
	var chain := str(city.get("chain", "offline"))
	column.add_child(_caps(("ON CHAIN · %s" % TownState.short_address(tx)) if chain != "offline" and tx != "" else "REHEARSAL · NO CHAIN", Brand.GREEN))
	paper.add_child(column)
	add_child(paper)
	paper.reset_size()
	var start := Vector2(size.x - paper.size.x - 21.0, 200.0)
	paper.position = start
	paper.scale = Vector2(1.0, 0.0)
	var t := paper.create_tween()
	t.tween_property(paper, "scale", Vector2.ONE, 0.35 if HudMotion.on else 0.01).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(RECEIPT_FOR)
	var to: Vector2 = wallet_at.call() if wallet_at.is_valid() else Vector2(40, 110)
	t.tween_property(paper, "position", to, 0.6 if HudMotion.on else 0.01).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(paper, "scale", Vector2.ONE * 0.2, 0.6)
	t.parallel().tween_property(paper, "modulate:a", 0.0, 0.6)
	t.tween_callback(paper.queue_free)
