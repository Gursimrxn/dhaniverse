class_name ExchangeBoard
extends Node3D
## The exchange in the world (ux12): Uniswap's live quote on a flap board over the kiosk on the landing, its own mark on it, a brass lever
## at its side, and the "AT THE CHAIN" stamp while the swap is out. E at the kiosk brings the camera up to it and the island turns into
## its bar ("hold, pull the lever", "Q new quote", Esc); hold E and the lever comes down and the swap goes (chosen). SpiceRun owns what it
## says: the quote, the clock and the server's answers. This only shows them, and holds the keys while it's up.

signal chosen(i: int)              # the lever: swap on this quote
signal key_pressed(key: int)       # Q: a new quote

const SIZE := Vector2(2.6, 1.6)    # m, the board's face
const AT := Vector3(0.0, 4.0, -0.35)   # its middle, in the kiosk's own frame (the kiosk faces +Z, where a customer stands)
const EYE := Vector3(0.0, 3.3, 4.6)    # where the camera looks from, in the same frame
const HOLD := 1.0                  # s of E to pull the lever
const FLY := 1.1
const DARK := Color("1d1e1e")
const BRASS := Color("C9A24A")
const NOTE := Color("C9C1A6")
const UNISWAP := preload("res://assets/ui/sponsors/Uniswap_horizontallogo_pink.png")

var player: CharacterBody3D
var director: Director
var is_open := false
var pick := 0
var title := ""                    # the island's title while it's up: the run
var note := ""                     # what it last said, for the island and for the walkthrough bot
var _kiosk := Transform3D.IDENTITY
var _rows: Array[Label3D] = []     # [label, value] pairs, one per line of the quote
var _chain := Label3D.new()        # "Uniswap v4 · Sepolia", or a rehearsal
var _clock := Label3D.new()
var _stamp := Label3D.new()
var _lever := Node3D.new()
var _hold := 0.0
var _armed := false                # E let go since it opened: a new press pulls

func setup(kiosk: Transform3D, chain_words: String) -> void:
	_kiosk = kiosk
	global_transform = kiosk.translated_local(AT)
	_build(chain_words)

func _build(chain_words: String) -> void:
	var back := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = Vector3(SIZE.x, SIZE.y, 0.08)
	back.mesh = face
	back.material_override = _flat(DARK)
	add_child(back)
	var frame := MeshInstance3D.new()
	var rim := BoxMesh.new()
	rim.size = Vector3(SIZE.x + 0.1, SIZE.y + 0.1, 0.06)
	frame.mesh = rim
	frame.position.z = -0.03
	frame.material_override = _flat(BRASS, 0.7)
	add_child(frame)
	for x in [-SIZE.x * 0.42, SIZE.x * 0.42]:      # the posts it stands on, down to the kiosk's roof
		var post := MeshInstance3D.new()
		var pole := BoxMesh.new()
		pole.size = Vector3(0.07, 0.9, 0.07)
		post.mesh = pole
		post.position = Vector3(x, -SIZE.y * 0.5 - 0.45, -0.05)
		post.material_override = _flat(BRASS, 0.7)
		add_child(post)
	var mark := Sprite3D.new()                      # Uniswap's own wordmark, as is
	mark.texture = UNISWAP
	mark.pixel_size = 0.0011
	mark.position = Vector3(-SIZE.x * 0.5 + 0.36, SIZE.y * 0.5 - 0.18, 0.05)
	add_child(mark)
	var head := _text(_head("THE EXCHANGE · LIVE QUOTE"), Vector3(-SIZE.x * 0.5 + 0.72, SIZE.y * 0.5 - 0.13, 0.05), HORIZONTAL_ALIGNMENT_LEFT)
	head.font_size = 34
	add_child(head)
	_chain = _text(_small(chain_words), Vector3(-SIZE.x * 0.5 + 0.72, SIZE.y * 0.5 - 0.27, 0.05), HORIZONTAL_ALIGNMENT_LEFT)
	_chain.font_size = 28
	add_child(_chain)
	for i in 4:
		var y := SIZE.y * 0.5 - 0.52 - i * 0.22
		var label := _text(_small(""), Vector3(-SIZE.x * 0.5 + 0.12, y, 0.05), HORIZONTAL_ALIGNMENT_LEFT)
		var value := _text(_figure(""), Vector3(SIZE.x * 0.5 - 0.12, y, 0.05), HORIZONTAL_ALIGNMENT_RIGHT)
		add_child(label)
		add_child(value)
		_rows.append(label)
		_rows.append(value)
	_clock = _text(_small(""), Vector3(0.0, -SIZE.y * 0.5 + 0.13, 0.05), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_clock)
	_stamp = _text(_head("AT THE CHAIN"), Vector3(SIZE.x * 0.22, -SIZE.y * 0.12, 0.07), HORIZONTAL_ALIGNMENT_CENTER)
	_stamp.font_size = 64
	_stamp.outline_size = 18
	_stamp.rotation.z = deg_to_rad(8.0)
	_stamp.visible = false
	add_child(_stamp)
	_lever.position = Vector3(SIZE.x * 0.5 + 0.22, -0.1, 0.0)    # the brass lever at its right, pulled down to swap
	var arm := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.025
	rod.bottom_radius = 0.025
	rod.height = 0.7
	arm.mesh = rod
	arm.position.y = 0.35
	arm.material_override = _flat(BRASS, 0.8)
	_lever.add_child(arm)
	var knob := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.07
	ball.height = 0.14
	knob.mesh = ball
	knob.position.y = 0.72
	knob.material_override = _flat(Color("b8473b"), 0.3)
	_lever.add_child(knob)
	add_child(_lever)

static func _flat(colour: Color, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metal
	m.roughness = 0.45 if metal > 0.0 else 0.85
	return m

func _text(label: Label3D, at: Vector3, align: int) -> Label3D:
	label.position = at
	label.horizontal_alignment = align
	label.pixel_size = 0.0021
	label.shaded = false
	label.double_sided = false
	label.outline_size = 0
	return label

func _head(words: String) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.font = Brand.FONT_DISPLAY
	l.font_size = 40
	l.modulate = Brand.CREAM
	return l

func _small(words: String) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.font = Brand.FONT_BODY
	l.font_size = 36
	l.modulate = NOTE
	return l

func _figure(words: String) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.font = Brand.FONT_BODY
	l.font_size = 48
	l.modulate = Brand.CREAM
	return l

## The quote's lines (each [what, figure]), its clock, and the stamp: "chain" while the swap is out, "done" with what came, or "".
func show_quote(rows: Array, clock: String, stamp := "", stamp_words := "") -> void:
	for i in 4:
		var row: Array = rows[i] if i < rows.size() else ["", ""]
		_rows[i * 2].text = str(row[0])
		_rows[i * 2 + 1].text = str(row[1])
	_clock.text = clock
	_stamp.visible = stamp != ""
	_stamp.text = stamp_words if stamp_words != "" else "AT THE CHAIN"
	_stamp.modulate = Brand.ORANGE if stamp == "chain" else Brand.MINT

## E at the kiosk: the camera comes up to the board, the island becomes its bar, and the keys are the board's.
func open() -> void:
	if is_open: return
	is_open = true
	_armed = false
	_hold = 0.0
	player.frozen = true
	if Island.up:
		Island.up.board_bar(true)
		Island.up.board_mode(false, "hold, pull the lever", ["Q", "new quote"])
	var eye := get_viewport().get_camera_3d()
	var from := eye.global_position
	var to_eye := _kiosk * EYE
	director.fly([from, to_eye], [from - eye.global_basis.z * 4.0, global_position], FLY, eye.fov, false)

func close() -> void:
	if not is_open: return
	is_open = false
	_hold = 0.0
	if Island.up:
		Island.up.board_hold(0.0)
		Island.up.board_mode(true, "hold, tear it off", [])
		Island.up.board_bar(false)
	await director.land(FLY)
	if not is_open:
		player.frozen = false
		player.rig.take_cursor_back()

## The island's line: the run, its step and what the swap does.
func set_card(title_: String, line: String) -> void:
	title = title_
	if Island.up: Island.up.board_card(title, line)

## A word from the exchange: the server's answer, or what's happening. Warm is a refusal, in orange.
func say(words: String, warm := true) -> void:
	note = words
	if Island.up and words != "":
		if warm: Island.up.board_say(words)
		else: Island.up.board_card(title, words)

func _process(delta: float) -> void:
	if not is_open: return
	if not Input.is_action_pressed("interact"):
		_armed = true
		_hold = maxf(_hold - delta * 2.0, 0.0)
	elif _armed:
		_hold = 1.0 if Access.tap_holds else minf(_hold + delta / HOLD, 1.0)
		if _hold >= 1.0:
			_armed = false
			_hold = 0.0
			_pull()
	if Island.up: Island.up.board_hold(_hold)
	_lever.rotation.x = lerpf(_lever.rotation.x, -_hold * 1.1, 1.0 - exp(-18.0 * delta))

## The lever comes down and springs back: the swap goes.
func _pull() -> void:
	if HudMotion.on:
		var t := create_tween()
		t.tween_property(_lever, "rotation:x", -1.3, 0.12).set_ease(Tween.EASE_IN)
		t.tween_property(_lever, "rotation:x", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	chosen.emit(0)

func _input(e: InputEvent) -> void:
	if not is_open or not e is InputEventKey or not e.pressed or e.echo: return
	match e.keycode:
		KEY_Q: key_pressed.emit(KEY_Q)
		KEY_ESCAPE: close()
		_: return
	get_viewport().set_input_as_handled()
