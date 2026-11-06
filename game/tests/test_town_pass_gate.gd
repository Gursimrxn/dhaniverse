extends TestCase
## The Town Pass at the gangway: World ID, once, at sign-up. Held there only on a town that can stamp one, and only until it's stamped.

const CITY := {"day": 1.0, "day_ms": 3600000.0, "day_elapsed_ms": 0.0, "now_ms": 0.0, "chain": "sepolia", "price": 4000.0}

func _client(town_pass: bool, human: bool, wallet = "0xabc") -> TownClient:
	var c := TownClient.new()
	c.player = "sam"                   # as start() or the ticket's claim leaves it
	c.handle_message({"type": "snapshot", "seq": 1.0, "debug": false, "town_pass": town_pass,
		"you": {"name": "sam", "energy": 100.0, "human": human, "wallet": wallet}, "city": CITY.duplicate()})
	return c

func test_a_new_passenger_shows_the_pass_where_one_can_be_had() -> void:
	var c := _client(true, false)
	check(c.town_pass, "the snapshot says this town stamps passes")
	check(TownPassGate.wanted(c), "held at the gangway")
	c.free()

func test_once_stamped_it_is_never_asked_for_again() -> void:
	var c := _client(true, true)
	check(not TownPassGate.wanted(c), "a stamped pass lets them straight in")
	c.free()

func test_a_town_that_cannot_stamp_one_holds_nobody() -> void:
	var c := _client(false, false)
	check(not c.town_pass, "no town_pass in the snapshot")
	check(not TownPassGate.wanted(c), "nobody is stuck at a gangway that can't open")
	c.free()

func test_an_old_server_without_the_field_holds_nobody() -> void:
	var c := TownClient.new()
	c.handle_message({"type": "snapshot", "seq": 1.0, "debug": false, "you": {"name": "sam", "human": false}, "city": CITY.duplicate()})
	check(not TownPassGate.wanted(c), "missing means no")
	c.free()

func test_stamping_lets_them_ashore() -> void:
	var c := _client(true, false)
	var desk := TownPassDesk.new()
	desk.client = c
	var gate := TownPassGate.new()
	gate.client = c
	gate.desk = desk
	var root := Node.new()
	Engine.get_main_loop().root.add_child(root)
	root.add_child(gate)
	var passed: Array[int] = []
	gate.passed.connect(func(): passed.append(1))
	gate.open()
	check(gate.is_open(), "the sheet is up")
	c.handle_message({"type": "event", "seq": 2.0, "event": {"type": "HumanVerified", "account": "sam"}})
	eq(passed.size(), 1, "HumanVerified lets them ashore")
	check(not gate.is_open(), "the sheet is put away")
	c.handle_message({"type": "event", "seq": 2.0, "event": {"type": "HumanVerified", "account": "sam"}})
	eq(passed.size(), 1, "only once")
	root.queue_free()
	desk.free()
	c.free()

func test_someone_elses_pass_does_not_open_the_gate() -> void:
	var c := _client(true, false)
	var desk := TownPassDesk.new()
	desk.client = c
	var gate := TownPassGate.new()
	gate.client = c
	gate.desk = desk
	var root := Node.new()
	Engine.get_main_loop().root.add_child(root)
	root.add_child(gate)
	gate.open()
	c.handle_message({"type": "event", "seq": 2.0, "event": {"type": "HumanVerified", "account": "priya"}})
	check(gate.is_open(), "still waiting for their own")
	root.queue_free()
	desk.free()
	c.free()
