class_name FoodCounter
extends Node3D
## The counter you eat at, standing up: the Common Table. One of each thing on the server's menu stands on the ledge with its live price in
## USDC, which moves with every meal anyone in town buys; the key opens the menu (ui/food_menu.gd) on what you stand at, with the free
## community thali at its head. A meal is paid for on chain (BuyMeal), and when the chain says it was eaten (MealEaten) you eat it there;
## the free thali (FreeMeal) and a rescue come the same way. What it costs and what it gives are the server's. Model and the named points
## read here: tools/blender/build_food.py.

const MODEL := preload("res://assets/market/food.glb")
const FRONT := Rect2(-3.1, 0.45, 6.2, 1.9)   # where you stand to buy (x, z from the counter's front edge)
const REACH := 0.6                 # m along the counter from a food's middle
const TAG_RANGE := 3.0             # m: a price shows only this close, or the room fills with tags
const TAG_OVER := 0.2              # m over the food
const HINT_OVER := 0.72            # m over the food: clear of its price tag and what stands behind
const LABELS := {"chai": "Chai", "vada_pav": "Vada pav", "thali": "Thali"}      # by the server's menu name
const MODEL_OF := {"chai": "chai", "vada_pav": "snack", "thali": "restaurant"}     # which of the model's foods stands for it
const KEY := "E"
const FOOD_SIZE := 1.3             # as his hands are large, the food is drawn to read at his scale
const EATING := 1.1                # s he holds it, eating, before it is gone

var player: CharacterBody3D
var client: TownClient
var paint := Callable()            # gives a model the town's materials

var _spots := {}                   # menu name -> Vector3 (world)
var _foods := {}                   # menu name -> the food on the ledge
var _tags := {}                    # menu name -> PriceTag
var _hint: KeyHint
var _here := false                 # standing at the counter
var _eating: Node3D
var food_menu := FoodMenu.new()

## tags: where the plates over things live (the world's UI layer).
func setup(tags: Control) -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	paint.call(model)
	var spots := {}
	var foods := {}
	for node in model.find_children("*", "Node3D", true, false):
		var label := String(node.name)
		if label.begins_with("Spot_"): spots[label.trim_prefix("Spot_")] = to_global((node as Node3D).position)
		elif label.begins_with("Food_"): foods[label.trim_prefix("Food_")] = node
	for item in MODEL_OF:
		if spots.has(MODEL_OF[item]) and foods.has(MODEL_OF[item]):
			_spots[item] = spots[MODEL_OF[item]]
			_foods[item] = foods[MODEL_OF[item]]
	for kind in foods:                 # what the menu doesn't sell isn't on the ledge
		if not kind in MODEL_OF.values(): (foods[kind] as Node3D).visible = false
	for food in _foods:
		(_foods[food] as Node3D).global_position = _spots[food]
		(_foods[food] as Node3D).scale = Vector3.ONE * FOOD_SIZE
		var tag := PriceTag.new()
		tag.at = (_spots[food] as Vector3) + Vector3.UP * TAG_OVER
		tags.add_child(tag)
		_tags[food] = tag
	_hint = KeyHint.new()
	tags.add_child(_hint)
	food_menu.client = client
	food_menu.player = player
	tags.add_child(food_menu)
	client.event.connect(_on_event)

func _process(_delta: float) -> void:
	if player == null: return
	var p := to_local(player.global_position)
	var here := FRONT.has_point(Vector2(p.x, p.z))
	if here != _here:
		_here = here
		player.rest_yaw = PI if here else null
		player.rig.hold_view(0.0 if here else null)
	_show_prices()
	var food := _food_at(p)
	if food != "" and not food_menu.is_open:
		_hint.show_hint(KEY, "Menu")
		_hint.at = (_spots[food] as Vector3) + Vector3.UP * HINT_OVER
	else:
		_hint.show_hint("", "")

func _food_at(p: Vector3) -> String:
	if not _here: return ""
	for food in _spots:
		if absf(p.x - to_local(_spots[food]).x) < REACH: return food
	return ""

## Each price from the menu as the server last sent it, and its way since yesterday.
func _show_prices() -> void:
	var menu := {}
	for m in client.city.get("menu", []): menu[m.name] = m
	for food in _tags:
		var near := player.global_position.distance_to(_spots[food]) < TAG_RANGE
		if not near or not menu.has(food):
			_tags[food].clear()
			continue
		var price := int(menu[food].price)
		_tags[food].show_price(LABELS[food], price, price - int(menu[food].get("was", price)))

func _unhandled_input(e: InputEvent) -> void:
	if _here and Screens.free_to_open() and e.is_action_pressed("interact"): press()     # never over the phone or another screen

## The key at the counter: the menu, on what he stands at. The meal comes when the server says it was paid for.
func press() -> void:
	food_menu.open(_food_at(to_local(player.global_position)))

func _on_event(e: Dictionary) -> void:
	if str(e.get("account", "")) != client.player: return
	match str(e.type):
		"MealEaten":
			food_menu.close()
			if _spots.has(e.item) and _here: _eat(e.item)
		"FreeMealEaten":
			food_menu.close()
			if _here: _eat("thali")

## It comes from the ledge to his hand, and he eats it where he stands.
func _eat(food: String) -> void:
	if is_instance_valid(_eating): _eating.queue_free()
	player.avatar.reach(_spots[food])
	_eating = (_foods[food] as Node3D).duplicate()
	player.avatar.set_carrying(true)
	player.avatar.hold(_eating, _spots[food])
	for t in [0.35, 0.8]:
		get_tree().create_timer(t).timeout.connect(func(): if is_instance_valid(_eating): player.avatar.bite())
	var bite := _eating.get_instance_id()       # by id: a second meal may free this one first
	get_tree().create_timer(EATING).timeout.connect(func():
		var held = instance_from_id(bite)
		if is_instance_valid(held):
			held.queue_free()
			if _eating == held: player.avatar.set_carrying(false))
