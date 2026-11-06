class_name KeyStrip
extends PanelContainer
## On the ferry's deck, the first time: a small strip of the keys that move you, low in the middle of the screen. W A S D walk, the
## mouse looks, E uses. Each key fades once it's been used, and its word once all its keys have; when everything has, the strip goes
## for good. The keys are read from the real bindings.

const GROUPS := [[["move_forward", "move_left", "move_back", "move_right"], "walk"], [["*mouse"], "look"], [["interact"], "use"]]
const LOOKED := 160.0              # px of mouse travel that counts as looking round
const USED_A := 0.2                # a used key, faded back
const FADE := 0.25                 # s
const BOTTOM := 56.0               # px off the bottom of the screen

var want := false                  # the opening says when it's the time
var _caps := {}                    # action -> its cap
var _words := []                   # [word, its actions]
var _used := {}
var _looked := 0.0
var _gone := false
var _fade: Tween

func _ready() -> void:
	var look := StyleBoxFlat.new()
	look.bg_color = Brand.PLATE
	look.border_color = Brand.CREAM
	look.set_border_width_all(3)
	look.set_corner_radius_all(20)
	look.content_margin_left = 16
	look.content_margin_right = 16
	look.content_margin_top = 9
	look.content_margin_bottom = 9
	add_theme_stylebox_override("panel", Brand.as_plate(look))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	for g in GROUPS:
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 5)
		for action in g[0]:
			var cap := GameHud.key_cap("Mouse" if action == "*mouse" else GameHud._key_name(action), 13)
			_caps[action] = cap
			group.add_child(cap)
		var word := GameHud.on_scene(Label.new(), Brand.FONT_BODY, 14)
		word.text = g[1]
		word.add_theme_constant_override("outline_size", 0)
		word.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		_words.append([word, g[0]])
		var gap := Control.new()
		gap.custom_minimum_size.x = 3
		group.add_child(gap)
		group.add_child(word)
		row.add_child(group)
	add_child(row)
	modulate.a = 0.0
	visible = false

func _process(_delta: float) -> void:
	var show := want and not _gone
	if show != visible and (_fade == null or not _fade.is_running()):
		if show: visible = true
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0 if show else 0.0, FADE).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		if not show: _fade.tween_callback(hide)
	if visible:
		reset_size()
		var screen := get_viewport_rect().size
		position = Vector2((screen.x - size.x) * 0.5, screen.y - size.y - BOTTOM)

func _input(e: InputEvent) -> void:
	if not want or _gone: return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_looked += (e as InputEventMouseMotion).relative.length()
		if _looked > LOOKED: _use("*mouse")
		return
	for action in _caps:
		if action != "*mouse" and e.is_action_pressed(action): _use(action)

func _use(action: String) -> void:
	if _used.has(action): return
	_used[action] = true
	create_tween().tween_property(_caps[action], "modulate:a", USED_A, FADE).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	for w in _words:
		if (w[1] as Array).all(func(a): return _used.has(a)):
			create_tween().tween_property(w[0], "modulate:a", USED_A, FADE).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if _used.size() == _caps.size(): _gone = true
