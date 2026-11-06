class_name PhoneTown
extends PhonePage
## The town together: this week's Town Goal (meals town-wide; reaching it makes everyone's next chest one better), the weekly draw (your
## tickets, everyone's, the prize it would have now), today's Market Rush pot and who leads it, this season's Rush board with your place,
## your Price Call, and, for someone new, who sent you. Never an amount anyone paid or holds: only the town's totals and names.

var _friend := LineEdit.new()
var _said := ""

func _init() -> void:
	_friend.placeholder_text = "Who sent you?"
	_friend.max_length = 20
	_friend.custom_minimum_size.x = 170
	_friend.add_theme_font_override("font", Brand.FONT_BODY)
	_friend.add_theme_font_size_override("font_size", 14)

func refresh() -> void:
	if _friend.get_parent(): _friend.get_parent().remove_child(_friend)
	clear_page()
	add_theme_constant_override("separation", 9)
	var you := client.you
	var city := client.city
	var goal: Dictionary = city.get("town_goal", {})
	add_child(words("This week's Town Goal", 16))
	var target := maxi(int(goal.get("target", 0)), 1)
	var bar := ProgressBar.new()
	bar.max_value = target
	bar.value = int(goal.get("progress", 0))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(WIDTH, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Brand.GREEN
	fill.set_corner_radius_all(5)
	var track := StyleBoxFlat.new()
	track.bg_color = LINE
	track.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", track)
	add_child(bar)
	var tier := str(you.get("chest", {}).get("tier", "wood"))
	add_child(words(("Reached! Everyone's next chest is one better." if bool(goal.get("reached", false))
		else "%d of %d meals eaten in town. Reach it and your next chest goes from %s to %s." % [int(goal.get("progress", 0)), int(goal.get("target", 0)), tier, TownState.tier_after(tier)]), 13, MUTED))
	var draw: Dictionary = city.get("draw", {})
	add_child(words("The weekly draw", 16))
	add_child(_fact("Your tickets", str(int(you.get("tickets", 0)))))
	add_child(_fact("Tickets in, town-wide", str(int(draw.get("tickets", 0)))))
	add_child(_fact("Prize now", Usdc.text(int(draw.get("prize", 0)))))
	add_child(words("Tickets are earned, never bought: a day you come, a Rush run, a chest, a quest, a right Price Call." + ("" if bool(you.get("human", false)) else " Only Town Pass holders are in the draw."), 12, MUTED))
	var rush: Dictionary = city.get("rush", {})
	add_child(words("Market Rush today", 16))
	add_child(_fact("Today's pot", Usdc.text(int(rush.get("pot", 0)))))
	add_child(_fact("Your best today", str(int(you.get("best_today", 0)))))
	add_child(_fact("Runs left", "%d of %d" % [int(you.get("runs_left", 0)), int(rush.get("runs_per_day", 3))]))
	var today: Array = rush.get("today", [])
	for e in today.slice(0, 5): add_child(_entry(e))
	add_child(words("The top 10 share the pot when the day closes.", 12, MUTED))
	add_child(words("Market Rush, this season", 16))
	var rows: Array = city.get("boards", {}).get("rush", [])
	if rows.is_empty(): add_child(words("Nobody on the board yet this season.", 13, MUTED))
	for e in rows: add_child(_entry(e))
	var mine = you.get("ranks", {}).get("rush")
	add_child(words("You: #%d" % int(mine) if mine != null else "You're on it after your first run", 14, WARN))
	var call = you.get("price_call")
	add_child(words("Price Call", 16))
	add_child(words("Today you called %s. It settles when the next city day opens." % str(call.call) if call is Dictionary else "Call tomorrow's food price at the board in Tally Square.", 13, MUTED))
	add_child(words("Who sent you?", 16))
	if you.get("referrer") != null:
		add_child(words("%s sent you." % str(you.referrer), 13, MUTED))
	else:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(_friend)
		var b := chip("That's them")
		b.pressed.connect(func():
			var who := _friend.text.strip_edges().to_lower()
			if who != "": client.send({"type": "Refer", "player": who}))
		line.add_child(b)
		add_child(line)
		add_child(words(_said if _said != "" else "When you have your Town Pass and a quest done, you both get tickets.", 12, MUTED if _said == "" else WARN))

func listen() -> void:
	client.refused.connect(func(command: Dictionary, refusal: Dictionary):
		if command.get("type") == "Refer":
			_said = Refusals.say(refusal, client.now_ms())
			if is_visible_in_tree(): refresh())

func _fact(what: String, value: String) -> Control:
	var line := HBoxContainer.new()
	var label := words(what, 14, MUTED, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	line.add_child(words(value, 14, INK, false))
	return line

func _entry(entry: Dictionary) -> Control:
	var r := row()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.add_child(words(str(int(entry.get("rank", 0))), 16, INK, false))
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 0)
	who.add_child(words(str(entry.get("name", "")), 14, WARN if str(entry.get("name", "")) == client.player else INK, false))
	if str(entry.get("title", "")) != "": who.add_child(words(str(entry.title), 12, MUTED, false))
	line.add_child(who)
	r.add_child(line)
	return r
