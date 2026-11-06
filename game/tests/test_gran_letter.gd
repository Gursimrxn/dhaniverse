extends TestCase
## Gran's letter: a story beat with the player's name in it, and no choice to make.

func test_the_letter_names_the_player_and_points_at_the_ledger() -> void:
	var text: String = Strings.GRAN_LETTER % "sam"
	check(text.begins_with("Dear sam,"), "addressed to the player: " + text.left(20))
	check("ledger" in text.to_lower(), "the hook: her ledger's pages")
	check("Gran" in text, "signed")

func test_it_has_nothing_to_sign() -> void:
	var said: Array = (load("res://scripts/ui/gran_letter.gd") as Script).get_script_signal_list().map(func(s): return s.name)
	check("read" in said, "folding it away is all there is")
	check(not "decided" in said, "no choice left in it")
