class_name MarketStall
extends Node3D
## Kofi's stall, and Market Rush. Walk behind the counter and the key starts a run (three a day, PROTOCOL.md): 90 seconds timed by the
## server, which rings the bell at the end (RushTimeUp). Walk away any time and it ends, and Kofi carries on without you. People drift in
## when they drift in, look over the crates, and some buy: those line up with what they want over their heads. Wait too long and they
## go. The key takes from the crate you stand at and hands over to the one at the counter. A run's count goes on the season's board and
## today's, whose top ten share the day's Rush pot; the server keeps the count (TownClient). Rules: StallShift. Model and the named
## points read here: tools/blender/build_stall.py. A chalkboard by the counter says what's left today.

const MODEL := preload("res://assets/market/stall.glb")
const AISLE := Rect2(-3.1, -1.85, 6.2, 1.42)     # behind the counter (stall x, z)
const CRATE_REACH := 0.8           # m along the counter from a crate's middle
const ITEM_NAMES := {"apple": "Apples", "mango": "Mangoes", "lime": "Limes"}
const ITEM_ICONS := {"apple": preload("res://assets/ui/produce/apple.svg"), "mango": preload("res://assets/ui/produce/mango.svg"), "lime": preload("res://assets/ui/produce/lime.svg")}
const KEY := "E"
const QUEUE_SIZE := 3
const ARRIVE_EVERY := Vector2(2.0, 8.0)   # s between people coming in
const LULL_CHANCE := 0.18          # now and then, nobody for a while
const LULL := Vector2(10.0, 18.0)  # s
const BROWSE := Vector2(0.8, 4.5)  # s looking over the crates
const JUST_LOOKING := 0.15         # who looks and leaves
const PATIENCE := Vector2(35.0, 70.0)   # s in line before they give up
const KOFI_SERVES := Vector2(3.5, 7.0)  # s he takes over one, when you're not behind the counter
const NEAR := 45.0                 # m: further away than this, nobody needs to be coming in
const GIVE_UP := ["Never mind.", "I'll come back.", "No time today."]
const THANKS := ["Thanks!", "Lovely.", "Just right.", "", ""]
const KOFI_LOOK := {"top": "e07a3a", "tee": "e8e2d4", "skin": "6e452e", "hair": "2b2018", "bottom": "3b3a4a", "shoes": "2a2a30", "open_top": false, "tall": 1.08, "wide": 1.2, "beard": true, "cap": true, "hat": "e07a3a", "apron": true, "apron_colour": "c98a5e"}
const VIEW_SIDE := 0.55             # m over his shoulder, during a run: composed, not a default follow
const RUSH_FULL := "That's the last customer of this rush. Step away from the counter to end it."
const KOFI_ASIDE := Vector3(3.8, 0.05, -1.1)   # where he stands when you've taken the crates (stall frame)
const CHEER := 0.9                 # s the served one stays, pleased, before leaving
const ITEM_FLIGHT := 0.22          # s from his hand to where it is going

var player: CharacterBody3D
var client: TownClient
var paint := Callable()            # gives a model the town's materials
var browse := Rect2(-3.0, 1.9, 6.0, 1.1)   # where people stand looking it over (stall x, z)
var cinema: Cinema
var view_pitch := -25.0            # how steeply the view looks during a run (deg): under a roof, it has to stay low
var route_in: Array[Vector3] = []  # the way from the street to the head of the queue line, in the world
var route_out: Array[Vector3] = [] # the way back out

var shift := StallShift.new()
var behind := false                # standing behind the counter
var in_rush := false               # a run is under way, as the server said (RushStarted until RushEnded)
var _starting := false             # StartRush sent, no answer yet
var _board: Label3D                # the chalkboard by the counter
var _queue: Array[MarketCustomer] = []
var _slots := {}                   # item -> Vector3, where the worker stands (stall frame)
var _items := {}                   # item -> a hidden copy of what is carried
var _spots: Array[Vector3] = []    # the queue's spots, 0 at the counter (world)
var _carried: Node3D
var _hint: KeyHint
var _screen: ShiftScreen           # the run's own plates, up during a run
var _tags: Control
var _crate_tops := {}              # item -> Vector3, where its hint sits (world)
var _rng := RandomNumberGenerator.new()
var _dressed := 0                  # customers so far: the next outfit
var _next_in := 0.5                # s until someone else comes in
var _coming := 0                   # on their way, not yet in line
var _kofi: MarketCustomer
var _kofi_in := 0.0
var _quiet := false                # the server says this run has had all its customers

## tags: where the plates over things live (the world's UI layer).
func setup(tags: Control) -> void:
	_tags = tags
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	paint.call(model)
	for node in model.find_children("*", "Node3D", true, false):
		var label := String(node.name)
		if label.begins_with("Slot_"): _slots[label.trim_prefix("Slot_")] = (node as Node3D).position
		elif label.begins_with("Crate_"): _crate_tops[label.trim_prefix("Crate_")] = (node as Node3D).global_position
		elif label.begins_with("Queue_"): _spots.append((node as Node3D).global_position)
		elif label.begins_with("Item_"):
			_items[label.trim_prefix("Item_")] = node
			(node as Node3D).visible = false
		elif label == "Coin": (node as Node3D).visible = false     # the model's coin: there's no pay to show
	_hint = KeyHint.new()
	tags.add_child(_hint)
	_screen = ShiftScreen.new()
	_screen.stall = self
	_screen.client = client
	tags.add_child(_screen)
	client.refused.connect(_on_refused)
	client.synced.connect(_reconcile_rush)
	client.event.connect(_on_event)
	client.answered.connect(func(_ref, _ok): _starting = false)
	_chalkboard()
	_rng.randomize()
	_kofi = MarketCustomer.new()
	add_child(_kofi)
	_kofi.top_level = true
	_kofi.setup("folk", KOFI_LOOK, _tags)
	_kofi.position = to_global(Vector3(float(_slots.values()[0].x), 0.05, float(_slots.values()[0].z)))
	_kofi.face(global_position + global_basis * Vector3(0, 0, 4))

func _order_for(c: MarketCustomer) -> String:
	var items: Array = ITEM_NAMES.keys()
	var item: String = items[_rng.randi_range(0, items.size() - 1)]
	c.order_id = shift.add_order(item)
	return item

## Every order in the queue: large for the one at the counter, small for the rest.
func _show_orders() -> void:
	for i in _queue.size():
		_queue[i].bubble.show_order(ITEM_ICONS[_queue[i].item], i == 0)

func _new_customer() -> MarketCustomer:
	var c := MarketCustomer.new()
	_dressed += 1
	add_child(c)
	c.top_level = true
	c.watching = player
	c.setup("folk", MarketCustomer.PersonScript.folk_look(_rng.randi()), _tags)
	return c

func _process(delta: float) -> void:
	if player == null: return
	_people(delta)
	var p := to_local(player.global_position)
	var now_behind := AISLE.has_point(Vector2(p.x, p.z))
	if now_behind != behind:
		behind = now_behind
		player.rig.hold_view((PI + global_rotation.y) if behind else null, view_pitch, VIEW_SIDE)
		if not behind:
			player.rest_yaw = null
			if in_rush: client.send({"type": "EndRush"})
			_run_over()
	if behind: player.rest_yaw = _facing() if in_rush else 0.0
	_update_hint(_crate_at(p))
	_write_board()

## The run has begun, as the server says (RushStarted): Kofi steps aside and the customers come quicker.
func _run_begins() -> void:
	in_rush = true
	_quiet = false
	_kofi_moves()
	_next_in = minf(_next_in, _rng.randf_range(0.3, 1.5))

## The run is over (the bell, walking away, or the server ending it): what was carried goes back on its crate.
func _run_over() -> void:
	if not in_rush: return
	in_rush = false
	_quiet = false
	_kofi_moves()
	if shift.held != "":
		shift.leave()
		if _carried: _carried.queue_free()
		_carried = null
		player.avatar.set_carrying(false)

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"RushStarted": if behind: _run_begins()
		"RushTimeUp":
			var n := int(e.get("served", 0))
			if cinema: cinema.say("Time's up! %s served." % ("1 order" if n == 1 else "%d orders" % n), 3.5)
			_run_over()
		"RushEnded": _run_over()

## The key behind the counter with no run on: start one, if there are runs left today.
func start_run() -> void:
	if in_rush or _starting: return
	if int(client.you.get("runs_left", 0)) <= 0:
		if cinema: cinema.say(Refusals.say({"type": "NoRunsLeft", "most": client.city.get("rush", {}).get("runs_per_day", 3), "resets_at": client.city.get("next_real_day_at")}, client.now_ms()), 4.0)
		return
	_starting = true
	client.send({"type": "StartRush"})

## The chalkboard by the counter: runs left, today's best and the pot.
func _chalkboard() -> void:
	_board = Label3D.new()
	_board.font = Brand.FONT_BODY
	_board.font_size = 40
	_board.pixel_size = 0.0024
	_board.modulate = Brand.CREAM
	_board.outline_size = 8
	_board.outline_modulate = Color(Brand.PLATE, 0.8)
	_board.position = Vector3(-3.7, 1.75, 1.0)     # on the customers' side, at the counter's end: seen walking up, not over the shoulder
	_board.visibility_range_end = 20.0
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_board.width = 900.0
	_board.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board.double_sided = false            # read from the street, not through the back over his shoulder
	add_child(_board)

func _write_board() -> void:
	var you := client.you
	if you.is_empty():
		_board.text = ""
		return
	var rush: Dictionary = client.city.get("rush", {})
	var left_ms := TownState.rush_left(you, client.now_ms())
	var head := "MARKET RUSH · %s left" % TownState.clock(left_ms) if in_rush and left_ms > 0 else "MARKET RUSH"
	_board.text = "%s\nRuns left today: %d of %d\nYour best today: %d\nToday's pot: %s, shared by the top 10" % [head, int(you.get("runs_left", 0)), int(rush.get("runs_per_day", 3)),
		int(you.get("best_today", 0)), Usdc.text(int(rush.get("pot", 0)))]

## Who comes in, who gives up waiting, and Kofi getting on with it when you're not there.
func _people(delta: float) -> void:
	_next_in -= delta
	var wanted_here := not (_quiet and in_rush) and not (behind and not in_rush)     # all its customers, or waiting to start: people pass by
	if wanted_here and _next_in <= 0.0 and _queue.size() + _coming < QUEUE_SIZE and global_position.distance_to(player.global_position) < NEAR:
		_customer_arrives()
		var lull := _rng.randf() < LULL_CHANCE and not _queue.is_empty()
		_next_in = _rng.randf_range(LULL.x, LULL.y) if lull else _rng.randf_range(ARRIVE_EVERY.x, ARRIVE_EVERY.y)
	for c in _queue.duplicate():
		if c.is_walking(): continue
		c.patience -= delta
		if c.patience <= 0.0: _gives_up(c)
	if _kofi == null or in_rush or _queue.is_empty() or _queue[0].is_walking(): return
	_kofi_in -= delta
	if _kofi_in <= 0.0:
		_kofi_in = _rng.randf_range(KOFI_SERVES.x, KOFI_SERVES.y)
		var c: MarketCustomer = _queue[0]
		_kofi.reach()
		_kofi.walk([to_global(Vector3(float(_slots[c.item].x), 0.05, float(_slots[c.item].z)))] as Array[Vector3])
		shift.drop(c.order_id)
		_queue.erase(c)
		_move_queue_up()
		_customer_served(c)

func _kofi_moves() -> void:
	if in_rush: _kofi.walk([to_global(KOFI_ASIDE)] as Array[Vector3])
	_kofi_in = _rng.randf_range(KOFI_SERVES.x, KOFI_SERVES.y)

func _gives_up(c: MarketCustomer) -> void:
	shift.drop(c.order_id)
	_queue.erase(c)
	c.bubble.say(GIVE_UP[_rng.randi_range(0, GIVE_UP.size() - 1)])
	_leaves(c, 1.2)
	_move_queue_up()

func _exit_tree() -> void:
	if _hint: _hint.queue_free()
	if _screen: _screen.queue_free()
	if behind and player:
		player.rest_yaw = null
		player.rig.hold_view(null)

## Which way he stands behind the counter: towards the customer once he has what they want, or else square to it.
func _facing() -> float:
	if shift.held == "" or shift.held != shift.wanted(): return 0.0
	var to := _queue[0].position - player.global_position
	return atan2(to.x, to.z)

func _crate_at(p: Vector3) -> String:
	if not in_rush: return ""
	for item in _slots:
		if absf(p.x - float(_slots[item].x)) < CRATE_REACH: return item
	return ""

func _update_hint(crate: String) -> void:
	var text := ""
	var where := Vector3.ZERO
	if behind and not in_rush:
		var left := int(client.you.get("runs_left", 0))
		_hint.show_hint(KEY if left > 0 else "", ("Start a Market Rush · %d of %d left today" % [left, int(client.city.get("rush", {}).get("runs_per_day", 3))]) if left > 0
			else "No runs left today. More %s." % TownState.soon(TownState.left_ms(client.city.get("next_real_day_at"), client.now_ms())))
		_hint.at = global_position + global_basis * Vector3(0, 1.6, -0.6)
		return
	match shift.action(crate) if in_rush else StallShift.Do.NOTHING:
		StallShift.Do.TAKE:
			text = "Take " + str(ITEM_NAMES[crate]).to_lower()
			where = _crate_tops[crate]
		StallShift.Do.SWAP:
			text = "Swap for " + str(ITEM_NAMES[crate]).to_lower()
			where = _crate_tops[crate]
		StallShift.Do.PUT_BACK:
			text = "Put back"
			where = _crate_tops[crate]
		StallShift.Do.SERVE: pass     # the run's screen's "Hand it over" says it
	_hint.show_hint(KEY, text)
	_hint.at = where

func _unhandled_input(e: InputEvent) -> void:
	if not behind or not e.is_action_pressed("interact") or e.is_echo() or Screens.holding(): return
	if not in_rush and not Screens.free_to_open(): return     # a new run never starts under the phone or another screen
	get_viewport().set_input_as_handled()
	if in_rush: press()
	else: start_run()

## The key, behind the counter.
func press() -> void:
	var was_front: MarketCustomer = _queue[0] if not _queue.is_empty() else null
	var crate := _crate_at(to_local(player.global_position))
	var had := _carried
	match shift.press(crate):
		StallShift.Do.TAKE:
			player.avatar.reach(_crate_tops[crate])
			_take(shift.held, _crate_tops[crate])
		StallShift.Do.SWAP:
			player.avatar.reach(_crate_tops[crate])
			_carried = null
			_put_down(had, _crate_tops[crate])
			_take(shift.held, _crate_tops[crate])
		StallShift.Do.PUT_BACK:
			_carried = null
			player.avatar.set_carrying(false)
			player.avatar.reach(_crate_tops[crate], func(): _put_down(had, _crate_tops[crate]))
		StallShift.Do.REFUSE:
			player.avatar.reach(_chest(was_front))
			var want: String = ITEM_NAMES[shift.wanted()]
			was_front.bubble.say("No, %s!" % want.to_lower())
			get_tree().create_timer(1.1).timeout.connect(func():
				if is_instance_valid(was_front) and not _queue.is_empty() and _queue[0] == was_front: _show_orders())
		StallShift.Do.SERVE:
			_carried = null
			_queue.erase(was_front)
			_move_queue_up()
			player.avatar.reach(_chest(was_front), func():
				player.avatar.set_carrying(false)
				_put_down(had, _chest(was_front), func():
					client.send({"type": "ServeOrder"})
					_customer_served(was_front)))

func _chest(c: MarketCustomer) -> Vector3:
	return c.position + Vector3.UP * 0.75

## A new one of the item into his hand, coming from where it was taken.
func _take(item: String, from: Vector3) -> void:
	_carried = (_items[item] as Node3D).duplicate()
	_carried.visible = true
	player.avatar.set_carrying(true)
	player.avatar.hold(_carried, from)

## What he held leaves his hand for a point in the world, and is gone when it gets there.
func _put_down(item: Node3D, to: Vector3, then := Callable()) -> void:
	if item == null:
		if then.is_valid(): then.call()
		return
	var was := item.global_transform
	item.get_parent().remove_child(item)
	add_child(item)
	item.top_level = true
	item.global_transform = was
	var t := create_tween()
	t.tween_property(item, "global_position", to, ITEM_FLIGHT).set_trans(Tween.TRANS_SINE)
	t.tween_callback(item.queue_free)
	if then.is_valid(): t.tween_callback(then)

## What the server refused, with its numbers. Being told a run already stands as it should is just the two catching up after a
## drop. Nothing else can come of the commands sent from here, so anything more is a bug worth seeing.
func _on_refused(command: Dictionary, refusal: Dictionary) -> void:
	if not command.type in ["StartRush", "ServeOrder", "EndRush"]: return
	match refusal.type:
		"AlreadyInRush":
			if behind and not in_rush: _run_begins()     # one from before a drop is still running
		"NotInRush", "RushOver": _run_over()
		"NoRunsLeft": if cinema: cinema.say(Refusals.say(refusal, client.now_ms()), 4.0)
		"RushFull":                    # every customer this run has: the stall goes quiet until it ends, and nobody's told off
			if in_rush and not _quiet: cinema.say(RUSH_FULL, 4.0)
			_quiet = in_rush
		_: push_warning("stall: %s refused: %s" % [command.type, refusal])

## After a snapshot: the server's run is the run. One it remembers from before a drop goes on if he's still behind the counter.
func _reconcile_rush() -> void:
	var said := bool(client.you.get("in_rush", false))
	if said and not behind: client.send({"type": "EndRush"})
	elif said and not in_rush: _run_begins()
	elif not said and in_rush: _run_over()

## The next one steps up as soon as the order is filled.
func _move_queue_up() -> void:
	for i in _queue.size():
		var next: Array[Vector3] = [_spots[i]]
		_queue[i].walk(next)
	_show_orders()

## They have it: pleased, then off, and someone new comes in.
func _customer_served(c: MarketCustomer) -> void:
	var line: String = THANKS[_rng.randi_range(0, THANKS.size() - 1)]
	if line != "": c.bubble.say(line)
	else: c.bubble.clear()
	c.cheer()
	_leaves(c, CHEER)
	_next_in = minf(_next_in, _rng.randf_range(1.0, 4.0))

func _leaves(c: MarketCustomer, after: float) -> void:
	get_tree().create_timer(after).timeout.connect(func():
		if not is_instance_valid(c): return
		c.bubble.clear()
		var way: Array[Vector3] = [c.position + Vector3(1.4, 0, 0.8)]
		way.append_array(route_out)
		c.walk(way, c.queue_free))

## Someone comes in, and looks over the crates. Then they want something, or they don't.
func _customer_arrives() -> void:
	var c := _new_customer()
	c.position = route_in[0]
	_coming += 1
	var way: Array[Vector3] = route_in.duplicate()
	way.append(to_global(Vector3(_rng.randf_range(browse.position.x, browse.end.x), 0.05, _rng.randf_range(browse.position.y, browse.end.y))))
	c.walk(way, func():
		c.face(global_position)
		get_tree().create_timer(_rng.randf_range(BROWSE.x, BROWSE.y)).timeout.connect(func(): _decides(c)))

func _decides(c: MarketCustomer) -> void:
	_coming -= 1
	if _rng.randf() < JUST_LOOKING or _queue.size() >= QUEUE_SIZE:
		_leaves(c, 0.0)
		return
	var spot := _queue.size()
	_queue.append(c)
	c.item = _order_for(c)
	c.patience = _rng.randf_range(PATIENCE.x, PATIENCE.y)
	c.set_meta("patience", c.patience)   # the full wait, for the shift screen's bar
	c.walk([_spots[spot]] as Array[Vector3])
	_show_orders()
