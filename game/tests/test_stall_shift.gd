extends TestCase
## The key at a stall: what it does in each situation.

func test_take_then_serve() -> void:
	var s := StallShift.new()
	var id := s.add_order("apple")
	eq(s.action(""), StallShift.Do.NOTHING, "empty hands, at no crate")
	eq(s.press("apple"), StallShift.Do.TAKE, "take")
	eq(s.held, "apple", "held")
	eq(s.action(""), StallShift.Do.SERVE, "the order's item hands over from anywhere behind the counter")
	eq(s.press("lime"), StallShift.Do.SERVE, "at another crate it still hands over")
	eq(s.served.id, id, "the order filled")
	eq(s.held, "", "hands empty")
	eq(s.orders.size(), 0, "queue")

func test_wrong_item_never_traps_you() -> void:
	var s := StallShift.new()
	s.add_order("mango")
	s.press("apple")
	eq(s.action("apple"), StallShift.Do.PUT_BACK, "at its own crate")
	eq(s.press("lime"), StallShift.Do.SWAP, "at another crate")
	eq(s.held, "lime", "swapped")
	eq(s.press(""), StallShift.Do.REFUSE, "away from the crates")
	eq(s.held, "lime", "a refusal keeps it")
	eq(s.orders.size(), 1, "the order stays")
	eq(s.press("lime"), StallShift.Do.PUT_BACK, "put back")
	eq(s.held, "", "hands empty")

func test_only_the_front_order_counts() -> void:
	var s := StallShift.new()
	s.add_order("apple")
	s.add_order("lime")
	s.press("lime")
	eq(s.action(""), StallShift.Do.REFUSE, "the second customer's item, at no crate")
	s.press("lime")      # puts it back
	s.press("apple")
	s.press("")
	eq(s.wanted(), "lime", "the next moves up")

func test_walking_away_clears_the_hands() -> void:
	var s := StallShift.new()
	s.add_order("apple")
	s.press("apple")
	s.leave()
	eq(s.held, "", "held")
	eq(s.orders.size(), 1, "orders wait")
