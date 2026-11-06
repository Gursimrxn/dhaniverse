class_name Sound
extends Node
## What the town sounds like: one loop per kind of place faded by where the player is, quiet music by time of day, and a sound for
## each thing that happens. Files: game/assets/audio (tools/make_audio.js, all original).

const DIR := "res://assets/audio/%s.wav"
const LOOPS := ["amb_town", "amb_water", "amb_market", "amb_table", "amb_bank"]
const ROOM_LOOPS := {0: "amb_bank", 1: "amb_market", 2: "amb_table"}   # by the index in world.gd's ROOMS; the others are quiet rooms
const LOUD := {"amb_town": -15.0, "amb_water": -13.0, "amb_market": -11.0, "amb_table": -12.0, "amb_bank": -14.0}   # dB at full
const MUSIC_DB := -17.0
const OFF_DB := -60.0
const FADE := 1.6                  # s for a place to take over
const MUSIC_FADE := 3.5
const WATER_NEAR := 4.0            # m from the river: as loud as it gets
const WATER_FAR := 34.0            # m: gone
const COIN_EVENTS := ["OrderServed", "MealEaten"]     # the till: an order handed over, a meal paid for
const SAME_SOUND_GAP := 0.28       # s: the same sound again sooner than this is dropped
const STREAK_WITHIN := 1.6         # s: a sound repeating this soon is a run of them (orders handed over in a hurry)
const STREAK_EVERY := 3            # in a run, only every third is heard, quieter: the first says it, the rest are a trickle
const STREAK_QUIETER := 7.0        # dB
const PITCH_SPREAD := 0.06         # so no two are quite the same
const STEP_DB := -19.0
const STEP_HEAVY_DB := 5.0         # how much louder at a full run
const STEP_FILES := {"stone": 3, "grass": 3, "wood": 3}
const MUSIC_FOR := {"dawn": "music_dawn", "day": "music_day", "evening": "music_day", "night": "music_night"}

var world: Node3D
var _loops := {}                   # name -> AudioStreamPlayer
var _music: Array[AudioStreamPlayer] = []
var _music_on := 0                 # which of the two is playing
var _music_name := ""
var _once := {}
var _was_indoors := false
var _last_played := {}             # a sound -> when it last played (ms)
var _streak := {}                  # a sound -> how long its run has been
var played := {}                   # a sound -> how many times (dev)

func _ready() -> void:
	for n in LOOPS:
		var p := _player(n, true)
		p.volume_db = OFF_DB
		p.play(randf() * 4.0)
		_loops[n] = p
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = OFF_DB
		add_child(m)
		_music.append(m)
	world.client.event.connect(_on_event)
	world.player.footstep.connect(_footstep)

## A foot came down, on whatever's there.
func _footstep(at: Vector3, heavy: float) -> void:
	var surface: String = world.surface_at(at)
	var p := AudioStreamPlayer.new()
	p.stream = _load("step_%s_%d" % [surface, randi_range(1, int(STEP_FILES[surface]))], false)
	p.volume_db = STEP_DB + heavy * STEP_HEAVY_DB
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _player(file: String, loop := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _load(file, loop)
	p.bus = _bus_for(file)
	add_child(p)
	return p

func _load(file: String, loop: bool) -> AudioStreamWAV:
	var s: AudioStreamWAV = load(DIR % file)
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s

## One thing that happens. The same sound may overlap itself.
func play(file: String, db := -4.0) -> void:
	var now := Time.get_ticks_msec()
	var since := now - int(_last_played.get(file, -100000))
	if since < int(SAME_SOUND_GAP * 1000.0): return
	_last_played[file] = now
	_streak[file] = int(_streak.get(file, 0)) + 1 if since < int(STREAK_WITHIN * 1000.0) else 0
	if int(_streak[file]) > 0:
		if int(_streak[file]) % STREAK_EVERY != 0: return
		db -= STREAK_QUIETER
	played[file] = int(played.get(file, 0)) + 1
	if not _once.has(file):
		_once[file] = AudioStreamPlayer.new()
		_once[file].stream = _load(file, false)
		_once[file].bus = _bus_for(file)
		_once[file].max_polyphony = 4
		add_child(_once[file])
	_once[file].volume_db = db
	_once[file].pitch_scale = randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	_once[file].play()

func _on_event(e: Dictionary) -> void:
	# your own, nobody else's
	if e.type in COIN_EVENTS and str(e.get("account", "")) == world.client.player: play("coin", -8.0)

func _process(delta: float) -> void:
	var p: Vector3 = world.player.global_position
	var room: int = world.room_at(p)
	var indoors: bool = room >= 0
	if indoors != _was_indoors:
		_was_indoors = indoors
		play("door", -10.0)
	var want := {}
	if indoors:
		if ROOM_LOOPS.has(room): want[ROOM_LOOPS[room]] = 1.0
	else:
		want["amb_town"] = 1.0
		want["amb_water"] = 1.0 - smoothstep(WATER_NEAR, WATER_FAR, world.data.water_sd(Vector2(p.x, p.z)))
	for n in _loops:
		var k: float = want.get(n, 0.0)
		var target: float = lerpf(OFF_DB, LOUD[n], pow(k, 0.25)) if k > 0.001 else OFF_DB
		_loops[n].volume_db = move_toward(_loops[n].volume_db, target, delta * absf(OFF_DB) / FADE)
	_update_music(delta)

func _update_music(delta: float) -> void:
	var name_: String = MUSIC_FOR.get(world.mode, "music_day")
	if name_ != _music_name:
		_music_name = name_
		_music_on = 1 - _music_on
		_music[_music_on].stream = _load(name_, true)
		_music[_music_on].play()
	var step: float = delta * absf(OFF_DB) / MUSIC_FADE
	_music[_music_on].volume_db = move_toward(_music[_music_on].volume_db, MUSIC_DB, step)
	var other := _music[1 - _music_on]
	other.volume_db = move_toward(other.volume_db, OFF_DB, step)
	if other.playing and other.volume_db <= OFF_DB + 0.5: other.stop()

const BUSES := ["Music", "Town", "Effects"]

func _bus_for(file: String) -> StringName:
	_make_buses()
	if file.begins_with("music"): return &"Music"
	if file.begins_with("amb"): return &"Town"
	return &"Effects"

func _make_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)

## The player's levels, 0 to 1 each.
func set_volumes(music: float, town: float, effects: float) -> void:
	_make_buses()
	for pair in [["Music", music], ["Town", town], ["Effects", effects]]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(pair[0]), linear_to_db(maxf(pair[1], 0.0001)))
