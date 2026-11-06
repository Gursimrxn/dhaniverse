class_name TownClient
extends Node
## The game's only way to the rules: the Rust server, over a WebSocket (server/PROTOCOL.md). Commands go in through send();
## what happened comes back as signals, and `you` and `city` are always the last the server sent. The client never works a
## number out for itself. A command waits until its result: after a drop it is sent again with the same ref, so nothing
## counts twice. The exported game starts the server beside it; a run from the editor expects one already listening.

signal synced                      # a snapshot arrived: everything was replaced
signal event(e: Dictionary)        # something happened: stage it
signal you_changed
signal city_changed
signal refused(command: Dictionary, refusal: Dictionary)
signal link_changed(up: bool)
signal hello_refused(refusal: Dictionary)   # that name won't do: nothing connects until there's another
signal presence(players: Array)
signal left(name_: String)
signal answered(ref: String, ok: bool)   # a command has its result
signal rehearsed                   # a rehearsal action is done, its events already in
signal replied(command: Dictionary, reply: Dictionary)   # a command went through, with its whole result (TownPass's `url` rides on it)
signal profiled(card: Dictionary)  # a profile asked for with ask_profile()
signal server_said(message: String)   # an `error`: always a client bug, or a rehearsal that couldn't be done

const PROTOCOL := 3
const DEFAULT_URL := "ws://127.0.0.1:7878"
const SERVER_EXE := "dhaniverse-server.exe"
const SERVER_FILE := "server_url.txt"   # beside the game: the town to join, unless told otherwise
const RETRY_EVERY := 2.0           # s between tries while the server can't be reached

var you := {}
var city := {}
var up := false                    # connected and synced
var debug := false                 # a rehearsal server: rehearse() works on it
var town_pass := false             # this town stamps Town Passes (World ID, or a rehearsal): everyone shows one before coming ashore
var player := ""                   # who this is: nothing connects until there is a name
var secret := ""                   # proves it, to the server: made once, kept on this machine
var _nameless := false             # connected with no name yet: all it can do is claim one
var trying: bool:                  # it means to be connected: with a name, or nameless for the ticket
	get: return player != "" or _nameless or kicked
var url := DEFAULT_URL
var _ws: WebSocketPeer
var _said_hello := false
var kicked := false                # another window took this name: stop trying, or the two would fight over it
var _retry_in := 0.0
var _pending: Array[Dictionary] = []   # {ref, command}, oldest first: sent or waiting to be, until their result
var _session := str(int(Time.get_unix_time_from_system()))   # refs work once, and a save outlives a run
var _count := 0
var _server_pid := -1
var feed: Array = []               # the snapshot's latest posts, oldest first; new ones come as FeedPost events
var _now_said := 0.0               # city.now_ms as last said (the real clock), and when it was said here
var _now_heard := 0
var payments: Array[Dictionary] = []   # this session's money that moved on chain, newest first: {what, usdc, tx, item}
const PAYMENTS_KEPT := 12

func _ready() -> void:
	url = _configured_url()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--player="): player = a.trim_prefix("--player=")
		elif a.begins_with("--server-url="): url = a.trim_prefix("--server-url=")
	_start_server()

func _exit_tree() -> void:
	if _server_pid > 0: OS.kill(_server_pid)

## Which town. In a browser: ?server=wss://... on the page, or the page's own DHANIVERSE_SERVER. Otherwise a file beside the game. Only
## with none of these does it fall back to a server of its own on this machine.
func _configured_url() -> String:
	if OS.has_feature("web"):
		var from_page = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || window.DHANIVERSE_SERVER || ''")
		if str(from_page) != "": return str(from_page)
		return DEFAULT_URL
	var file := OS.get_executable_path().get_base_dir().path_join(SERVER_FILE)
	if FileAccess.file_exists(file):
		var from_file := FileAccess.get_file_as_string(file).strip_edges()
		if from_file != "": return from_file
	return DEFAULT_URL

## In an exported game, the server sits beside it. Its save goes with the game's own data. If one is already listening, this
## one finds the port taken and exits, and the client talks to the one that was there.
func _start_server() -> void:
	var dir := OS.get_executable_path().get_base_dir()
	if not OS.has_feature("template") or not FileAccess.file_exists(dir.path_join(SERVER_EXE)): return
	if url != DEFAULT_URL: return      # joining a town on another machine
	var save := ProjectSettings.globalize_path("user://city.jsonl")
	# a save a newer server can't replay is moved aside and a new city starts, so a new build never locks the player out
	_server_pid = OS.create_process(dir.path_join(SERVER_EXE), ["--addr", "0.0.0.0:7878", "--save", save, "--rules", dir.path_join("rules.toml"), "--new-if-incompatible"])

## The player's name is known: it's who to say hello as.
func start(name_: String, secret_ := "") -> void:
	player = name_
	secret = secret_
	_nameless = false
	_drop_quietly()

## A new player: connect with no name, so the ticket can claim one.
func connect_nameless() -> void:
	player = ""
	_nameless = true
	_drop_quietly()

## Where this body is, for the others to see. It isn't game state and gets no answer.
func move(m: Dictionary) -> void:
	if up and player != "": _write(m)

func _drop_quietly() -> void:
	if _ws:
		_ws.close()
		_ws = null
	_retry_in = 0.0

## Ask for something. It goes now, or as soon as the link is back. Returns its ref.
func send(command: Dictionary) -> String:
	_count += 1
	var ref := "%s-%s-%d" % [player, _session, _count]
	_pending.append({"ref": ref, "command": command})
	if up: _write_command(_pending.back())
	return ref

## Rehearsal only (snapshot.debug): Skip, NextSeason, ReadyChest, Fund, FundBucket, PassTown, NewCampaign (PROTOCOL.md), standing in
## for time, a faucet, World ID and a sponsor. Nothing waits for it or retries it: a fresh `you` and `rehearsed` follow.
func rehearse(action: Dictionary) -> void:
	if up and debug: _write({"type": "debug", "action": _whole(action)})

## Someone's public card (PROTOCOL.md, profiles): it comes back on `profiled`.
func ask_profile(name_: String) -> void:
	if up and player != "": _write({"type": "profile", "name": name_})

## The real clock (city.now_ms) as it is now: the server's last word, counted on here between its words. Every `*_at` is on it.
func now_ms() -> int:
	if city.is_empty(): return 0
	return int(_now_said) + (Time.get_ticks_msec() - _now_heard)

func _heard_clock(now) -> void:
	if now == null: return
	_now_said = float(now)
	_now_heard = Time.get_ticks_msec()

func _write_command(p: Dictionary) -> void:
	_write({"type": "command", "ref": p.ref, "command": _whole(p.command)})

## Numbers read from the server's JSON are floats here, and the server wants its whole numbers whole.
static func _whole(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d: out[k] = int(d[k]) if d[k] is float and d[k] == floorf(d[k]) else d[k]
	return out

func _write(m: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN: _ws.send_text(JSON.stringify(m))

func _process(delta: float) -> void:
	if kicked or (player == "" and not _nameless): return
	if _ws == null:
		_retry_in -= delta
		if _retry_in <= 0.0: _connect()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _said_hello:
				_said_hello = true
				if _nameless: _write({"type": "hello", "protocol": PROTOCOL, "secret": secret})
				else: _write({"type": "hello", "protocol": PROTOCOL, "player": player, "secret": secret})
			while _ws and _ws.get_available_packet_count() > 0:     # what it says may close it
				var m = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if m is Dictionary: handle_message(m)
		WebSocketPeer.STATE_CLOSED:
			_dropped()

func _connect() -> void:
	_ws = WebSocketPeer.new()
	_said_hello = false
	if _ws.connect_to_url(url) != OK: _dropped()

func _dropped() -> void:
	_ws = null
	_retry_in = RETRY_EVERY
	if up:
		up = false
		link_changed.emit(false)

## One message from the server.
func handle_message(m: Dictionary) -> void:
	match str(m.get("type", "")):
		"snapshot":
			you = m.you
			city = m.city
			_heard_clock(city.get("now_ms"))
			feed = m.get("feed", [])
			debug = bool(m.get("debug", false))
			town_pass = bool(m.get("town_pass", false))
			var was_up := up
			var waiting := _pending.duplicate()     # what is sent in answer to `synced` below goes first, and only once
			if _nameless:                 # this is the claim being answered: its result follows, and from now on this is who we are
				_nameless = false
				player = str(you.name)
				waiting.clear()
			up = true
			if not was_up:
				print("server: connected at %s as %s, protocol %d, energy %d%s" % [url, player, PROTOCOL, int(you.get("energy", 0)), ", rehearsal" if debug else ""])
				link_changed.emit(true)
			synced.emit()
			for p in waiting: _write_command(p)
		"event":
			_note_payment(m.event)
			event.emit(m.event)
		"you":
			you = m.you
			you_changed.emit()
		"city":
			city = m.city
			_heard_clock(city.get("now_ms"))
			city_changed.emit()
		"time":
			if not city.is_empty():
				city.day = m.day
				city.day_ms = m.day_ms
				city.day_elapsed_ms = m.day_elapsed_ms
				if m.has("now_ms"):
					city.now_ms = m.now_ms
					_heard_clock(m.now_ms)
		"profile":
			profiled.emit(m)
		"result":
			_answered(m)
		"debug_done":
			rehearsed.emit()
		"nameless":
			var waiting := _pending.duplicate()
			if not up:
				up = true
				link_changed.emit(true)
			for p in waiting: _write_command(p)     # a claim that was cut off goes again: the same name and secret just let them in
		"hello_refused":
			player = ""
			_ws.close()
			_ws = null
			hello_refused.emit(m.refusal)
		"presence":
			presence.emit(m.players)
		"left":
			left.emit(str(m.name))
		"kicked":
			kicked = true
			up = false
			link_changed.emit(false)
		"error":
			push_warning("server: " + str(m.get("message", "")))
			server_said.emit(str(m.get("message", "")))

## Where the town's plain HTTP is (PROTOCOL.md, HTTP): the same host and port as the WebSocket.
func http_base() -> String:
	return url.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/")

## The money of this player's that moved, as the server reported it, for the wallet's recent list. The server keeps no history for the
## client, so this is the session's own.
func _note_payment(e: Dictionary) -> void:
	if str(e.get("account", "")) != player: return
	var p := {}
	match str(e.get("type", "")):
		"MealEaten": p = {"what": "meal", "item": str(e.get("item", "")), "usdc": -int(e.get("usdc", 0)), "tx": e.get("tx")}
		"RewardPaid": p = {"what": str(e.get("why", "reward")), "usdc": int(e.get("amount", 0)), "tx": e.get("tx")}
		"DrawWon": p = {"what": "weekly draw", "usdc": int(e.get("prize", 0)), "tx": e.get("tx")}
		_: return
	payments.push_front(p)
	if payments.size() > PAYMENTS_KEPT: payments.pop_back()

## A command has its answer. RefUsed means an earlier try got through while the link was failing: not a refusal at all.
func _answered(m: Dictionary) -> void:
	for i in _pending.size():
		if _pending[i].ref != m.get("ref"): continue
		var p: Dictionary = _pending[i]
		_pending.remove_at(i)
		var ok: bool = m.get("ok", false) or m.get("refusal", {}).get("type", "") == "RefUsed"
		if not ok: refused.emit(p.command, m.get("refusal", {}))
		else: replied.emit(p.command, m)
		answered.emit(str(p.ref), ok)
		return
