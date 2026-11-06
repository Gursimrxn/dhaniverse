class_name Opening
extends Node3D
## How a new player arrives. Dawn, on the ferry. It comes in under the title, and when they choose a new life the deck is theirs (with no
## title, a few seconds of film and they walk it as it comes in); at the rail they write their name on the ticket. On the landing the harbourmaster greets them by that name
## and hands over Gran's letter, and they read it. That they have is kept on this machine (`keep`), so a crash picks up at the letter.
## The ferry and the jetty stand here for good.

signal finished
signal alongside                   # the ferry has reached the jetty

const FERRY := preload("res://assets/market/ferry.glb")
const JETTY := preload("res://assets/market/jetty.glb")
const DECK_Y := -0.55              # jetty and ferry deck: 0.65 m over the river here
const JETTY_AT := Vector3(-104.0, DECK_Y, 49.0)
const FERRY_DOCK := Vector3(-125.85, DECK_Y, 47.5)   # its side gap against the jetty's head
const FERRY_DOCK_YAW := -PI * 0.5  # its bow (+X) downstream
const KEEPER_AT := Vector2(-100.6, 49.0)
# down the middle of the river, slowing into the jetty
const ROUTE: Array[Vector3] = [Vector3(-142.0, DECK_Y, -22.0), Vector3(-138.0, DECK_Y, -5.0), Vector3(-133.0, DECK_Y, 13.0), Vector3(-127.5, DECK_Y, 32.0), FERRY_DOCK]
const RIDE := 22.0                 # s on the water
const RIDE_NAMED := 2.5            # how much faster it comes in once there's nothing left to do on board
const FILM := 5.5                  # s before the player has the deck
const PORT_LAND := 1.8             # s from the title's shot down to the deck
const ON_DECK :=Vector3(2.4, 0.05, 0.0)   # where he starts: on the foredeck, clear of the cabin's roof
const AT_RAIL_BOW := 3.5           # m along the deck: he's reached the rail
const AT_RAIL_SIDE := 1.45         # m across it, on either side
const BOB := 0.03                  # m
const TALK_AT := 3.1               # m from the harbourmaster
const HINT_AFTER := 6.0             # s standing still on the deck before it's worth saying how to walk
const LETTER_AFTER := 2.2          # s from him speaking to the letter being read
const AFTER_SKY := 10.0            # s the morning takes to come up after the letter
const GREET := "Morning, %s. I've something for you. From your gran."
const CALL := "Over here, %s!"
const AFTER_LETTER := "She was a good one, %s. Kofi at the Market Hall could use a hand, past the bank."
const READ := "read_gran_letter"   # the setting that says the letter's been read

var world: Node3D
var player: CharacterBody3D
var client: TownClient
var keeper: Harbourmaster
var director: Director
var cinema: Cinema
var sound: Sound
var plates: Array = []             # what's hidden on screen until the letter's read
var paint := Callable()
var keep := Callable()             # f(key, value): kept on this machine for next time (world.gd's settings)

var ferry: Node3D
var ticket: FerryTicket
var letter: GranLetter
var playing := false
var aboard := false                # the player rides in with the ferry without having the deck yet: under the title
var step := ""                     # where it's got to: film, deck, ticket, ashore, handing, letter, ""
var _ride_u := 1.0
var _named := false
var _walk_hint: KeyHint
var _hint_gone := false
var _still_for := 0.0
var _called_for := 0.0
var _mode_was := ""

func setup(tags: Control) -> void:
	var jetty: Node3D = JETTY.instantiate()
	add_child(jetty)
	paint.call(jetty)
	jetty.global_position = JETTY_AT
	ferry = FERRY.instantiate()
	add_child(ferry)
	paint.call(ferry)
	_moor()
	keeper.global_position = Vector3(KEEPER_AT.x, world.height_at(KEEPER_AT.x, KEEPER_AT.y), KEEPER_AT.y)
	ticket = FerryTicket.new()
	ticket.client = client
	tags.add_child(ticket)
	ticket.named.connect(_on_named)
	letter = GranLetter.new()
	tags.add_child(letter)
	letter.read.connect(_finish)
	_walk_hint = KeyHint.new()
	tags.add_child(_walk_hint)
	client.synced.connect(_on_synced)
	client.hello_refused.connect(_on_hello_refused)

func _moor() -> void:
	ferry.global_position = FERRY_DOCK
	ferry.rotation.y = FERRY_DOCK_YAW
	ferry.reset_physics_interpolation()

# --- the whole thing, for someone new ----------------------------------------------------------------------------------------
func play() -> void:
	_begin()
	world.set_time_mode("dawn", true)
	step = "film"
	_ride_u = 0.0
	player.frozen = true
	_place_on_deck()
	await get_tree().process_frame     # the screen's size is known from here
	cinema.wipe_open()
	cinema.bars_in()
	cinema.card("Tallyport", "", "", FILM - 2.2)
	director.skipped.connect(_end_film, CONNECT_ONE_SHOT)
	await director.follow(_film_shot, FILM, 36.0)
	if step == "film": _end_film()

## The ferry came in under the title: the camera comes down from that shot to the deck, and it's theirs from there.
func play_from_port(mode_was: String) -> void:
	_begin()
	_mode_was = mode_was
	step = "deck"
	player.frozen = false
	cinema.bars_out()
	director.land(PORT_LAND)
	_called_for = 0.0

## Straight to the jetty, for a player who skips the ride.
func come_in_now() -> void:
	if _ride_u >= 1.0: return
	_ride(1.0)
	player.global_position = ferry.global_transform * ON_DECK
	player.reset_physics_interpolation()
	_alongside()

func _begin() -> void:
	playing = true
	_mode_was = world.mode
	world._lapsing = true
	for p in plates: p.modulate.a = 0.0

func _place_on_deck() -> void:
	_ride(0.0)
	ferry.reset_physics_interpolation()
	player.global_position = ferry.global_transform * ON_DECK
	player.reset_physics_interpolation()
	player.rig.yaw = -PI * 0.5         # across the deck to the town, the sun coming up behind it
	player.rig.pitch = deg_to_rad(-8.0)

## From across the water with the sun coming up behind the town, closing in a little as it comes on.
func _film_shot(u: float) -> Array:
	var f: Vector3 = ferry.get_global_transform_interpolated().origin    # where it's drawn this frame: its raw position only moves on physics ticks, and the camera would judder against it
	var eye := f + Vector3(-15.0, 1.5, -17.0).lerp(Vector3(-13.0, 1.6, -15.0), Director.eased(u))
	return [eye, f + Vector3(1.5, 4.0, 2.0)]     # the ferry low in the frame, the title over the sky

func _end_film() -> void:
	if step != "film": return
	step = "deck"
	player.frozen = false
	cinema.bars_out()
	director.land(1.0)
	_called_for = 0.0

func _physics_process(delta: float) -> void:
	if _ride_u >= 1.0: return
	var was: Transform3D = ferry.global_transform
	_ride(minf(_ride_u + delta / RIDE * (RIDE_NAMED if _named else 1.0), 1.0))
	# he's carried with the deck, walking or not
	if playing or aboard: player.global_position = ferry.global_transform * (was.affine_inverse() * player.global_position)
	if _ride_u >= 1.0: _alongside()

func _ride(u_in: float) -> void:
	_ride_u = u_in
	var u := 1.0 - pow(1.0 - _ride_u, 1.7)      # steady, then slowing in
	var at := Director.along(ROUTE, u)
	var next := Director.along(ROUTE, minf(u + 0.01, 1.0))
	ferry.rotation.y = lerp_angle(atan2(-(next.z - at.z), next.x - at.x), FERRY_DOCK_YAW, smoothstep(0.86, 1.0, u))
	ferry.global_position = at + Vector3.UP * (BOB * sin(_ride_u * 40.0) * (1.0 - u))

## The ferry comes in again, with whoever and whatever's on it.
func ferry_arrives() -> void:
	_named = true                      # at the quicker pace
	_ride(0.55)
	ferry.reset_physics_interpolation()

func _alongside() -> void:
	_moor()
	aboard = false
	sound.play("ferry_horn", -10.0)
	alongside.emit()

func _process(delta: float) -> void:
	if not playing: return
	match step:
		"deck":
			var l: Vector3 = ferry.global_transform.affine_inverse() * player.global_position
			if not _hint_gone:
				_still_for = 0.0 if player.velocity.length() > 0.5 else _still_for + delta
				if _still_for > HINT_AFTER:
					_walk_hint.at = player.global_position + Vector3.UP * 1.85
					_walk_hint.show_hint("W", "Walk")
				if ON_DECK.distance_to(l) > 0.6:
					_hint_gone = true
					_walk_hint.show_hint("", "")
			if l.x > AT_RAIL_BOW or absf(l.z) > AT_RAIL_SIDE or l.x < -0.2:
				_open_ticket()
		"ashore":
			_called_for -= delta
			if _called_for <= 0.0 and _ride_u >= 1.0:
				_called_for = 9.0
				keeper.say(CALL % client.player, 3.0)
				keeper.wave()
			if _to_keeper() < TALK_AT: _meet_keeper()

func _to_keeper() -> float:
	return Vector2(player.global_position.x - keeper.global_position.x, player.global_position.z - keeper.global_position.z).length()

func _open_ticket() -> void:
	step = "ticket"
	_walk_hint.show_hint("", "")
	_hint_gone = true
	player.frozen = true
	sound.play("paper")
	ticket.open()

func _on_named(who: String) -> void:
	keep.call("player_name", who)
	ticket.close()
	player.frozen = false
	_named = true
	step = "ashore"
	_called_for = 0.0

func _on_synced() -> void:
	if step == "ticket" and not _named: ticket.accept()

## A saved name that won't do any more: a new ticket, then on with the landing.
func _on_hello_refused(_refusal: Dictionary) -> void:
	if playing: return
	_begin()
	client.connect_nameless()
	_to_landing()
	_open_ticket()

func _to_landing() -> void:
	player.global_position = keeper.global_position + Vector3(-TALK_AT - 1.5, 0.3, 0.0)
	player.rig.yaw = -PI * 0.5
	world.set_time_mode("dawn", true)

## Someone with a name who hasn't read the letter yet came back: straight to the harbourmaster and the letter.
func resume() -> void:
	_begin()
	_to_landing()
	_meet_keeper()

## In a short shot from the side, with the landing behind him: he greets them by name and hands it over.
func _meet_keeper() -> void:
	step = "handing"
	player.frozen = true
	var to := keeper.global_position - player.global_position
	player.rest_yaw = atan2(to.x, to.z)
	player.rig.hold_view(atan2(-to.x, -to.z))
	cinema.bars_in()
	# over his shoulder, the harbourmaster small against the landing: this is about the place, not their faces
	var along := to.normalized()
	var side := along.cross(Vector3.UP)
	var back: Vector3 = player.global_position - along * 3.4 + side * 1.3
	director.fly([back + Vector3.UP * 1.9, back + along * 0.5 + Vector3.UP * 1.8], [keeper.global_position + Vector3.UP * 1.0, keeper.global_position + Vector3.UP * 1.0], 9.0, 42.0, false)
	keeper.say(GREET % client.player, LETTER_AFTER + 0.6)
	await get_tree().create_timer(LETTER_AFTER * 0.5).timeout
	keeper.hand_over()
	sound.play("paper")
	await get_tree().create_timer(LETTER_AFTER * 0.5).timeout
	if step != "handing": return
	step = "letter"
	letter.open(client.player)

## Has this machine seen the letter read?
func has_read() -> bool:
	return bool(world._setting(READ, false))

## The letter's folded away: he says a word, the morning comes up, and the plates with it.
func _finish() -> void:
	if not playing: return
	playing = false
	step = ""
	keep.call(READ, true)
	letter.close()
	keeper.say(AFTER_LETTER % client.player, 7.0)
	cinema.bars_out()
	director.land()
	player.frozen = false
	player.rest_yaw = null
	player.rig.hold_view(null)
	world.ease_to_mode(_mode_was if _mode_was != "dawn" else "day", AFTER_SKY)
	keeper.going_about = true
	for p in plates: create_tween().tween_property(p, "modulate:a", 1.0, 1.4).set_delay(0.8)
	finished.emit()
