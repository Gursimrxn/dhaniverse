class_name PhoneQuests
extends PhonePage
## Your quest log: each quest you're on, its story, its steps ticked off as the server says, a pending stamp on a step gone to the chain,
## and where the next one is (the minimap's gold marker points there). Hold the Line shows its checks. A quest can be dropped: its campaign
## place goes back, its energy doesn't (PROTOCOL.md).

const PLACE_WORDS := {"market": "the Market Hall", "table": "the Common Table", "bank": "the bank", "homes": "your door, at the Homes", "square": "Tally Square",
	"harbourmaster": "the harbourmaster, on the landing", "kiosk": "the exchange, on the landing", "spice-merchant": "the Spice Merchant, in the Market Hall",
	"painter": "the sign painter, by the Market Hall", "stall": "your sign, by the Market Hall", "hall": "the town hall's clerk, by the Arrival Hall"}

var _dropping := ""                # asked once: a second press drops it

func refresh() -> void:
	clear_page()
	add_theme_constant_override("separation", 10)
	var you := client.you
	var quests: Array = you.get("quests", [])
	add_child(words("Your quests", 22))
	add_child(words("Errands left today: %d · mysteries: %d" % [int(you.get("errands_left", 0)), int(you.get("mystery_left", 0))], 13, MUTED))
	if quests.is_empty():
		add_child(words("Nothing on. The Bounty Board in Tally Square has work that pays in USDC.", 15, MUTED))
		return
	for q in quests: add_child(_quest(q))

func _quest(q: Dictionary) -> Control:
	var r := row()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	var title := words(str(q.get("title", "")), 17, INK, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(words("%d/%d" % [TownState.steps_done(q), q.get("steps", []).size()], 13, MUTED, false))
	column.add_child(head)
	var story := words(str(q.get("story", "")), 12, MUTED)
	story.custom_minimum_size.x = WIDTH - 24.0
	column.add_child(story)
	var next := TownState.next_step(q)
	var open := TownState.open_steps(q)
	for s in q.get("steps", []):
		var done := bool(s.get("done", false))
		var waiting := bool(s.get("waiting", false))
		var is_open: bool = open.has(s)
		var mark := "[x]" if done else ("[..]" if waiting else ("[ ]" if is_open else " · "))
		var line := words("%s %s%s" % [mark, str(s.get("text", "")), "  (waiting for the chain)" if waiting else ""], 13,
			MUTED if done else (WARN if waiting else (INK if is_open else MUTED)))
		line.custom_minimum_size.x = WIDTH - 24.0
		column.add_child(line)
	var hold = q.get("hold")
	if hold is Dictionary:
		var left := TownState.left_ms(hold.get("ends"), client.now_ms())
		column.add_child(words("Held through %d check%s · %d to go · ends %s" % [int(hold.get("passed", 0)), "" if int(hold.get("passed", 0)) == 1 else "s", int(hold.get("checks_left", 0)), TownState.soon(left)], 13, GOOD))
	if not next.is_empty():
		var place := str(next.get("place", ""))
		var where := words("Next: %s" % PLACE_WORDS.get(place, place), 13, Color("F0C33A"))
		where.custom_minimum_size.x = WIDTH - 24.0
		column.add_child(where)
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
	column.add_child(foot)
	r.add_child(column)
	return r
