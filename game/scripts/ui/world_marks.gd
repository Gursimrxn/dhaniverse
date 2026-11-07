class_name WorldMarks
extends Control
## The same marks everywhere (ux07), drawn over the town on the screen: every quest you could take shows its board badge over the place
## it starts (orange Rush, magenta swap, blue mystery, ink errands, gold Gran; faded once done today) with its name and how far; the one
## you're running (or an urgent crate) gets its words and distance under the guide's gold diamond, and when it's off the screen it
## waits on the screen's edge with an arrow pointing the way, so it's never lost. Within FOLD m the diamond folds into the green key hint
## and so does this.

const RANGE := 70.0              # m: badges further than this stay off the screen
const FOLD := 8.0                # m: the guide's diamond folds away here, and the words with it
const EDGE := Vector2(56, 96)    # px kept clear of the screen's sides and its top and bottom (the plates, the pocket)
const RUSH_AT := "stall"
const BADGE_PX := 10
const WORDS_PX := 12
const NOTE := Color("C9C1A6")
const GOLD := Color("F0C33A")

var world: Node
var client: TownClient
var _marks: Array = []           # {at: Vector3, colour, ink, word, title, faded}
var _goal := {}                  # {at: Vector3, words, colour}
var _think := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think = 0.4
		_read()
	queue_redraw()

## What to mark, from the offers the board shows and the guide's goal.
func _read() -> void:
	_marks.clear()
	_goal = {}
	var town: Dhaniverse = world.dhaniverse if world else null
	if town == null or client.you.is_empty(): return
	var guide: Guide = town.guide
	if guide.next_distance() != INF:
		var urgent: bool = world.loot != null and not world.loot.current().is_empty()
		_goal = {"at": guide.next_at(), "words": guide.next_words(), "colour": Brand.ORANGE if urgent else GOLD}
	var tracked := TownState.quest(client.you, guide.tracked)
	var busy := {}
	if not tracked.is_empty():
		var s := TownState.next_step(tracked)
		if not s.is_empty(): busy[str(s.get("place", ""))] = true
	for o in TownState.offers(client.you, client.city):
		var place := str(o.get("place", ""))
		if bool(o.on) or place == "" or busy.has(place) or not town.knows(place): continue
		var look: Array = BountyBoard.BADGES.get(BountyBoard.badge(o)[0], BountyBoard.BADGES.errand)
		_marks.append({"at": town.place_at(place) + Vector3.UP * (QuestMarks.OVER_PERSON if town.is_person(place) else QuestMarks.OVER) + Vector3.UP * 0.6,
			"colour": look[0], "ink": look[1], "word": str(BountyBoard.badge(o)[1]), "title": str(o.title).to_lower(), "faded": guide.done_today(str(o.quest))})
	if int(client.you.get("runs_left", 0)) > 0 and town.knows(RUSH_AT) and not busy.has(RUSH_AT):
		var rush: Array = BountyBoard.BADGES.rush
		_marks.append({"at": town.place_at(RUSH_AT) + Vector3.UP * 2.9, "colour": rush[0], "ink": rush[1], "word": "90s", "title": "market rush", "faded": false})

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or world == null or world.player == null: return
	var me: Vector3 = world.player.global_position
	for m in _marks:
		var far := Vector2(m.at.x - me.x, m.at.z - me.z).length()
		if far > RANGE or far < FOLD or cam.is_position_behind(m.at): continue
		var p := cam.unproject_position(m.at)
		if not Rect2(Vector2.ZERO, size).grow(-8.0).has_point(p): continue
		_pill(p, m.word, m.colour, m.ink, "%s · %d m" % [m.title, roundi(far)], 0.4 if m.faded else 1.0)
	if _goal.is_empty(): return
	var at: Vector3 = _goal.at
	var gone := Vector2(at.x - me.x, at.z - me.z).length()
	if gone < FOLD: return
	var said := "%s · %d m" % [str(_goal.words), roundi(gone)]
	var inside := Rect2(EDGE, size - EDGE * 2.0)
	var spot := cam.unproject_position(at)
	if not cam.is_position_behind(at) and inside.has_point(spot):
		_words_under(spot + Vector2(0, 26), said, _goal.colour)
		return
	# off the screen: on its edge, the way it lies from the middle, with an arrow pointing on
	var local := cam.global_transform.affine_inverse() * at
	var way := Vector2(local.x, -local.y)
	if local.z > 0.0: way = Vector2(local.x, 0.0)        # behind you: left or right, along the bottom of the way
	if way.length() < 0.001: way = Vector2.DOWN
	way = way.normalized()
	var mid := size * 0.5
	var reach := minf(absf((inside.size.x * 0.5) / way.x) if absf(way.x) > 0.001 else INF, absf((inside.size.y * 0.5) / way.y) if absf(way.y) > 0.001 else INF)
	var pin := mid + way * reach
	_arrow(pin, way, _goal.colour)
	_words_under(pin - way * 34.0, said, _goal.colour)

## A badge and its words, centred over a point: the board's colour chip with its word, then the quest's name and distance.
func _pill(p: Vector2, word: String, colour: Color, ink: Color, rest: String, alpha: float) -> void:
	var wfont: Font = Brand.FONT_DISPLAY
	var rfont: Font = Brand.FONT_BODY
	var ww := wfont.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_PX).x + 12.0
	var rw := rfont.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, WORDS_PX).x
	var w := ww + rw + 18.0
	var box := Rect2(p.x - w * 0.5, p.y - 13.0, w, 26.0)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(Brand.PLATE, alpha)
	plate.border_color = Color(Brand.CREAM, alpha)
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(13)
	draw_style_box(plate, box)
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(colour, alpha)
	chip.set_corner_radius_all(9)
	draw_style_box(chip, Rect2(box.position + Vector2(4, 4), Vector2(ww, 18)))
	draw_string(wfont, box.position + Vector2(10, 4 + 9 + (wfont.get_ascent(BADGE_PX) - wfont.get_descent(BADGE_PX)) * 0.5), word, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_PX, Color(ink, alpha))
	draw_string(rfont, box.position + Vector2(ww + 11, 13 + (rfont.get_ascent(WORDS_PX) - rfont.get_descent(WORDS_PX)) * 0.5), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, WORDS_PX, Color(Brand.CREAM, alpha))

## The goal's words in its colour on a dark pill, centred under a point.
func _words_under(p: Vector2, words: String, colour: Color) -> void:
	var font: Font = Brand.FONT_BODY
	var w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, WORDS_PX).x + 22.0
	var box := Rect2(p.x - w * 0.5, p.y - 12.0, w, 24.0)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Brand.PLATE
	plate.border_color = colour
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(12)
	draw_style_box(plate, box)
	draw_string(font, box.position + Vector2(11, 12 + (font.get_ascent(WORDS_PX) - font.get_descent(WORDS_PX)) * 0.5), words, HORIZONTAL_ALIGNMENT_LEFT, -1, WORDS_PX, colour)

## The edge arrow: a diamond-headed pointer in the goal's colour, pointing the way.
func _arrow(p: Vector2, way: Vector2, colour: Color) -> void:
	var side := Vector2(-way.y, way.x)
	var tip := p + way * 14.0
	draw_colored_polygon(PackedVector2Array([tip, p - way * 6.0 + side * 11.0, p - way * 1.0, p - way * 6.0 - side * 11.0]), colour)
	draw_polyline(PackedVector2Array([tip, p - way * 6.0 + side * 11.0, p - way * 1.0, p - way * 6.0 - side * 11.0, tip]), Brand.PLATE, 1.5, true)
