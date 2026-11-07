class_name PhoneQuests
extends PhonePage
## Your quests: an urgent loot crate first when one is out (it won't wait), then the quest you're running (the one the guide's diamond,
## the minimap's route and the tracker point at) with its story and every step marked done, next, at the chain or still to come, then
## the others, each a press away from being the one you run. A quest can be dropped: its campaign place goes back, its energy doesn't
## (PROTOCOL.md).

const UNISWAP := preload("res://assets/ui/sponsors/Uniswap_icon_pink.png")
const PLACE_WORDS := {"market": "the Market Hall", "table": "the Common Table", "bank": "the bank", "homes": "your door, at the Homes", "square": "Tally Square",
	"harbourmaster": "the harbourmaster, on the landing", "kiosk": "the exchange, on the landing", "spice-merchant": "the Spice Merchant, in the Market Hall",
	"painter": "the sign painter, by the Market Hall", "stall": "your sign, by the Market Hall", "hall": "the town hall's clerk, by the Arrival Hall"}

var guide: Guide                   # which quest is being run, and how far its next step is
var loot: LootCrate
var _dropping := ""                # asked once: a second press drops it

func refresh() -> void:
	clear_page()
	add_theme_constant_override("separation", 10)
	var you := client.you
	add_child(heading("your quests"))
	add_child(words("Errands left today: %d · mysteries: %d" % [int(you.get("errands_left", 0)), int(you.get("mystery_left", 0))], 12, MUTED))
	var crate: Dictionary = loot.current() if loot else {}
	if not crate.is_empty(): add_child(_crate(crate))
	var quests: Array = you.get("quests", [])
	if quests.is_empty():
		add_child(words("Nothing on. The Bounty Board in Tally Square has work that pays in USDC.", 15, MUTED))
		return
	var running := TownState.quest(you, guide.tracked) if guide else {}
	if running.is_empty(): running = quests[0]
	add_child(caps("RUNNING NOW"))
	add_child(_running(running))
	var others := quests.filter(func(q): return str(q.quest) != str(running.quest))
	if others.is_empty(): return
	add_child(caps("ALSO ON"))
	for q in others: add_child(_other(q))

## The crate, time running: what it holds, where, how long is left.
func _crate(crate: Dictionary) -> Control:
	var r := row()
	(r.get_theme_stylebox("panel") as StyleBoxFlat).border_color = WARN
	(r.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(2)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.add_child(caps("URGENT · LOOT CRATE", WARN))
	column.add_child(words("%s %s" % [Usdc.text(int(crate.prize)), loot.place_words()], 17, INK, false))
	var left := TownState.clock(TownState.left_ms(crate.ends_at, client.now_ms()))
	column.add_child(words("%s left · the first one there takes it" % left, 12, MUTED, false))
	r.add_child(column)
	return r

func _running(q: Dictionary) -> Control:
	var r := row()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var title := words(str(q.get("title", "")), 18, INK, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(words("%d/%d" % [TownState.steps_done(q), q.get("steps", []).size()], 13, MUTED, false))
	column.add_child(head)
	var sponsor := _sponsor(q)
	if sponsor: column.add_child(sponsor)
	var story := words(str(q.get("story", "")), 12, MUTED)
	story.custom_minimum_size.x = WIDTH - 28.0
	column.add_child(story)
	var next := TownState.next_step(q)
	var open := TownState.open_steps(q)
	for s in q.get("steps", []):
		var done := bool(s.get("done", false))
		var waiting := bool(s.get("waiting", false))
		var is_next: bool = not next.is_empty() and s == next
		var state := "done" if done else ("waiting" if waiting else ("next" if is_next else ("open" if open.has(s) else "later")))
		var money := ""
		if str(s.get("kind", "")) == "cargo" and done and int(q.get("advanced", 0)) > 0: money = " · +$%s advanced, on an IOU" % Usdc.amount(int(q.advanced))
		column.add_child(_step(str(s.get("text", "")) + money, state))
	if not next.is_empty():
		var place := str(next.get("place", ""))
		var far: float = guide.next_distance() if guide and (loot == null or loot.current().is_empty()) else INF
		column.add_child(words("Next: %s%s" % [PLACE_WORDS.get(place, place), (" · %d m" % roundi(far)) if far != INF else ""], 13, GOOD, false))
	var owe := int(q.get("advanced", 0))
	var held := str(q.get("swapped", "0"))
	if owe > 0 or held != "0" or int(q.get("cargo_usdc", 0)) > 0:
		column.add_child(_carrying(owe, held))
	var hold = q.get("hold")
	if hold is Dictionary:
		var left := TownState.left_ms(hold.get("ends"), client.now_ms())
		column.add_child(words("Held through %d check%s · %d to go · ends %s" % [int(hold.get("passed", 0)), "" if int(hold.get("passed", 0)) == 1 else "s", int(hold.get("checks_left", 0)), TownState.soon(left)], 12, GOOD))
	column.add_child(_foot(q))
	r.add_child(column)
	return r

## One step, with its mark: a green tick done, an orange ring at the chain, a filled ring next, an open ring still to come.
func _step(text: String, state: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(14, 14)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mark.draw.connect(_draw_mark.bind(mark, state))
	line.add_child(mark)
	var said := words(text + ("  · at the chain" if state == "waiting" else ""), 13,
		MUTED if state in ["done", "later"] else (WARN if state == "waiting" else INK))
	said.custom_minimum_size.x = WIDTH - 50.0
	line.add_child(said)
	return line

func _draw_mark(mark: Control, state: String) -> void:
	var c := Vector2(7, 8)
	match state:
		"done":
			mark.draw_circle(c, 6.5, GOOD)
			mark.draw_polyline(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(-1, 2.5), c + Vector2(3.5, -2.5)]), Color.WHITE, 1.6, true)
		"waiting":
			mark.draw_arc(c, 5.5, 0.0, TAU, 20, WARN, 2.0, true)
		"next":
			mark.draw_arc(c, 5.5, 0.0, TAU, 20, INK, 2.0, true)
			mark.draw_circle(c, 2.5, INK)
		_:
			mark.draw_arc(c, 5.5, 0.0, TAU, 20, LINE.lerp(INK, 0.25), 1.5, true)

## Who pays and how the pay splits, from the quest's card on the board: the Spice Run's $1.00 is your cargo money back, then your fee.
func _sponsor(q: Dictionary) -> Control:
	var card := {}
	for c in client.city.get("bounty", []):
		if q.get("campaign") != null and int(c.get("id", -1)) == int(q.campaign): card = c
	if card.is_empty(): return null
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	if str(card.get("sponsor", "")) == "Uniswap":
		var mark := TextureRect.new()
		mark.texture = UNISWAP
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(22, 22)
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(mark)
	var pay := int(card.get("payout", 0))
	var cargo := int(q.get("cargo_usdc", 0))
	var split := (": your $%s cargo back, then $%s for you" % [Usdc.amount(cargo), Usdc.amount(pay - cargo)]) if cargo > 0 and pay > cargo else ""
	var said := words("Sponsored by %s · pays $%s%s" % [str(card.get("sponsor", "")), Usdc.amount(pay), split], 11, MUTED)
	said.custom_minimum_size.x = WIDTH - 60.0
	line.add_child(said)
	return line

## What the quest has you carrying, side by side: the advance you owe and the token you hold for the delivery.
func _carrying(owe: int, held: String) -> Control:
	var box := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color("FAFAF8")
	look.set_corner_radius_all(12)
	look.set_content_margin_all(9)
	box.add_theme_stylebox_override("panel", look)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for part in [["YOU OWE", ("$%s to the harbourmaster" % Usdc.amount(owe)) if owe > 0 else "nothing"], ["YOU CARRY", ("%s MANGO" % TokenAmount.about(held, 18)) if held != "0" else "no MANGO yet"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		col.add_child(caps(part[0]))
		var w := words(part[1], 12, INK)
		w.custom_minimum_size.x = (WIDTH - 60.0) * 0.5
		col.add_child(w)
		row.add_child(col)
	box.add_child(row)
	return box

func _other(q: Dictionary) -> Control:
	var r := row()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(words(str(q.get("title", "")), 15, INK, false))
	var next := TownState.next_step(q)
	column.add_child(words("%d/%d · %s" % [TownState.steps_done(q), q.get("steps", []).size(), QuestMarks.step_words(next) if not next.is_empty() else "waiting on the chain"], 12, MUTED, false))
	line.add_child(column)
	var run := chip("Run this")
	run.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	run.pressed.connect(func():
		if guide: guide.track(str(q.quest))
		refresh())
	line.add_child(run)
	r.add_child(line)
	return r

func _foot(q: Dictionary) -> Control:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	var pays := words("%d energy spent" % int(q.get("energy", 0)), 12, MUTED, false)
	pays.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(pays)
	var drop := chip("Drop it" if _dropping != str(q.quest) else "Sure? Drop")
	drop.pressed.connect(func():
		if _dropping == str(q.quest):
			client.send({"type": "AbandonQuest", "quest": str(q.quest)})
			_dropping = ""
		else:
			_dropping = str(q.quest)
		refresh())
	foot.add_child(drop)
	return foot
