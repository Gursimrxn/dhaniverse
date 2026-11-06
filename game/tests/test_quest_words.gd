extends TestCase
## The words a quest step, a meal and a sheet put in front of the player: short enough for a hint, the free thali kept apart from
## the paid menu, and Grandma's pages placed where the server says.

func test_a_step_reads_as_a_short_hint() -> void:
	eq(QuestMarks.step_words({"text": "Collect the chai from the Common Table."}), "Collect the chai from the Common Table", "a short one whole")
	eq(QuestMarks.step_words({"text": "Collect the cargo money from the harbourmaster. If your wallet is short, he'll advance it."}), "Collect the cargo money from the…", "its first sentence, in whole words")
	eq(QuestMarks.step_words({}), "", "no text")

func test_the_free_thali_is_never_the_best_buy_or_priced() -> void:
	var free := {"name": "free", "free": true, "price": 0, "energy": 40}
	var chai := {"name": "chai", "price": 3623, "energy": 10}
	check(FoodMenu._per(free) == INF, "the free one isn't compared")
	near(FoodMenu._per(chai), 3623.0 * 20.0 / 10.0, 0.01, "USDC per energy bar, from the server's price")
	eq(FoodMenu._label(free), "Community thali", "its name")
	eq(FoodMenu._label({"name": "vada_pav"}), "Vada pav", "the server's names, in words")

func test_every_menu_item_has_food_on_the_ledge() -> void:
	for item in ["chai", "vada_pav", "thali"]:
		check(FoodCounter.MODEL_OF.has(item), "%s stands on the ledge" % item)
		check(FoodCounter.LABELS.has(item), "%s has a name" % item)

func test_the_places_quests_name_are_in_town() -> void:
	for place in ["market", "table", "bank", "homes", "square", "harbourmaster", "kiosk", "hall", "stall", "spice-merchant", "painter"]:
		check(Tallyport.PLACES.has(place) or place in Tallyport.PEOPLE, "%s is a place in town" % place)

func test_the_phone_keeps_clear_of_the_map_the_keys_and_the_bar() -> void:
	var phone := Phone.new()
	for screen in [Vector2(1280, 720), Vector2(1382, 720), Vector2(1395, 720)]:     # 16:9, and a maximised window's 1536x864 and 1920x1080 less the taskbar
		var r := phone.frame_rect(screen)
		var map := Rect2(screen.x - 21.0 - 167.0, 21.0, 167.0, 167.0 + 11.0 + 20.0)      # the minimap and the place name under it
		var keys := Rect2(screen.x - 21.0 - 150.0, screen.y - 21.0 - 90.0, 150.0, 90.0)   # the key hints, bottom right
		var bar := Rect2(screen.x * 0.5 - 180.0, screen.y - 21.0 - 102.0, 360.0, 102.0)    # the slot bar, bottom centre
		check(not r.intersects(map), "%s: clear of the minimap" % screen)
		check(not r.intersects(keys), "%s: clear of the key hints" % screen)
		check(not r.intersects(bar), "%s: clear of the slot bar" % screen)
		check(r.position.y >= 100.0 and r.size.y >= 450.0, "%s: under the island, and still tall (%d)" % [screen, int(r.size.y)])
	phone.free()
