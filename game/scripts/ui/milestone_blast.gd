class_name MilestoneBlast
extends Control
## A really earned first takes the whole screen for a moment, as on the milestone board in its default green: rays turning round
## the mark, shockwave rings, confetti, the title stamping in with a shake and a shine, then the firsts so far.
## Everyday firsts (QUIET) get a FirstNote instead. Never during a camera moment: `wait_for` says when one is playing.
## The one big effect the game allows itself. Nothing pauses behind it, and it goes by itself, so it has none of the board's
## buttons: there's no Ledger Wall to carve at, and nothing to share to.

## The server's firsts (PROTOCOL.md): first_meal, first_quest, town_pass. A big reveal of another kind (Grandma's strongbox) comes
## through show_reveal().
const FIRSTS := {
	"first_meal": ["First meal", "Food is what fills your energy. Its price moves with the whole city."],
	"first_quest": ["First quest", "Work for the town, paid in USDC. The Bounty Board has more."],
	"town_pass": ["Town Pass", "One real person, one pass. Now the town can pay you."],
}
const HOW_MANY := 3
const QUIET := ["first_meal"]
const OVER_EVERYTHING := 100     # z index
const SETTLE := 0.9              # s after it was earned: the coin lands before the screen goes
const LASTS := 4.5               # s
const FADE_IN := 0.12
const FADE_OUT := 0.35
const BG := Color("337E43")      # the board's default colourway
const FG := Color.WHITE
const SHINE := Color("FFF8E3")
# where things are on the board's 1440x810 stage, at 1280x720
const MID := Vector2(640, 169)   # the mark's middle: rays, rings and confetti start here
const MARK := Vector2(128, 124)
const TITLE_TOP := 256.0
const STATS_TOP := 508.0
const RAYS := 20                 # 9 degrees on, 9 off
const RAY_SPIN := TAU / 40.0     # radians a second
const RINGS := [[0.25, 5.3], [0.45, 3.6], [0.65, 1.8]]    # delay s, width px
const RING_TIME := 1.2
const RING_FROM := 27.0          # px radius: 20rem across at scale .3 ...
const RING_TO := 302.0           # ... to 3.4
const SHAKE := [Vector2.ZERO, Vector2(-5, 3), Vector2(4, -4), Vector2(-3, 2), Vector2(2, -1), Vector2.ZERO]
const CONFETTI := 40
const CONFETTI_COLOURS := [Brand.BLUE, Brand.MAGENTA, Brand.ORANGE, Brand.CREAM, Color("F0C33A"), Color.BLACK, Color.WHITE]

var client: TownClient
var wait_for := Callable()        # true while something else has the screen
var _note := FirstNote.new()

var playing: bool:
	get: return _t >= 0.0 or _note.playing or not _waiting.is_empty()

var _waiting: Array = []          # firsts (their names) and reveals ({title, line, kicker}), in turn
var _t := -1.0                   # s into this blast; below 0, none
var _settling := 0.0
var _mark := TextureRect.new()
var _brand := HBoxContainer.new()
var _day := Label.new()
var _words := VBoxContainer.new()
var _kicker := Label.new()
var _title := Label.new()
var _scratch := Control.new()
var _line := Label.new()
var _stats := VBoxContainer.new()
var _segs := Control.new()
var _count := RichTextLabel.new()
var _shine: ShaderMaterial
var _bits: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = OVER_EVERYTHING
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_mark.texture = preload("res://assets/ui/coin_mark.svg")
	_mark.modulate = FG
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.size = MARK
	_mark.pivot_offset = MARK * 0.5
	add_child(_mark)
	_build_corners()
	_build_words()
	_build_stats()
	get_parent().add_child.call_deferred(_note)   # beside this, which stays hidden between blasts
	if client: client.event.connect(_on_event)

func _style(label: Label, font: Font, font_size: int) -> Label:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", FG)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Top left the brand, top right the day, as on the board.
func _build_corners() -> void:
	_brand.add_theme_constant_override("separation", 11)
	_brand.position = Vector2(28, 28)
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := TextureRect.new()
	mark.texture = _mark.texture
	mark.modulate = FG
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(27, 26)
	_brand.add_child(mark)
	var name_label := _style(Label.new(), Brand.FONT_BODY, 20)
	name_label.text = "Dhaniverse"
	_brand.add_child(name_label)
	add_child(_brand)
	_style(_day, Brand.FONT_DISPLAY, 18)
	_day.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_day)

func _build_words() -> void:
	_words.add_theme_constant_override("separation", 14)
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(_kicker, Brand.FONT_DISPLAY, 20)
	_kicker.text = "MILESTONE · A NEW FIRST"
	var tight := FontVariation.new()     # the board's -.045em
	tight.base_font = Brand.FONT_BODY
	tight.spacing_glyph = -5
	_style(_title, tight, 107)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec4 fg : source_color;
uniform vec4 shine : source_color;
uniform float width = 1.0;
uniform float at = -0.25;     // the band's middle, in the title's widths
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	float t = dot(local / width, vec2(0.94, 0.342));    // the board's 110deg
	COLOR.rgb = mix(fg.rgb, shine.rgb, clamp(1.0 - abs(t - at) / 0.2, 0.0, 1.0));
}"""
	_shine = ShaderMaterial.new()
	_shine.shader = sh
	_shine.set_shader_parameter("fg", FG)
	_shine.set_shader_parameter("shine", SHINE)
	_title.material = _shine
	var title_box := VBoxContainer.new()  # the title and its scratched underline, as wide as each other
	title_box.add_theme_constant_override("separation", 11)
	title_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_box.add_child(_title)
	_scratch.custom_minimum_size.y = 5
	_scratch.draw.connect(func():
		var look := StyleBoxFlat.new()
		look.bg_color = Color(FG, 0.85)
		look.set_corner_radius_all(3)
		_scratch.draw_style_box(look, Rect2(0, 0, _scratch.size.x * _ramp(0.95, 0.6), 5)))
	title_box.add_child(_scratch)
	_style(_line, Brand.FONT_BODY, 20)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 533
	_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for part in [_kicker, title_box, _line]: _words.add_child(part)
	add_child(_words)

## The firsts so far, as the board's segments. Its other stats (saved, the daily rate) belong to one first; these are every first's.
func _build_stats() -> void:
	_stats.add_theme_constant_override("separation", 7)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_segs.custom_minimum_size = Vector2(HOW_MANY * 25.0 + (HOW_MANY - 1) * 4.0, 11)
	_segs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_segs.draw.connect(_draw_segs)
	_stats.add_child(_segs)
	EnergyPlate.small_print(_count)
	_count.add_theme_color_override("default_color", FG)
	_count.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stats.add_child(_count)
	add_child(_stats)

func _on_event(e: Dictionary) -> void:
	if e.type == "FirstEarned" and e.account == client.player: show_first(e.first)

## Queued, so two firsts at once each get their moment.
func show_first(first: String) -> void:
	if FIRSTS.has(first): _waiting.append(first)

## A big moment that isn't a first: the same blast, with its own words.
func show_reveal(title: String, line: String, kicker := "MILESTONE") -> void:
	_waiting.append({"title": title, "line": line, "kicker": kicker})

func _earned() -> int:
	return client.you.get("firsts", []).size() if client else 0

func _begin(what) -> void:
	var first := str(what) if what is String else ""
	if QUIET.has(first):
		_note.show_note(FIRSTS[first][0], FIRSTS[first][1])
		return
	_t = 0.0
	var words: Array = FIRSTS[first] if first != "" else [str(what.title), str(what.line)]
	_kicker.text = "MILESTONE · A NEW FIRST" if first != "" else str(what.get("kicker", "MILESTONE"))
	_title.text = words[0]
	# the board's 12rem, unless a long first wouldn't fit across the screen
	var font: Font = _title.get_theme_font("font")
	var fs := 107
	while fs > 48 and font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 1180.0: fs -= 4
	_title.add_theme_font_size_override("font_size", fs)
	_line.text = words[1]
	_count.text = "[font_size=14]%s[/font_size] firsts" % EnergyPlate.mono("%d/%d" % [_earned(), HOW_MANY])
	_day.text = "DAY %d · SEASON %d" % [int(client.city.get("day", 0)), int(client.city.get("season", {}).get("number", 0))] if client else ""
	visible = true
	_bits.clear()
	for i in CONFETTI:
		var a := TAU * i / CONFETTI + _rng.randf() * 0.5
		var d := _rng.randf_range(213.0, 533.0)
		var s := _rng.randf_range(7.0, 16.0)
		_bits.append({"to": Vector2(cos(a) * d, sin(a) * d * 0.7 - 80.0), "spin": deg_to_rad(_rng.randf_range(-360.0, 360.0)),
			"size": Vector2(s, s if i % 3 == 0 else s * 0.5), "round": i % 3 == 0, "delay": _rng.randf_range(0.45, 0.6),
			"colour": CONFETTI_COLOURS[i % CONFETTI_COLOURS.size()]})

## 0 to 1 over `lasting` seconds from `from`.
func _ramp(from: float, lasting: float) -> float:
	return clampf((_t - from) / lasting, 0.0, 1.0)

func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)

func _ease_back(t: float) -> float:
	var s := t - 1.0
	return s * s * (2.7 * s + 1.7) + 1.0

func _process(delta: float) -> void:
	if _t < 0.0:
		if _waiting.is_empty():
			_settling = SETTLE
		else:
			_settling -= delta
			# one big moment at a time: it waits for the camera, and for any note still showing
			if _settling <= 0.0 and not _note.playing and not (wait_for.is_valid() and wait_for.call()): _begin(_waiting.pop_front())
		return
	_t += delta
	if _t >= LASTS:
		_t = -1.0
		visible = false
		return
	var stage := _stage()
	# the mark pops in turning, then floats
	var pop := _ease_back(_ramp(0.1, 0.7))
	_mark.position = stage + MID - MARK * 0.5 + Vector2(0, -7.0 * sin(maxf(_t - 1.0, 0.0) * TAU / 3.0))
	_mark.scale = Vector2.ONE * maxf(pop, 0.001)
	_mark.rotation = deg_to_rad(-30.0) * (1.0 - _ramp(0.1, 0.7))
	_mark.modulate.a = _ramp(0.1, 0.2)
	_words.position = stage + Vector2(0, TITLE_TOP)
	_words.size = Vector2(1280, 0)
	_kicker.modulate.a = _ramp(0.35, 0.5)
	var stamp := _ramp(0.5, 0.45)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2.ONE * lerpf(1.9, 1.0, _ease_back(stamp))
	_title.rotation = deg_to_rad(-6.0) * (1.0 - stamp)
	_title.modulate.a = stamp
	# the shine crosses between 40% and 80% of each 2.4 s, from 1.1 s on
	var cycle := fmod(maxf(_t - 1.1, 0.0), 2.4) / 2.4
	_shine.set_shader_parameter("width", maxf(_title.size.x, 1.0))
	_shine.set_shader_parameter("at", lerpf(-0.25, 2.15, smoothstep(0.4, 0.8, cycle)))
	_scratch.queue_redraw()
	_line.modulate.a = _ramp(0.9, 0.5)
	# the board's rise: up 1.6rem into place, fading in, over half a second
	var rise := _ramp(1.05, 0.5)
	_stats.position = stage + Vector2(0, STATS_TOP + 14.0 * (1.0 - rise))
	_stats.size = Vector2(1280, 0)
	_stats.modulate.a = rise
	_segs.queue_redraw()
	_day.size = Vector2(400, 24)
	_day.position = Vector2(size.x - 400.0 - 28.0, 32.0)
	modulate.a = minf(minf(_t / FADE_IN, (LASTS - _t) / FADE_OUT), 1.0)
	queue_redraw()

## The board's 1280x720 stage, centred on the screen, shaking as the title lands.
func _stage() -> Vector2:
	var at := (size - Vector2(1280, 720)) * 0.5
	var k := _ramp(0.55, 0.4)
	if k <= 0.0 or k >= 1.0: return at
	var i := int(k * 5.0)
	return at + SHAKE[i].lerp(SHAKE[i + 1], k * 5.0 - i)

func _draw() -> void:
	if _t < 0.0: return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var c := _stage() + MID
	var far := size.length()
	var ray := Color(FG, 0.10)
	for i in RAYS:
		var a := TAU * i / RAYS + _t * RAY_SPIN
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a) * far, c + Vector2.from_angle(a + TAU / RAYS * 0.5) * far]), ray)
	for ring in RINGS:
		var k: float = (_t - ring[0]) / RING_TIME
		if k > 0.0 and k < 1.0:
			draw_arc(c, lerpf(RING_FROM, RING_TO, _ease_out(k)), 0.0, TAU, 72, Color(FG, 0.9 * (1.0 - k)), ring[1], true)
	# confetti on the board's path: out to its spot by 55%, then on and down 26rem, fading
	for b in _bits:
		var k: float = (_t - b.delay) / 1.8
		if k <= 0.0 or k >= 1.0: continue
		var at: Vector2
		var turn: float
		var alpha := 1.0
		if k < 0.55:
			var e := _ease_out(k / 0.55)
			at = b.to * e
			turn = b.spin * e
			draw_set_transform(c + at, turn, Vector2.ONE * lerpf(0.2, 1.0, e))
		else:
			var e := _ease_out((k - 0.55) / 0.45)
			at = b.to.lerp(Vector2(b.to.x * 1.15, b.to.y + 231.0), e)
			turn = b.spin * (1.0 + e)
			alpha = 1.0 - e
			draw_set_transform(c + at, turn)
		var colour := Color(b.colour, alpha)
		if b.round: draw_circle(Vector2.ZERO, b.size.x * 0.5, colour)
		else: draw_rect(Rect2(-b.size * 0.5, b.size), colour)
	draw_set_transform(Vector2.ZERO)

## Filled for each first so far; the newest fills in at 1.5 s, then flashes.
func _draw_segs() -> void:
	var earned := _earned()
	var look := StyleBoxFlat.new()
	look.set_corner_radius_all(4)
	for i in HOW_MANY:
		var r := Rect2(i * 29.0, 0, 25, 11)
		look.bg_color = Color(FG, 0.25)
		_segs.draw_style_box(look, r)
		if i >= earned: continue
		var newest := i == earned - 1
		var f := _ramp(1.9, 0.9)
		if newest and f > 0.0 and f < 1.0:    # the flash, spreading out from behind it
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(1, 1, 1, 0.9 * (1.0 - f))
			ring.set_corner_radius_all(4 + int(16.0 * f))
			ring.set_expand_margin_all(16.0 * f)
			_segs.draw_style_box(ring, r)
		look.bg_color = FG
		_segs.draw_style_box(look, Rect2(r.position, Vector2(r.size.x * (_ease_out(_ramp(1.5, 0.5)) if newest else 1.0), r.size.y)))
