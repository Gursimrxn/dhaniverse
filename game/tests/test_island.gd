extends TestCase
## The island's line of moments, where it puts the sun, and the boards' easing.

func test_a_meal_goes_first_the_town_last_and_the_line_is_capped() -> void:
	var q: Array[Dictionary] = []
	for kind in ["town", "mentor", "rush", "meal", "rush", "rush"]: Island.queue_in(q, {"kind": kind})
	eq(q.map(func(m): return m.kind), ["meal", "rush", "rush", "rush", "mentor", "town"], "order")
	Island.queue_in(q, {"kind": "meal"})
	eq(q.size(), Island.WAITING, "capped")
	eq(q.back().kind, "mentor", "the town goes first when the line is full")

func test_dawn_is_left_noon_the_top_dusk_right() -> void:
	near(Island.sun_t(_dir(90.0, 2.0)), 0.0, 0.05, "dawn, in the east")
	near(Island.sun_t(_dir(180.0, 60.0)), 0.5, 0.01, "noon, in the south")
	near(Island.sun_t(_dir(270.0, 2.0)), 1.0, 0.05, "dusk, in the west")

func test_the_mentor_line_is_its_first_sentence_then_whole_words() -> void:
	eq(Island.first_sentence("Chai costs more than yesterday. That's called inflation."), "Chai costs more than yesterday.", "first sentence")
	eq(Island.first_sentence("No stop here"), "No stop here", "no stop")
	var font := Brand.FONT_BODY
	eq(Island.whole_words("Short.", 400.0, font, 11), "Short.", "fits")
	var cut := Island.whole_words("one two three four five six seven", font.get_string_size("one two three", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0, font, 11)
	eq(cut, "one two three…", "whole words")

func test_the_ease_runs_from_nothing_to_all_and_is_quick_out_of_the_blocks() -> void:
	near(Island.ease_out(0.0), 0.0, 0.001, "start")
	near(Island.ease_out(1.0), 1.0, 0.001, "end")
	check(Island.ease_out(0.3) > 0.6, "most of the way by a third: %f" % Island.ease_out(0.3))

## valley/world.gd's _dir: compass bearing and height to a direction, x east.
static func _dir(az_deg: float, el_deg: float) -> Vector3:
	return load("res://scripts/valley/world.gd")._dir(az_deg, el_deg)
