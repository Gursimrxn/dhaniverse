class_name Island
extends Control
## Top centre, as on the island boards (States, Main, Morph): the city day's clock in a dark pill, beside a dial with the sun where the
## world's sun really is. When something happens, a round lobe splits off the pill's left end, joined by a liquid neck, and says
## what it was: one at a time, a meal first, the town last, a dot under it for each still waiting. During a Market Rush run it holds
## the run. Hover it with the cursor free, or hold Alt, and a card drops out of it: your energy, your best run, the day.
## One ColorRect draws every shape (shaders/ui/island.gdshader); the words are Labels over it.
## Board sizes are rem at 1440, so x REM px here.

signal held(kind: String)          # a moment, the run or the clock is fully up

const REM := 1280.0 / 144.0
const TOP := 2.4
const REST := Vector2(23.6, 4.8)
const H := 6.4                     # a moment's height, and its lobe's
const GAP := 0.7                   # between the lobe and the pill
const CARD := Vector2(46.0, 17.0)
const CARD_R := 2.4
const RUN_W := 46.0
const MAX_W := 60.0
const MENTOR_W := 38.0             # rem: the widest a mentor's line grows
const MAX_TEXT := 40.0             # rem: a longer line is cut short
const RING := 3.0                  # px
const NECK := 18.0                 # px the union reaches: enough to bridge GAP with a neck
const OPEN := 0.5                  # s
const SHUT := 0.45
const BETWEEN := 0.6               # s at rest between two moments
const GLANCE_IN := 0.45
const WAITING := 6                 # moments kept in line; past this the last goes
const BOX := Vector2(720, 420)     # px: the shader's rect, room for the widest moment and the card, with the shadow
const BOX_AT := Vector2(360, 24)   # where the island's top centre is in it
const MUTED := Color("C9C1A6")
const OUT_INK := Color("FF8A3D")
const TRACK := Color("3d3e3e")
const RULE := Color("4a4b4b")
const HORIZON := Color("5a5b5b")
const SUN_HIGH := Color("FFC86B")
const SUN_LOW := Color("FF8A3D")
const TOWN := Color("3a3b3b")
const STALL := "Kofi's stall"
# kind: [place in line, seconds up, the board's width in rem]. A meal goes ahead of anything waiting; the town waits for everyone.
const KINDS := {"meal": [0, 3.0, 33.0], "rush": [1, 3.0, 33.0], "money": [1, 3.2, 34.0], "quest": [1, 3.6, 36.0], "mentor": [2, 8.0, 36.0], "town": [3, 3.0, 36.0]}
const WHY := {"streak": "for coming back", "rush": "for a Rush run", "chest": "from your chest", "weekly chest": "from the weekly strongbox", "quest": "for a quest",
	"price call": "for a right price call", "referral": "for a friend you brought"}
const WAITING_FOR := {"town_pass": "waiting for your Town Pass", "budget": "the town's budget is spent today: tomorrow", "chain": "the chain refused it: tried again tomorrow"}
const FEED_PLACES := {"board": "Market Rush", "season": "Tallyport"}
const ICONS := {
	"bowl": '<path d="M4 11h16a8 8 0 0 1-16 0z"/><path d="M9 7.5c0-1.5 1-1.5 1-3M13 7.5c0-1.5 1-1.5 1-3"/>',
	"stall": '<path d="M3 9l2-5h14l2 5"/><path d="M3 9h18v1a3 3 0 0 1-6 0 3 3 0 0 1-6 0 3 3 0 0 1-6 0z"/><path d="M5 13v7h14v-7"/>',
	"quest": '<path d="M12 21s-6-5.5-6-10a6 6 0 0 1 12 0c0 4.5-6 10-6 10z"/><circle cx="12" cy="11" r="2"/>',
	"ticket": '<path d="M3 7h18v3a2 2 0 0 0 0 4v3H3v-3a2 2 0 0 0 0-4z"/><path d="M15 7v10"/>',
	"pass": '<rect x="5" y="3" width="14" height="18" rx="2"/><circle cx="12" cy="10" r="3"/><path d="M9 17h6"/>',
	"chest": '<path d="M3 11h18v9H3z"/><path d="M3 11a9 6 0 0 1 18 0"/><path d="M12 13v3"/>',
}
const COIN := preload("res://assets/ui/coin_mark.svg")
const ROUND := "shader_type canvas_item; uniform float ring = 0.0; void fragment() { float d = length(UV - vec2(0.5)); COLOR.rgb = mix(COLOR.rgb, vec3(1.0, 0.973, 0.89), step(0.5 - ring, d)); COLOR.a *= smoothstep(0.5, 0.49, d); }"
# the board's coin: its linear gradient corner to corner, keeping the fade (gradient_mark.gdshader flows, and drops the modulate)
const COIN_FILL := "shader_type canvas_item; void fragment() { float t = (UV.x + UV.y) * 0.5; vec3 c = mix(vec3(1.0, 0.925, 0.741), vec3(1.0, 0.4, 0.0), clamp(t / 0.35, 0.0, 1.0)); c = mix(c, vec3(0.898, 0.18, 0.996), clamp((t - 0.35) / 0.25, 0.0, 1.0)); c = mix(c, vec3(0.439, 0.475, 1.0), clamp((t - 0.6) / 0.2, 0.0, 1.0)); COLOR.rgb = mix(c, vec3(0.631, 1.0, 0.706), clamp((t - 0.8) / 0.2, 0.0, 1.0)); }"

static var up: Island
static var _icons := {}

var world: Node
var hud: GameHud
var client: TownClient

var _root := Control.new()         # the island's top centre
var _shape := ColorRect.new()
var _mat := ShaderMaterial.new()
var _coin_mat := ShaderMaterial.new()
var _face_mat := ShaderMaterial.new()
var _ringed_mat := ShaderMaterial.new()
var _rest := HBoxContainer.new()
var _dial := Control.new()
var _clock: Label
var _day: Label
var _run := Control.new()
var _run_name: Label
var _run_clock: Label
var _run_track := Control.new()
var _run_sub := HBoxContainer.new()
var _moment := Control.new()
var _icon := TextureRect.new()
var _text := HBoxContainer.new()
var _head: Label
var _sub := HBoxContainer.new()
var _end := VBoxContainer.new()
var _fig: Label
var _note := HBoxContainer.new()
var _dots := Control.new()
var _card := MarginContainer.new()
var _pips := Control.new()
var _energy := HBoxContainer.new()
var _best: Label
var _best_sub := HBoxContainer.new()
var _day_big: Label
var _day_sub := HBoxContainer.new()
var _bar_on := StyleBoxFlat.new()
var _bar_off := StyleBoxFlat.new()
var _bar_out := StyleBoxFlat.new()

var _q: Array[Dictionary] = []
var _m := {}
var _phase := 0                    # 0 none, 1 opening, 2 up, 3 closing
var _t := 0.0
var _since := 0.0
var _rest_in := 0.0
var _w := 0.0                      # the moment's pill, rem
var _b := 0.0                      # 0 the clock, 1 the run
var _g := 0.0                      # the glance
var _pill_now := Rect2()
var _lobe_now := Vector3.ZERO
var _box_h := 0.0
var _left_ms := 0.0
var _last_said := -1.0
var _shown_s := -1
var _sun_t := -1.0
var _night := false
var _sun_in := 0.0
var _track_k := -1.0
var _in_rush := false
var _run_said := ""
var _dots_n := 0
var _energy_n := 0
var _said_rest := false
var _said_run := false

## Made and put on screen by world.gd; returned for the opening's plates.
static func join(parent: Control, world_: Node, hud_: GameHud) -> Island:
	var island := Island.new()
	island.world = world_
	island.hud = hud_
	parent.add_child(island)
	return island

func _ready() -> void:
	up = self
	client = world.client
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.position = Vector2(size.x * 0.5, TOP * REM)
	add_child(_root)
	_mat.shader = preload("res://shaders/ui/island.gdshader")
	_mat.set_shader_parameter(&"k", NECK)
	_mat.set_shader_parameter(&"ring", RING)
	_mat.set_shader_parameter(&"card_r", CARD_R * REM)
	_mat.set_shader_parameter(&"shadow_at", Vector2(0.0, REM))
	_mat.set_shader_parameter(&"shadow_blur", 1.6 * REM)
	_shape.material = _mat
	_shape.position = -BOX_AT
	_root.add_child(_shape)
	_coin_mat.shader = Shader.new()
	_coin_mat.shader.code = COIN_FILL
	var round_it := Shader.new()
	round_it.code = ROUND
	_face_mat.shader = round_it
	_ringed_mat.shader = round_it
	_ringed_mat.set_shader_parameter(&"ring", 0.25 / H)
	_build_rest()
	_build_run()
	_build_moment()
	_build_dots()
	_build_card()
	for n in find_children("*", "Control", true, false): (n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	client.event.connect(_on_event)
	if hud: hud._ticker.hide()     # its lines are the island's town moments now
	visible = false

func _exit_tree() -> void:
	if up == self: up = null

# --- what happened -----------------------------------------------------------------------------------------------------

func _on_event(e: Dictionary) -> void:
	var mine := str(e.get("account", "")) == client.player
	var t := str(e.type)
	if not mine and not t in ["FeedPost", "TownGoalReached", "DrawCommitted", "DrawRevealed"]: return
	match t:
		"OrderServed": _order(int(e.served))
		"RushEnded":
			_add({"kind": "rush", "head": "Rush over.", "sub": [["%s · %s" % ["1 order served" if int(e.served) == 1 else "%d orders served" % int(e.served), STALL], ""]],
				"fig": str(int(e.served)), "ink": Brand.MINT, "note": [["best today ", ""], ["{today}", "b"]], "lobe": "stall", "fill": Brand.GREEN})
		"MealOrdered":
			_add({"kind": "meal", "head": "Ordered.", "sub": [["%s · on its way to the chain" % _food(e.item), ""]], "fig": Usdc.text(int(e.get("max_usdc", 0))),
				"ink": Brand.CREAM, "note": [["at most", ""]], "lobe": "bowl", "fill": Brand.ORANGE})
		"MealEaten":
			_add({"kind": "meal", "head": "Ate.", "sub": [["%s · Common Table" % _food(e.item), ""]], "fig": "-" + Usdc.text(int(e.usdc)),
				"ink": OUT_INK, "note": [["energy ", ""], [str(int(e.energy)), "b"]], "lobe": "bowl", "fill": Brand.ORANGE})     # energy: what it is now
		"MealFailed":
			_add({"kind": "meal", "head": "Not eaten.", "sub": [[Refusals.reason(e.get("reason")), ""]], "note": [["nothing paid", ""]], "lobe": "bowl", "fill": Brand.PLATE})
		"FreeMealEaten":
			_add({"kind": "meal", "head": "The free thali.", "sub": [["Common Table · on the town", ""]], "note": [["energy ", ""], [str(int(e.energy)), "b"]], "lobe": "bowl", "fill": Brand.GREEN})
		"VoucherUsed":
			_add({"kind": "meal", "head": "A voucher.", "sub": [["The town pays for your %s" % _food(e.item).to_lower(), ""]], "lobe": "bowl", "fill": Brand.GREEN})
		"RushStarted":
			_add({"kind": "rush", "head": "Go!", "sub": [["%d seconds · %s" % [int(client.city.get("rush", {}).get("run_ms", 0)) / 1000, "1 run left today" if int(e.get("runs_left", 0)) == 1 else "%d runs left today" % int(e.get("runs_left", 0))], ""]], "lobe": "stall", "fill": Brand.GREEN})
		"TicketsEarned":
			_add({"kind": "money", "head": "+%d ticket%s." % [int(e.tickets), "" if int(e.tickets) == 1 else "s"], "sub": [[str(WHY.get(str(e.get("why", "")), "")), ""]],
				"fig": str(int(e.get("total", 0))), "note": [["this week", ""]], "lobe": "ticket", "fill": Brand.BLUE})
		"RewardPaid":
			_add({"kind": "money", "head": "Paid.", "sub": [["%s · into your wallet" % str(e.get("why", "a reward")).capitalize(), ""]], "fig": "+" + Usdc.text(int(e.amount)),
				"ink": Brand.MINT, "lobe": "coin", "fill": Brand.GREEN})
		"RewardPending":
			_add({"kind": "money", "head": "Owed to you.", "sub": [["%s · %s" % [str(e.get("why", "")).capitalize(), WAITING_FOR.get(str(e.get("waiting", "")), "waiting")], ""]],
				"fig": Usdc.text(int(e.amount)), "ink": Brand.CREAM, "lobe": "coin", "fill": TOWN})
		"WalletReady": _add({"kind": "money", "head": "Your wallet.", "sub": [[TownState.short_address(e.get("address")) + " · on your phone", ""]], "lobe": "coin", "fill": TOWN})
		"HumanVerified": _add({"kind": "quest", "head": "Town Pass stamped.", "sub": [["The town can pay you now", ""]], "lobe": "pass", "fill": Brand.GREEN})
		"NameRegistered": _add({"kind": "quest", "head": "Your name.", "sub": [[str(e.get("name", "")), ""]], "lobe": "pass", "fill": Brand.MAGENTA})
		"QuestTaken":
			_add({"kind": "quest", "head": "Quest taken.", "sub": [[TownState.quest_title(client.you, client.city, str(e.quest)), ""]], "fig": "-%d" % int(e.get("energy", 0)) if int(e.get("energy", 0)) > 0 else "",
				"ink": OUT_INK, "note": [["energy", ""]] if int(e.get("energy", 0)) > 0 else [], "lobe": "quest", "fill": Brand.ORANGE})
		"QuestStepSent":
			_add({"kind": "quest", "head": "Sent to the chain.", "sub": [[_step(e), ""]], "lobe": "quest", "fill": TOWN})
		"QuestStepDone":
			_add({"kind": "quest", "head": "Done.", "sub": [[_step(e), ""]], "lobe": "quest", "fill": Brand.GREEN})
		"QuestStepFailed":
			_add({"kind": "quest", "head": "Didn't go through.", "sub": [[Refusals.reason(e.get("reason")), ""]], "note": [["try again", ""]], "lobe": "quest", "fill": Brand.PLATE})
		"QuestDone":
			var r: Dictionary = e.get("reward", {})
			_add({"kind": "quest", "head": "Quest done!", "sub": [[str(e.get("title", "")) + ((" · " + str(r.title)) if r.get("title") != null and str(r.get("title", "")) != "" else ""), ""]],
				"fig": "+" + Usdc.text(int(r.get("usdc", 0))) if int(r.get("usdc", 0)) > 0 else "", "ink": Brand.MINT,
				"note": [["+%d ticket%s" % [int(r.get("tickets", 0)), "" if int(r.get("tickets", 0)) == 1 else "s"], ""]] if int(r.get("tickets", 0)) > 0 else [], "lobe": "quest", "fill": Brand.GREEN})
		"QuestAbandoned": _add({"kind": "quest", "head": "Quest dropped.", "sub": [[TownState.quest_title(client.you, client.city, str(e.quest)), ""]], "lobe": "quest", "fill": TOWN})
		"QuestFailed": _add({"kind": "quest", "head": "Quest failed.", "sub": [[Refusals.reason(e.get("reason")), ""]], "lobe": "quest", "fill": Brand.PLATE})
		"PriceCalled": _add({"kind": "money", "head": "Called: %s." % str(e.get("call", "")), "sub": [["Settles when the next city day opens", ""]], "lobe": "coin", "fill": TOWN})
		"PriceCallSettled":
			var right := bool(e.get("right", false))
			_add({"kind": "money", "head": "Right call!" if right else "Not this time.", "sub": [["You said %s; it went %s" % [str(e.get("call", "")), str(e.get("moved", ""))], ""]], "lobe": "coin", "fill": Brand.GREEN if right else TOWN})
		"RescueComing": _add({"kind": "meal", "head": "Help's coming.", "sub": [["A neighbour is bringing you a thali", ""]], "lobe": "bowl", "fill": Brand.GREEN})
		"RescueMeal": _add({"kind": "meal", "head": "A thali, on the town.", "sub": [["From a neighbour", ""]], "note": [["energy ", ""], [str(int(e.get("energy", 0))), "b"]], "lobe": "bowl", "fill": Brand.GREEN})
		"LoggedIn":
			var streak := int(e.get("streak", 0))
			_add({"kind": "money", "head": "Welcome back.", "sub": [["%s · %d of the last 7 days" % ["day 1 of a streak" if streak <= 1 else "%d days in a row" % streak, int(e.get("week_days", 0))], ""]], "lobe": "chest", "fill": TOWN})
		"Referred": _add({"kind": "money", "head": "Noted.", "sub": [["%s sent you" % str(e.get("by", "")), ""]], "lobe": "ticket", "fill": TOWN})
		"ReferralRewarded": _add({"kind": "money", "head": "Your friend made it.", "sub": [["%s · +%d tickets" % [str(e.get("friend", "")), int(e.get("tickets", 0))], ""]], "lobe": "ticket", "fill": Brand.BLUE})
		"DrawWon": _add({"kind": "money", "head": "You won the draw!", "sub": [["Week %d's draw" % int(e.get("week", 0)), ""]], "fig": "+" + Usdc.text(int(e.get("prize", 0))), "ink": Brand.MINT, "lobe": "ticket", "fill": Brand.GREEN})
		"TownGoalReached": town("The town hit its goal!", "%d meals this week: everyone's next chest is one better" % int(e.get("meals", 0)))
		"DrawCommitted": town("The weekly draw is sealed.", "%d tickets in · prize %s" % [int(e.get("tickets", 0)), Usdc.text(int(e.get("prize", 0)))])
		"FeedPost":
			if str(e.get("kind", "")) in ["draw", "goal"]: return     # said above, as it happened
			town(str(e.text), FEED_PLACES.get(str(e.get("kind", "")), "The town's feed"), e.get("about") != null)

static func _food(item) -> String:
	return str(FoodCounter.LABELS.get(str(item), str(item).capitalize()))

## A step's words from the quest it's in (the event comes before the `you` it changed, so the step is still there).
func _step(e: Dictionary) -> String:
	var q := TownState.quest(client.you, str(e.get("quest", "")))
	for s in q.get("steps", []):
		if str(s.get("id", "")) == str(e.get("step", "")): return QuestMarks.step_words(s)
	return str(q.get("title", ""))

## Orders come quicker than they can each be shown: one still waiting takes the next one in. served: the server's count this run.
func _order(served: int) -> void:
	var last := {}
	for m in _q:
		if m.get("tag", "") == "order": last = m
	if last.is_empty():
		last = {"kind": "rush", "tag": "order", "head": "Served.", "ink": Brand.MINT, "note": [["best ", ""], ["{best}", "b"]], "lobe": "stall", "fill": Brand.GREEN}
		_add(last)
	last.sub = [["%s this run · %s" % ["1 order" if served == 1 else "%d orders" % served, STALL], ""]]
	last.fig = str(served)

## The mentor's line (MentorChat's corner hands it over). Only the newest waits.
func mentor_says(line: String) -> void:
	for i in range(_q.size() - 1, -1, -1):
		if _q[i].kind == "mentor": _q.remove_at(i)
	_add({"kind": "mentor", "head": "A thought.", "sub": [[line, ""]], "note": [["H", "key"], ["Ask", "w"]], "lobe": "mentor", "fill": Brand.MAGENTA})

## The town has changed (the feed, or GameHud's toast).
func town(head: String, sub := "", someone := false) -> void:
	_add({"kind": "town", "head": head, "sub": [[sub, ""]] if sub != "" else [], "lobe": "face" if someone else "coin", "fill": TOWN})

func _add(m: Dictionary) -> void:
	queue_in(_q, m)

## Into line by kind, after any of its own kind or ahead of it; the line never grows past WAITING.
static func queue_in(q: Array[Dictionary], m: Dictionary) -> void:
	var place: int = KINDS[m.kind][0]
	var i := q.size()
	while i > 0 and int(KINDS[q[i - 1].kind][0]) > place: i -= 1
	q.insert(i, m)
	if q.size() > WAITING: q.pop_back()

# --- each frame --------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_clock(delta)
	if _m.get("kind", "") == "mentor" and world.mentor.is_open: _done()   # H: the chat has it now
	var hide := _hidden()
	if visible == hide: visible = not hide
	if hide:
		_g = 0.0
		return
	_root.position = Vector2(size.x * 0.5, TOP * REM)
	_tick_sun(delta)
	_tick_run(delta)
	_tick_glance(delta)
	_tick_moment(delta)
	_place_shapes()

func _hidden() -> bool:
	if client.you.is_empty(): return true
	if (world.title and world.title.is_up) or world.opening.playing or world.director.busy or world.blast.playing: return true
	if world.moments and world.moments.running: return true
	return world.any_sheet_open() and not world.phone.is_open

## The city day's clock, counted down here between the server's words: its word wins whenever it has spoken.
func _tick_clock(delta: float) -> void:
	var city := client.city
	var said := float(city.get("day_ms", 0)) - float(city.get("day_elapsed_ms", 0))
	_left_ms = said if said != _last_said else maxf(_left_ms - delta * 1000.0, 0.0)
	_last_said = said
	var s := ceili(_left_ms / 1000.0)
	if s == _shown_s: return
	_shown_s = s
	_clock.text = "%d:%02d" % [s / 60, s % 60] if s < 3600 else "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60]
	_day.text = str(int(city.get("day", 0)))

func _tick_sun(delta: float) -> void:
	_sun_in -= delta
	if _sun_in > 0.0: return
	_sun_in = 0.25
	var to_sun = world.look.get("to_sun")
	if not to_sun is Vector3: return
	var t := sun_t(to_sun)
	var night: bool = world.mode == "night"
	if absf(t - _sun_t) > 0.002 or night != _night:
		_sun_t = t
		_night = night
		_dial.queue_redraw()

## Where the sun (or the moon) is across the sky, 0 at dawn on the left to 1 at dusk on the right: its height against its east-west
## place, so noon is the top of the arc.
static func sun_t(to_sun: Vector3) -> float:
	return clampf(atan2(to_sun.y, to_sun.x) / PI, 0.0, 1.0)

## The run: its track fills towards the most customers a run has (city.most_orders_per_run), and under it the count and your best.
func _tick_run(delta: float) -> void:
	var on: bool = world.stall.in_rush
	if on and not _in_rush: _run_name.text = "Market Rush"
	_in_rush = on
	_b = move_toward(_b, 1.0 if on else 0.0, delta / OPEN)
	if _b <= 0.0: return
	var served := int(client.you.get("served", 0)) if bool(client.you.get("in_rush", false)) else 0
	var k := served / maxf(float(client.city.get("most_orders_per_run", 0)), 1.0)
	if absf(k - _track_k) > 0.002:
		_track_k = k
		_run_track.queue_redraw()
	_run_clock.text = TownState.clock(TownState.rush_left(client.you, client.now_ms()))
	var best := int(client.you.get("best_today", 0))
	var left := int(client.you.get("runs_left", 0))
	var said := "%d %d %d" % [served, best, left]
	if said == _run_said: return
	_run_said = said
	_runs(_run_sub, [["Served ", ""], [str(served), "mint"], [" · best today ", ""], [str(best), "b"], [" · runs left ", ""], [str(left), "b"]], 1.2, Brand.FONT_DISPLAY, 1.2)

func _tick_glance(delta: float) -> void:
	var at := _root.get_local_mouse_position()
	var want := Input.is_key_pressed(KEY_ALT) or (Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _hit().has_point(at))
	if want and _g == 0.0: _fill_card()
	_g = move_toward(_g, 1.0 if want else 0.0, delta / GLANCE_IN)

## Where the pointer opens the glance: the island as it is, and once open, the card too.
func _hit() -> Rect2:
	if _g > 0.0: return Rect2(Vector2(-CARD.x * 0.5 - 1.0, 0.0) * REM, Vector2(CARD.x + 2.0, REST.y + CARD.y + 2.0) * REM)
	var r := Rect2(_pill_now.position * REM, _pill_now.size * REM)
	if _lobe_now.z > 0.0: r = r.merge(Rect2((Vector2(_lobe_now.x, _lobe_now.y) - Vector2.ONE * _lobe_now.z) * REM, Vector2.ONE * _lobe_now.z * 2.0 * REM))
	return r

func _tick_moment(delta: float) -> void:
	if _m.is_empty():
		_rest_in -= delta
		if _rest_in <= 0.0 and not _q.is_empty() and _g == 0.0:
			_open(_q.pop_front())
		elif _b >= 1.0 and not _said_run:
			_said_run = true
			held.emit("rush")
		elif _b <= 0.0 and not _said_rest:
			_said_rest = true
			held.emit("rest")
		if _b <= 0.0: _said_run = false
		return
	if not (_phase == 2 and _g > 0.0):   # a glance holds the moment where it is
		_t += delta
		_since += delta
	match _phase:
		1:
			if _t >= OPEN:
				_phase = 2
				_t = 0.0
				held.emit(_m.kind)
		2:
			if _t >= float(KINDS[_m.kind][1]):
				_phase = 3
				_t = 0.0
		3:
			if _t >= SHUT: _done()

func _done() -> void:
	_m = {}
	_phase = 0
	_rest_in = BETWEEN

func _place_shapes() -> void:
	var b := smoothstep(0.0, 1.0, _b)
	var ge := smoothstep(0.0, 1.0, _g)
	var pill := _mix(_rest_pill(), _pill_of(RUN_W), b)
	var lobe := _rest_lobe().lerp(_lobe_of(RUN_W), b)
	var k := 0.0
	var a_m := 0.0
	var a_base := 1.0
	var lift := 0.0
	match _phase:
		1:
			k = ease_out(_t / OPEN)
			a_m = clampf((_t - 0.22) / 0.28, 0.0, 1.0)
			a_base = 1.0 - clampf(_t / 0.15, 0.0, 1.0)
			lift = (1.0 - a_m) * 0.5
		2:
			k = 1.0
			a_m = 1.0
			a_base = 0.0
		3:
			k = 1.0 - ease_out(_t / SHUT)
			a_m = 1.0 - clampf(_t / 0.2, 0.0, 1.0)
			a_base = clampf((_t - SHUT + 0.2) / 0.2, 0.0, 1.0)
			lift = -(1.0 - a_m) * 0.3
	if _phase > 0:
		pill = _mix(pill, _pill_of(_w), k)
		lobe = lobe.lerp(_lobe_of(_w), k)
	pill = _mix(pill, _rest_pill(), ge)
	lobe = lobe.lerp(_rest_lobe(), ge)
	if (_phase == 0 and _b <= 0.0) or ge >= 1.0: lobe.z = 0.0    # at rest the lobe is folded into the pill
	_pill_now = pill
	_lobe_now = lobe
	var a_rest := maxf(a_base * (1.0 - b), ge)
	var a_run := a_base * b * (1.0 - ge)
	a_m *= 1.0 - ge
	_rest.modulate.a = a_rest
	_rest.visible = a_rest > 0.0
	_run.modulate.a = a_run
	_run.visible = a_run > 0.0
	_moment.modulate.a = a_m
	_moment.visible = a_m > 0.0
	_moment.position.y = lift * REM
	var fill := Color(0, 0, 0, 0)
	if a_m > 0.0 and a_m >= a_run: fill = Color(_m.fill, a_m)
	elif a_run > 0.0: fill = Color(Brand.GREEN, a_run)
	var sheen := 0.0
	if _phase > 0: sheen = clampf(_since / 0.3, 0.0, 1.0) if _since < 0.3 else clampf(1.0 - (_since - 0.3) / 0.8, 0.0, 1.0)
	var card := Rect2()
	if ge > 0.0: card = _mix(Rect2(-REST.x * 0.4, REST.y - 1.6, REST.x * 0.8, 1.6), Rect2(-CARD.x * 0.5, REST.y + 0.9, CARD.x, CARD.y), ge)
	_card.visible = ge > 0.5
	_card.modulate.a = clampf((ge - 0.55) / 0.45, 0.0, 1.0)
	_card.position.y = (REST.y + 0.9 - 1.2 * (1.0 - ge)) * REM
	var n := _q.size() if not _m.is_empty() else 0
	if n != _dots_n:
		_dots_n = n
		_dots.queue_redraw()
	_dots.modulate.a = a_m
	var h := BOX.y if ge > 0.0 else 120.0
	if h != _box_h:
		_box_h = h
		_shape.size = Vector2(BOX.x, h)
		_mat.set_shader_parameter(&"size", _shape.size)
	_mat.set_shader_parameter(&"pill", Vector4(pill.position.x * REM + BOX_AT.x, pill.position.y * REM + BOX_AT.y, pill.size.x * REM, pill.size.y * REM))
	_mat.set_shader_parameter(&"lobe", Vector3(lobe.x * REM + BOX_AT.x, lobe.y * REM + BOX_AT.y, lobe.z * REM))
	_mat.set_shader_parameter(&"card", Vector4(card.position.x * REM + BOX_AT.x, card.position.y * REM + BOX_AT.y, card.size.x * REM, card.size.y * REM))
	_mat.set_shader_parameter(&"lobe_fill", fill)
	_mat.set_shader_parameter(&"sheen", sheen)

# --- geometry, in rem from the island's top centre ---------------------------------------------------------------------

static func _rest_pill() -> Rect2:
	return Rect2(-REST.x * 0.5, 0.0, REST.x, REST.y)

static func _rest_lobe() -> Vector3:
	return Vector3(0.0, REST.y * 0.5, 1.6)

## A moment's pill, w wide, right of its lobe; the two together are centred.
static func _pill_of(w: float) -> Rect2:
	return Rect2(-(H + GAP + w) * 0.5 + H + GAP, 0.0, w, H)

static func _lobe_of(w: float) -> Vector3:
	return Vector3(-(H + GAP + w) * 0.5 + H * 0.5, H * 0.5, H * 0.5)

static func _mix(a: Rect2, b: Rect2, k: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, k), a.size.lerp(b.size, k))

## The boards' cubic-bezier(.2, .9, .25, 1).
static func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var t := x
	for i in 6:
		var u := 1.0 - t
		var at := 3.0 * u * u * t * 0.2 + 3.0 * u * t * t * 0.25 + t * t * t - x
		var slope := 3.0 * u * u * 0.2 + 6.0 * u * t * 0.05 + 3.0 * t * t * 0.75
		t = clampf(t - at / maxf(slope, 0.0001), 0.0, 1.0)
	var v := 1.0 - t
	return 3.0 * v * v * t * 0.9 + 3.0 * v * t * t + t * t * t

# --- a moment's words ------------------------------------------------------------------------------------------------

func _open(m: Dictionary) -> void:
	_m = m
	_phase = 1
	_t = 0.0
	_since = 0.0
	_head.text = m.head
	_fig.text = m.get("fig", "")
	_fig.visible = _fig.text != ""
	_fig.add_theme_color_override("font_color", m.get("ink", Brand.CREAM))
	var end := _runs(_note, m.get("note", []).map(_fill_in), 1.1 if not _keyed(m.get("note", [])) else 1.3, Brand.FONT_NUMBER, 1.3)
	if _fig.visible: end = maxf(end, _fig.get_combined_minimum_size().x)
	_end.visible = end > 0.0
	var widest := MAX_W
	var sub: Array = m.get("sub", [])
	if m.kind == "mentor":
		# the mentor's first sentence, whole; the pill grows to MENTOR_W, then whole words and "…"
		widest = MENTOR_W
		var room := (widest - 4.2 - 1.6) * REM - end
		sub = [[whole_words(first_sentence(str(sub[0][0])), room, Brand.FONT_BODY, roundi(1.2 * REM)), ""]]
	var body := maxf(_fit(_head), _runs(_sub, sub, 1.2 if not _keyed(sub) else 1.3, Brand.FONT_DISPLAY, 1.2))
	var need := 4.2 + (body + (1.6 * REM + end if end > 0.0 else 0.0)) / REM
	_w = clampf(maxf(float(KINDS[m.kind][2]), need), 0.0, widest)
	var pill := _pill_of(_w)
	_text.position = Vector2(pill.position.x + 1.8, 0.0) * REM
	_text.size = Vector2(_w - 4.2, H) * REM
	var lobe := _lobe_of(_w)
	_set_icon(_icon, m.lobe, Vector2(lobe.x, lobe.y))
	_dots.position.y = (H + 1.2) * REM

## Up to and with the first full stop (or ! or ?) that ends a sentence; the whole line if there is none.
static func first_sentence(line: String) -> String:
	line = line.strip_edges()
	for i in line.length() - 1:
		if line[i] in ".!?" and line[i + 1] == " ": return line.left(i + 1)
	return line

## As many whole words as fit in room px, then "…"; the line as it is if it fits.
static func whole_words(line: String, room: float, font: Font, px: int) -> String:
	if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= room: return line
	var out := ""
	for word in line.split(" ", false):
		var longer := word if out == "" else out + " " + word
		if font.get_string_size(longer + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room: break
		out = longer
	return out.rstrip(",;:") + "…"

## Words in a run: [text, how]. "" small print, "b" a figure, "mint" a figure gained, "w" plain cream, "key" a key cap.
func _runs(box: HBoxContainer, runs: Array, rem: float, figure: Font, figure_rem: float) -> float:
	for old in box.get_children():
		box.remove_child(old)
		old.queue_free()
	var w := 0.0
	for r in runs:
		var part: Label
		match str(r[1]):
			"key": part = GameHud.key_cap(r[0], roundi(1.3 * REM))
			"b": part = _label(figure, figure_rem, Brand.CREAM, r[0])
			"mint": part = _label(figure, figure_rem, Brand.MINT, r[0])
			"w": part = _label(Brand.FONT_BODY, rem, Brand.CREAM, r[0])
			_: part = _label(Brand.FONT_BODY, rem, MUTED, r[0])
		part.size_flags_vertical = Control.SIZE_SHRINK_CENTER if r[1] == "key" else Control.SIZE_SHRINK_END
		box.add_child(part)
		w += part.get_combined_minimum_size().x if r[1] == "key" else _fit(part)
	var gap := roundi(0.8 * REM) if _keyed(runs) else 0
	box.add_theme_constant_override("separation", gap)
	return w + gap * maxi(runs.size() - 1, 0)

static func _keyed(runs: Array) -> bool:
	return runs.any(func(r): return r[1] == "key")

## A label's width, cut short with an ellipsis past MAX_TEXT.
func _fit(l: Label) -> float:
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.custom_minimum_size.x = 0.0
	var w := l.get_minimum_size().x
	if w > MAX_TEXT * REM:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = MAX_TEXT * REM
		w = MAX_TEXT * REM
	return w

## What the server has said by the time the moment shows.
func _fill_in(r: Array) -> Array:
	match str(r[0]):
		"{best}": return [str(int(client.you.get("best_run", 0))), r[1]]
		"{today}": return [str(int(client.you.get("best_today", 0))), r[1]]
	return r

func _set_icon(rect: TextureRect, what: String, at: Vector2) -> void:
	var side := 2.6
	rect.material = null
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	match what:
		"coin":
			rect.texture = COIN
			rect.material = _coin_mat
			side = 3.4
		"face", "mentor":
			rect.texture = MentorChat.FACE if what == "mentor" else PlayerFace.FACE
			rect.material = _ringed_mat if what == "mentor" else _face_mat
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			side = H
		_: rect.texture = _svg(what)
	rect.size = Vector2.ONE * side * REM
	rect.position = at * REM - rect.size * 0.5

## The boards' line icons, drawn once from their own SVG.
static func _svg(what: String) -> Texture2D:
	if not _icons.has(what):
		var img := Image.new()
		img.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#FFF8E3" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % ICONS[what], 3.0)
		_icons[what] = ImageTexture.create_from_image(img)
	return _icons[what]

# --- the glance ------------------------------------------------------------------------------------------------------

func _fill_card() -> void:
	var you := client.you
	_energy_n = int(you.get("energy", 0))
	_pips.queue_redraw()
	_runs(_energy, [[str(_energy_n), "b"], [" of 100", ""]], 1.1, Brand.FONT_NUMBER, 1.3)
	_best.text = str(int(you.get("best_run", 0)))
	var rank = you.get("ranks", {}).get("rush")
	_runs(_best_sub, [["#%d" % int(rank), "b"], [" on the board", ""]] if rank != null else [["orders in a run", ""]], 1.1, Brand.FONT_NUMBER, 1.3)
	_day_big.text = str(int(client.city.get("day", 0)))
	var season: Dictionary = client.city.get("season", {})
	_runs(_day_sub, [["season ", ""], [str(int(season.get("number", 0))), "b"]], 1.1, Brand.FONT_NUMBER, 1.3)

# --- building ----------------------------------------------------------------------------------------------------------

func _label(font: Font, rem: float, ink: Color, text := "") -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", roundi(rem * REM))
	l.add_theme_color_override("font_color", ink)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Letter-spaced, as the boards' small capitals.
static func _spaced(font: Font, rem: float, em: float) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = roundi(rem * REM * em)
	return f

func _cap(text: String) -> Label:
	return _label(_spaced(Brand.FONT_BODY, 1.0, 0.14), 1.0, MUTED, text)

func _build_rest() -> void:
	_rest.alignment = BoxContainer.ALIGNMENT_CENTER
	_rest.add_theme_constant_override("separation", roundi(REM))
	_rest.position = Vector2(-REST.x * 0.5, 0.0) * REM
	_rest.size = REST * REM
	_dial.custom_minimum_size = Vector2(3.4, 1.9) * REM
	_dial.draw.connect(_draw_dial)
	_clock = _label(Brand.FONT_NUMBER, 2.4, Brand.CREAM)
	var sep := ColorRect.new()
	sep.color = RULE
	sep.custom_minimum_size = Vector2(1.0, 2.2 * REM)
	var day := HBoxContainer.new()
	day.add_theme_constant_override("separation", roundi(0.4 * REM))
	var word := _label(Brand.FONT_BODY, 1.4, Brand.CREAM, "Day")
	_day = _label(Brand.FONT_NUMBER, 1.8, Brand.CREAM)
	for part in [word, _day]:
		part.size_flags_vertical = Control.SIZE_SHRINK_END
		day.add_child(part)
	for part in [_dial, _clock, _cap("LEFT"), sep, day]:
		part.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_rest.add_child(part)
	_root.add_child(_rest)

## The board's dial: a dashed arc over the horizon, filled behind the sun as the day goes; the moon and two stars at night.
func _draw_dial() -> void:
	var u := _dial.size.x / 32.0
	var mid := Vector2(16, 16) * u
	var r := 11.0 * u
	for i in 11: _dial.draw_arc(mid, r, PI + (i * 3.4 + 0.3) / 11.0, PI + (i * 3.4 + 1.5) / 11.0, 3, RULE, 1.4 * u, true)
	var glow := SUN_LOW if _sun_t < 0.18 or _sun_t > 0.82 else SUN_HIGH
	if not _night and _sun_t > 0.0: _dial.draw_arc(mid, r, PI, PI + PI * _sun_t, 24, Color(glow, 0.75), 1.4 * u, true)
	_dial.draw_line(Vector2(2, 16.2) * u, Vector2(30, 16.2) * u, HORIZON, 1.2 * u, true)
	var at := mid + Vector2.from_angle(PI + PI * _sun_t) * r
	if _night:
		_dial.draw_circle(Vector2(7, 6) * u, 0.7 * u, Brand.CREAM_MUTED)
		_dial.draw_circle(Vector2(25, 9) * u, 0.6 * u, Brand.CREAM_MUTED)
		_dial.draw_circle(at, 3.2 * u, Brand.CREAM_MUTED)
		_dial.draw_circle(at + Vector2(1.6, -1.0).rotated(PI * _sun_t - PI * 0.5) * u, 2.7 * u, Brand.PLATE)
	else:
		_dial.draw_circle(at, 5.0 * u, Color(glow, 0.22))
		_dial.draw_circle(at, 2.8 * u, glow)

func _build_run() -> void:
	var lobe := _lobe_of(RUN_W)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_set_icon(icon, "stall", Vector2(lobe.x, lobe.y))
	_run.add_child(icon)
	var pill := _pill_of(RUN_W)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", roundi(0.35 * REM))
	body.position = Vector2(pill.position.x + 1.8, 0.0) * REM
	body.size = Vector2(RUN_W - 4.2, H) * REM
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(0.8 * REM))
	_run_name = _label(Brand.FONT_EDITORIAL_ITALIC, 2.5, Brand.CREAM)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_clock = _label(Brand.FONT_NUMBER, 2.2, Brand.CREAM)
	for part in [_run_name, push, _run_clock, _cap("LEFT")]:
		part.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(part)
	body.add_child(row)
	_run_track.custom_minimum_size.y = 0.5 * REM
	for s in [_bar_off, _bar_on, _bar_out]: (s as StyleBoxFlat).set_corner_radius_all(roundi(REM))
	_bar_off.bg_color = TRACK
	_bar_on.bg_color = Brand.GREEN
	_bar_out.bg_color = Brand.ORANGE
	_run_track.draw.connect(func():
		var s := _run_track.size
		_run_track.draw_style_box(_bar_off, Rect2(Vector2.ZERO, s))
		if _track_k > 0.0: _run_track.draw_style_box(_bar_out, Rect2(0, 0, maxf(s.x * minf(_track_k, 1.0), s.y), s.y)))
	body.add_child(_run_track)
	body.add_child(_run_sub)
	_run.add_child(body)
	_root.add_child(_run)

func _build_moment() -> void:
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_moment.add_child(_icon)
	_text.add_theme_constant_override("separation", roundi(1.6 * REM))
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", roundi(0.35 * REM))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head = _label(Brand.FONT_EDITORIAL_ITALIC, 2.5, Brand.CREAM)
	body.add_child(_head)
	body.add_child(_sub)
	_text.add_child(body)
	_end.alignment = BoxContainer.ALIGNMENT_CENTER
	_end.add_theme_constant_override("separation", roundi(0.35 * REM))
	_fig = _label(Brand.FONT_DISPLAY, 3.2, Brand.CREAM)
	for part in [_fig, _note]:
		part.size_flags_horizontal = Control.SIZE_SHRINK_END
		_end.add_child(part)
	_text.add_child(_end)
	_moment.add_child(_text)
	_root.add_child(_moment)

## A dot under the island for each moment still to come.
func _build_dots() -> void:
	_dots.position = Vector2(0.0, (H + 1.2) * REM)
	_dots.draw.connect(func():
		var d := 0.7 * REM
		var step := 1.3 * REM
		var x0 := -(_dots_n * step - 0.6 * REM) * 0.5 + d * 0.5
		for i in _dots_n:
			_dots.draw_circle(Vector2(x0 + i * step, d * 0.5 + 0.2 * REM), d * 0.5 + 1.0, Color(0, 0, 0, 0.3))
			_dots.draw_circle(Vector2(x0 + i * step, d * 0.5), d * 0.5, Brand.CREAM))
	_root.add_child(_dots)

func _build_card() -> void:
	_card.position = Vector2(-CARD.x * 0.5, REST.y + 0.9) * REM
	_card.size = CARD * REM
	for side in [["margin_left", 2.6], ["margin_right", 2.6], ["margin_top", 2.2], ["margin_bottom", 2.0]]: _card.add_theme_constant_override(side[0], roundi(side[1] * REM))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(1.6 * REM))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", roundi(1.6 * REM))
	_best = _label(Brand.FONT_DISPLAY, 2.6, Brand.CREAM)
	_day_big = _label(Brand.FONT_DISPLAY, 2.6, Brand.CREAM)
	_pips.custom_minimum_size = Vector2(5 * 2.0 + 4 * 0.4, 0.9 + 0.9) * REM
	_pips.draw.connect(func():
		var on := roundi(_energy_n / 20.0)
		for i in 5: _pips.draw_style_box(_bar_on if i < on else _bar_off, Rect2(Vector2(i * 2.4, 0.6) * REM, Vector2(2.0, 0.9) * REM)))
	for cell in [["ENERGY", _pips, _energy], ["BEST RUN", _best, _best_sub], ["DAY", _day_big, _day_sub]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", roundi(0.5 * REM))
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_cap(cell[0]))
		v.add_child(cell[1])
		v.add_child(cell[2])
		stats.add_child(v)
	column.add_child(stats)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(push)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", roundi(0.7 * REM))
	for k in [["H", "Mentor"], ["N", "Paper"], ["Tab", "Phone"]]:
		if keys.get_child_count() > 0:
			var space := Control.new()
			space.custom_minimum_size.x = 0.2 * REM
			keys.add_child(space)
		var cap := GameHud.key_cap(k[0], roundi(1.3 * REM))
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		keys.add_child(cap)
		var word := _label(Brand.FONT_BODY, 1.2, MUTED, k[1])
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		keys.add_child(word)
	column.add_child(keys)
	_card.add_child(column)
	_card.visible = false
	_root.add_child(_card)
