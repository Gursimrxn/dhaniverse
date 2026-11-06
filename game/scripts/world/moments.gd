class_name Moments
extends Node
## The town's big moments, each directed once and driven by what the server says happened. Every one is skippable, and takes the
## player's control for under 6 s. Camera: Director. Framing and words: Cinema. If they're busy (a paper open, the opening, a Market
## Rush run with something in hand), the moment passes without the camera: nobody loses a thing they were doing to a cutscene.

const OVER_TOWN := Vector3(-22.0, 34.0, -48.0)       # high over the market end, looking back down the town
const TOWN_MIDDLE := Vector3(-30.0, 2.0, 8.0)
const WAIT_TURN := 6.0             # s a moment waits for whatever's on screen to finish, before it lets the shot go
const ESTABLISH := 2.6             # s a first look at a place takes
const FERRY_SHOT := 2.3
# the first time in each place: a look round it that lands behind him. No bars: it isn't a story beat, it's arriving. eyes, then what they look at
const PLACES := {
	"hall": [[Vector3(-20.0, 1.9, -15.5), Vector3(-20.0, 4.6, -24.0)], [Vector3(-20.0, 2.4, -33.0), Vector3(-15.0, 0.9, -28.0)]],
	"bank": [[Vector3(-27.0, 2.0, 9.6), Vector3(-30.5, 2.7, 13.0)], [Vector3(-27.0, 2.2, 20.0), Vector3(-24.0, 1.3, 18.0)]],
	"table": [[Vector3(8.8, 1.7, 11.0), Vector3(11.5, 2.4, 14.0)], [Vector3(16.0, 1.6, 21.0), Vector3(18.0, 0.9, 13.0)]],
	"court": [[Vector3(-8.0, 7.5, 72.0), Vector3(-8.0, 3.4, 78.5)], [Vector3(-8.0, 3.0, 90.0), Vector3(-8.0, 2.4, 88.0)]],
	"landing": [[Vector3(-108.0, 3.2, 53.0), Vector3(-103.0, 1.8, 54.0)], [Vector3(-92.0, 1.2, 44.0), Vector3(-92.0, 1.4, 48.0)]],
}
const LANDING_RECT := Rect2(-103.0, 40.0, 19.0, 19.0)
const COURT_RECT := Rect2(-26.0, 74.0, 36.0, 22.0)
# a season's shock (PROTOCOL.md): its banners, its words, and world.gd's SEASONS look for the trees
const SHOCK_COLOURS := {"": Color("2f7c7a"), "harvest": Color("d9a441"), "festival": Color("e07a3a"), "drought": Color("b5835a")}
const SHOCKS := {"harvest": "A good harvest", "festival": "Festival", "drought": "Dry weather up the river"}
const SEASON_LOOKS := {"": 1, "harvest": 3, "festival": 2, "drought": 2}
const SEASON_FOR := 5.0

var world: Node3D
var client: TownClient
var player: CharacterBody3D
var director: Director
var cinema: Cinema
var sound: Sound
var _running := false
var running: bool:
	get: return _running
var _skipped := false              # the last shot was skipped: the rest of its cuts go too
var _seen_now := {}

func _ready() -> void:
	client.event.connect(_on_event)
	director.skipped.connect(func(): _skipped = true)

func _process(_delta: float) -> void:
	_first_look()

## Kept with the player's settings.
func _seen(place: String) -> bool:
	return _seen_now.has(place) or bool(world._setting("seen_" + place, false))

func _mark_seen(place: String) -> void:
	_seen_now[place] = true
	world._save_setting("seen_" + place, true)

## In a place for the first time.
func _first_look() -> void:
	if not world.cinematic_on or not client.up or not _free_to_play() or not client.you.has("name"): return
	var p: Vector3 = player.global_position
	var place := ""
	match world.room_at(p):
		0: place = "bank"
		1: place = "hall"
		2: place = "table"
		-1:
			if COURT_RECT.has_point(Vector2(p.x, p.z)): place = "court"
			elif LANDING_RECT.has_point(Vector2(p.x, p.z)): place = "landing"
	if place == "" or _seen(place): return
	_mark_seen(place)
	var shot: Array = PLACES[place]
	director.keys_pass_through = true
	await director.fly(shot[0], shot[1], ESTABLISH, 44.0)
	director.keys_pass_through = false
	director.land(0.9)

func _free_to_play() -> bool:
	if _running or player.frozen or world.opening.playing or director.busy or world.blast.playing: return false
	return not world.stall.in_rush or world.stall.shift.held == ""

## Wait for the screen to be free: a blast or another moment finishes first. False if it never comes, or the player has turned these off.
func _my_turn() -> bool:
	if not world.cinematic_on: return false
	var left := WAIT_TURN
	while left > 0.0 and not _free_to_play():
		await get_tree().create_timer(0.1).timeout
		left -= 0.1
	return _free_to_play()

func _on_event(e: Dictionary) -> void:
	if e.type == "SeasonChanged": _season(int(e.season), str(e.shock))

## The town changes with the season: its trees, and a word on what's coming.
func _season(number: int, shock: String) -> void:
	world.set_season_look(int(SEASON_LOOKS.get(shock, 1)))
	world.put_up_banners(SHOCK_COLOURS.get(shock, SHOCK_COLOURS[""]))
	if shock == "festival": world.town_reacts(false)
	sound.play("bell", -8.0)
	if not await _my_turn(): return
	_begin()
	_skipped = false
	cinema.bars_in()
	# the ferry coming in with what the season's bringing; then the town, dressed for it
	world.opening.ferry_arrives()
	var deck: Vector3 = world.opening.JETTY_AT
	await director.fly([deck + Vector3(-5.0, 1.0, -3.4), deck + Vector3(-7.5, 1.3, -3.2)], [deck + Vector3(-22.0, 1.4, -6.0), deck + Vector3(-21.0, 1.2, -1.5)], FERRY_SHOT, 40.0)
	if not _skipped:
		cinema.card("Season %d" % number, "", str(SHOCKS.get(shock, "")), SEASON_FOR - FERRY_SHOT - 0.6)
		await director.fly([OVER_TOWN + Vector3(10.0, -22.0, 24.0), OVER_TOWN], [TOWN_MIDDLE, TOWN_MIDDLE], SEASON_FOR - FERRY_SHOT, 44.0)
	await _end()

func _begin() -> void:
	_running = true
	player.frozen = true

func _end() -> void:
	cinema.bars_out()
	await director.land(0.8)
	player.frozen = false
	_running = false
