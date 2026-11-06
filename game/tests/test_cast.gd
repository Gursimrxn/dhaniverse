extends TestCase
## The named townsfolk: who they are, where they stand, and a line that fits the player's day.

const Cast := preload("res://scripts/life/cast.gd")

func test_the_cast_is_all_there() -> void:
	for id in ["harbourmaster", "kofi", "mei", "elias", "priya", "arthur", "bo", "sam", "dario", "yusuf", "ingrid"]:
		check(Cast.PEOPLE.has(id), "%s missing" % id)
		check(str(Cast.PEOPLE.get(id, {}).get("post", "")) != "", "%s has no post" % id)
		check(Cast.line(id, {}) != "Hello.", "%s has no line of their own" % id)

func test_lines_follow_the_players_day() -> void:
	var fresh := Cast.line("mei", {"milestones": {}})
	check("eat" in fresh.to_lower(), "Mei should offer a newcomer a meal: " + fresh)
	check(Cast.line("mei", {"milestones": {"first_meal": true}}) != fresh, "Mei says the same after the first meal")

func test_no_one_talks_about_what_the_town_no_longer_has() -> void:
	for id in Cast.PEOPLE:
		var said := Cast.line(id, {}).to_lower()
		for word in ["wage", "loan", "savings", "register", "interest", "shift", "rent"]:
			check(not word in said, "%s still mentions %s: %s" % [id, word, said])
