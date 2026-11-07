class_name CameraRig
extends Node3D
## Player camera with three views, cycled with C:
##   top   - the high follow camera looking down on the town: rotate (Z/X or right-drag), wheel zoom
##   third - close behind the player at head height: mouse look, wheel zoom
##   first - from the player's eyes: mouse look and a light head bob; the avatar only casts its shadow
## It follows by itself, like the camera of a modern third-person game:
##   - walking sideways swings it round, as if it trailed the player on a string; walking on ahead brings it
##     round behind them; walking towards it never flips it round
##   - it leads a little into the direction of travel, levels its pitch to the slope ahead (third person),
##     widens when sprinting and rides critically damped springs, so starts, stops and steps are soft
##   - it keeps out of walls, the ground and the river: third person pulls in, the top view first climbs
##     to look over a building in the way
## A turn by hand (mouse, right-drag, Z/X) takes over at once; the follow eases back in shortly after.
## In third and first person the cursor is captured: Esc frees it, a click takes it back. Every view keeps
## its own angle and zoom, and the camera glides from one to the next. Entering a building glides in on its
## interior from above (focus_on), whatever the view; leaving returns to it.

signal mode_changed(mode: String)

const MODES := ["top", "third", "first"]
const LABELS := {"top": "Top-down", "third": "Third person", "first": "First person"}
# per view: pivot height above the feet, zoom range (m), pitch range (deg), field of view (deg); the follow:
# sideways swing (1 = a taut string), recentring rate (/s), lead (s of travel), spring times (s, across and
# up), and the extra field of view (deg) and distance (fraction) at a sprint
const VIEWS := {
	"top": {"height": 1.0, "dist": Vector2(7.0, 30.0), "pitch": Vector2(-72.0, -25.0), "fov": 38.0,
		"swing": 0.45, "recentre": 0.45, "lead": 0.8, "spring": Vector2(0.3, 0.45), "sprint_fov": 3.0, "sprint_dist": 0.08},
	"third": {"height": 1.6, "dist": Vector2(2.2, 9.0), "pitch": Vector2(-65.0, 40.0), "fov": 62.0,
		"swing": 0.45, "recentre": 0.5, "lead": 0.25, "spring": Vector2(0.1, 0.22), "sprint_fov": 7.0, "sprint_dist": 0.12},
	"first": {"height": 1.62, "dist": Vector2.ZERO, "pitch": Vector2(-85.0, 85.0), "fov": 72.0,
		"swing": 0.0, "recentre": 0.0, "lead": 0.0, "spring": Vector2.ZERO, "sprint_fov": 5.0, "sprint_dist": 0.0},
}
const MOUSE_LOOK := 0.0024       # radians per pixel of mouse travel
const GLIDE := 0.7               # seconds the camera takes to glide to another view
const HANDS_OFF := Vector2(0.35, 1.4)   # seconds after a turn by hand before the swing / the recentring return
const TRAVEL_PITCH := -11.0      # third person: the pitch it levels out to while walking (deg)
const HOLD_PITCH := -25.0        # the pitch it eases to while holding a view (deg)

var target: Node3D
var floor_at := Callable()       # f(x, z) -> lowest height the camera may sink to (ground or water)
var mode := "top"
var indoors := false             # the top view shows only a head and a floor in a room: it gives way to third person
var _top_outside := false        # it was the top view at the door, and will be again
var hold_yaw = null              # a heading to come back to while working at something (hold_view)
var _hold_pitch := HOLD_PITCH    # and how steeply it looks
var _hold_side := 0.0            # and how far over the shoulder (m)
var _side := 0.0
var idle_drift := true           # the player's setting
var riding := false              # on something fast: a lower camera and a wider lens
var _ride := 0.0
var _idle_for := 0.0             # s since anyone touched anything
var _idle_k := 0.0
const IDLE_AFTER := 40.0         # s with no input before the camera starts to drift round him
const IDLE_TURN := 0.09          # radians a second
const RIDE_FOV := 10.0           # deg wider
const RIDE_LOW := 0.45           # m lower
var yaw := deg_to_rad(-20.0)
var pitch := deg_to_rad(-48.0)
var distance := 17.0
var fov := 38.0
var _yaw := yaw
var _pitch := pitch
var _dist := distance
var _height := 1.0
var _clear := distance           # how far back the camera can sit without clipping
var _lift := 0.0                 # top view: extra downward pitch to see over a building in the way
var _focus_point = null          # Vector3 or null
var _drag := false
var fov_bonus := 0.0              # the player's field of view, from settings
var _free_cursor := false        # Esc in a mouse-look view: the cursor stays free until a click
var _cursor_held := false        # something on screen wants the mouse (the phone): nothing else takes it back
var _skip_motion := 0
var _glide := 0.0
var _manual := 10.0              # seconds since the camera was last turned by hand
var _moving := 0.0               # seconds the player has been walking
var _lead := Vector3.ZERO
var _sprint := 0.0
var _roll := 0.0
var _follow := Vector3.ZERO      # spring-damped point the camera orbits
var _follow_v := Vector3.ZERO
var _saved := {"top": [deg_to_rad(-48.0), 17.0], "third": [deg_to_rad(-12.0), 4.5], "first": [deg_to_rad(-4.0), 0.0]}
var _probe := PhysicsShapeQueryParameters3D.new()
var cam: Camera3D
var _pivot: Node3D
const LIFT_LOOK_EVERY := 0.12    # s
var _lift_in := 0.0
var _lift_to := 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # moved every frame by hand, and so is all under it
	_pivot = Node3D.new()
	add_child(_pivot)
	cam = Camera3D.new()
	cam.fov = fov
	cam.near = 0.3
	cam.far = 400.0
	_pivot.add_child(cam)
	cam.make_current()
	var ball := SphereShape3D.new()
	ball.radius = 0.2
	_probe.shape = ball
	if target:
		_follow = _target_pos() + Vector3(0, _height, 0)
		global_position = _follow

static var look_speed := 1.0         # Settings: how far the view turns for the mouse
static var invert_y := false

func _input(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton or (e is InputEventMouseMotion and e.relative.length() > 2.0): _idle_for = 0.0

func _unhandled_input(e: InputEvent) -> void:
	if Screens.holding():     # a screen is up: its wheel, drag and keys are its own
		_drag = false
		return
	if e.is_action_pressed("camera_mode"):
		cycle_mode()
	elif e is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if _skip_motion > 0:
				_skip_motion -= 1      # the jump of the cursor being warped to the centre on capture
				return
			var rel: Vector2 = e.relative.limit_length(150.0) * look_speed
			yaw -= rel.x * MOUSE_LOOK
			pitch = _clamp_pitch(pitch - rel.y * MOUSE_LOOK * (-1.0 if invert_y else 1.0))
			_manual = 0.0
		elif _drag:
			yaw -= e.relative.x * 0.006 * look_speed
			pitch = _clamp_pitch(pitch - e.relative.y * 0.004 * look_speed * (-1.0 if invert_y else 1.0))
			_manual = 0.0
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _zoom(1.1)
		elif e.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]: _drag = e.pressed
		elif e.button_index == MOUSE_BUTTON_LEFT and e.pressed: _free_cursor = false
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and _focus_point == null and mode != "top":
		_free_cursor = true

func _view() -> Dictionary:
	return VIEWS.top if _focus_point != null else VIEWS[mode]

func _clamp_pitch(p: float) -> float:
	var r: Vector2 = _view().pitch
	return clampf(p, deg_to_rad(r.x), deg_to_rad(r.y))

func _zoom(f: float) -> void:
	var r: Vector2 = _view().dist
	if r.y > 0.0: distance = clampf(distance * f, r.x, r.y)

func _target_pos() -> Vector3:
	return target.smooth_position() if target.has_method("smooth_position") else target.global_position

func _process(delta: float) -> void:
	if delta <= 0.0: return
	var turn := Input.get_axis("rotate_right", "rotate_left")
	if turn != 0.0 and not Screens.holding():
		yaw += 1.8 * turn * delta * look_speed
		_manual = 0.0
	_manual += delta
	_glide = maxf(_glide - delta, 0.0)
	# nobody's doing anything: the camera wanders slowly round him until they are
	_idle_for += delta
	var hv_now: Vector3 = (target.velocity if target is CharacterBody3D else Vector3.ZERO) * Vector3(1, 0, 1)
	if hv_now.length() > 0.2: _idle_for = 0.0
	_idle_k = move_toward(_idle_k, 1.0 if _idle_for > IDLE_AFTER and hold_yaw == null and idle_drift else 0.0, delta * 0.5)
	if _idle_k > 0.0 and mode == "third": yaw += IDLE_TURN * _idle_k * delta
	_ride = move_toward(_ride, 1.0 if riding else 0.0, delta * 1.5)
	_side = lerpf(_side, _hold_side if hold_yaw != null else 0.0, 1.0 - exp(-3.0 * delta))
	var v: Dictionary = _view()
	var top := mode == "top" or _focus_point != null
	var eyes := mode == "first" and not top
	var tp := _target_pos()
	var hv: Vector3 = (target.velocity if target is CharacterBody3D else Vector3.ZERO) * Vector3(1, 0, 1)
	_auto_turn(delta, v, tp, hv)
	# the top view keeps its original easing; mouse look answers almost at once
	var k := 1.0 - exp(-(7.0 if top or _glide > 0.0 else 40.0) * delta)
	var kv := 1.0 - exp(-7.0 * delta)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, distance, kv)
	_height = lerpf(_height, float(v.height) - RIDE_LOW * _ride, kv)
	_sprint = lerpf(_sprint, clampf((hv.length() - 3.7) / 1.7, 0.0, 1.0), 1.0 - exp(-3.0 * delta))
	cam.fov = lerpf(cam.fov, fov + fov_bonus + float(v.sprint_fov) * _sprint + RIDE_FOV * _ride, kv)
	# the point the camera orbits: the head, led a little into the direction of travel (third person leads
	# only sideways, so the player keeps their distance)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var lead := hv * float(v.lead)
	if mode == "third": lead = right * lead.dot(right)
	lead = lead.limit_length(3.0 if top else 1.2)
	_lead = _lead.lerp(lead, 1.0 - exp(-2.0 * delta))
	var head := tp + Vector3(0, _height, 0)
	var ll := _lead.length()
	if ll > 0.05:
		_lead *= _cast(head, _lead / ll, ll) / ll     # never lead into a wall
	var goal: Vector3 = _focus_point if _focus_point != null else head + _lead
	if eyes and target.has_method("walk_bob"): goal.y += target.walk_bob() * 0.045 - 0.02
	if _follow.distance_to(goal) > 25.0:      # a jump across the map: no swoop
		_follow = goal
		_follow_v = Vector3.ZERO
	var times: Vector2 = v.spring
	if _glide > 0.0: times = Vector2(maxf(times.x, 0.16), maxf(times.y, 0.22))
	_spring(goal, times, delta)
	# the eyes ride with the head once the glide into first person is over
	global_position = _follow.lerp(goal, smoothstep(0.0, 1.0, 1.0 - _glide / GLIDE)) if eyes else _follow
	rotation = Vector3(0, _yaw, 0)
	# first person leans a touch into a sidestep
	_roll = lerpf(_roll, -hv.dot(right) * 0.0035 if eyes else 0.0, 1.0 - exp(-6.0 * delta))
	var reach := _dist * (1.0 + float(v.sprint_dist) * _sprint)
	cam.position = Vector3(_side, 0, _clearance(reach, delta))
	_pivot.rotation = Vector3(_pitch + _lift, 0, _roll)
	if target.has_method("set_body_visible"): target.set_body_visible(cam.position.z > 0.7)
	if "face_yaw" in target: target.face_yaw = _yaw + PI if eyes else null
	_update_cursor()

## Hands-off follow (top and third person): sideways travel swings the camera round, walking on ahead
## brings it round behind the player, and in third person the pitch levels out to the slope ahead.
func _auto_turn(delta: float, v: Dictionary, tp: Vector3, hv: Vector3) -> void:
	var speed := hv.length()
	_moving = _moving + delta if speed > 0.8 else 0.0
	if hold_yaw != null:         # steps along a counter must not swing the view off it; a turn by hand still may
		if _manual > HANDS_OFF.y:
			yaw += angle_difference(yaw, hold_yaw) * (1.0 - exp(-2.5 * delta))
			pitch = lerpf(pitch, deg_to_rad(_hold_pitch), 1.0 - exp(-2.5 * delta))
		return
	if _focus_point != null or _drag or float(v.swing) <= 0.0 or speed < 0.3: return
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var trail := maxf(_clear * cos(_pitch + _lift), 1.5)   # how far behind the player the camera hangs
	yaw -= float(v.swing) * hv.dot(right) / trail * smoothstep(HANDS_OFF.x, HANDS_OFF.x + 0.5, _manual) * delta
	var off := angle_difference(yaw, atan2(-hv.x, -hv.z))
	var w := smoothstep(HANDS_OFF.y, HANDS_OFF.y + 0.8, _manual) * smoothstep(-0.2, 0.7, cos(off)) * smoothstep(0.3, 0.9, _moving)
	if w <= 0.0: return
	yaw += off * (1.0 - exp(-float(v.recentre) * clampf(speed / 4.2, 0.0, 1.5) * w * delta))
	if mode == "third" and floor_at.is_valid():
		var ahead := tp + hv / speed * 4.0
		var slope := atan2(float(floor_at.call(ahead.x, ahead.z)) - float(floor_at.call(tp.x, tp.z)), 4.0)
		pitch = lerpf(pitch, _clamp_pitch(deg_to_rad(TRAVEL_PITCH) + slope * 0.6), 1.0 - exp(-0.8 * w * delta))

## Critically damped spring of the orbit point towards `goal` (smooth times across and up).
func _spring(goal: Vector3, times: Vector2, delta: float) -> void:
	for i in 3:
		var t: float = times.y if i == 1 else times.x
		if t <= 0.0:
			_follow[i] = goal[i]
			_follow_v[i] = 0.0
			continue
		var w := 2.0 / t
		var x := w * delta
		var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var c: float = _follow[i] - goal[i]
		var tmp: float = (_follow_v[i] + w * c) * delta
		_follow_v[i] = (_follow_v[i] - w * tmp) * e
		_follow[i] = goal[i] + (c + tmp) * e

## Keep the camera out of walls, the ground and the river surface: third person pulls in, the top view
## first tilts down (up to its steepest pitch) to look over a building in the way. Pulls in at once, eases
## back out once clear.
func _clearance(d: float, delta: float) -> float:
	var top := mode == "top" and _focus_point == null
	if (mode != "third" and not top) or _focus_point != null or d < 0.3:
		_lift = lerpf(_lift, 0.0, 1.0 - exp(-4.0 * delta))
		_clear = d
		return d
	var from := global_position
	if top:
		_lift_in -= delta
		if _lift_in <= 0.0:
			_lift_in = LIFT_LOOK_EVERY
			_lift_to = 0.0
			var most := deg_to_rad(VIEWS.top.pitch.x) - _pitch
			while _lift_to > most and _cast(from, _back(_pitch + _lift_to), d) < d - 0.5:
				_lift_to = maxf(_lift_to - deg_to_rad(5.0), most)
		_lift = lerpf(_lift, _lift_to, 1.0 - exp(-(5.0 if _lift_to < _lift else 1.5) * delta))
	var back := _back(_pitch + _lift)
	var want := _cast(from, back, d)
	if floor_at.is_valid() and back.y < -0.01:
		# looking up swings the camera under the head: keep it above the grass, closer in
		var p := from + back * want
		var lowest: float = floor_at.call(p.x, p.z) + 0.35 + 0.75 * smoothstep(0.0, deg_to_rad(30.0), _pitch)
		if p.y < lowest: want = minf(want, (from.y - lowest) / -back.y)
	want = maxf(want, 0.0)
	_clear = want if want < _clear else lerpf(_clear, want, 1.0 - exp(-5.0 * delta))
	return _clear

func _back(p: float) -> Vector3:
	return (Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, p)) * Vector3.BACK

## How far back along `dir` the camera fits, sweeping a 0.2 m ball out from the pivot (up to d).
func _cast(from: Vector3, dir: Vector3, d: float) -> float:
	if _probe.exclude.is_empty() and target is CollisionObject3D: _probe.exclude = [target.get_rid()]
	_probe.transform = Transform3D(Basis.IDENTITY, from)
	_probe.motion = dir * (d + 0.3)
	var r := get_world_3d().direct_space_state.cast_motion(_probe)
	return d if r[0] >= 1.0 else clampf((d + 0.3) * r[0] - 0.3, 0.0, d)

func _update_cursor() -> void:
	var look := mode != "top" and _focus_point == null and not _free_cursor and not _cursor_held and cam.current and DisplayServer.window_is_focused()
	var m := Input.MOUSE_MODE_CAPTURED if look else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != m:
		Input.mouse_mode = m
		if look: _skip_motion = 2

## Something on screen wants the mouse for as long as this is on.
func hold_cursor(on: bool) -> void:
	_cursor_held = on

## Esc was for something on screen, not for freeing the mouse.
func take_cursor_back() -> void:
	_free_cursor = false

## Switch view, gliding there (or jumping, for start-up and captures).
func set_mode(m: String, instant := false) -> void:
	if not VIEWS.has(m) or m == mode: return
	_saved[mode] = [pitch, distance]
	mode = m
	if _focus_point == null:
		pitch = _saved[m][0]
		distance = _saved[m][1]
		fov = VIEWS[m].fov
	_free_cursor = false
	if instant:
		_yaw = yaw
		_pitch = pitch
		_dist = distance
		_clear = distance
		_lift = 0.0
		_lead = Vector3.ZERO
		_height = VIEWS[m].height
		cam.fov = fov
		if target:
			_follow = _target_pos() + Vector3(0, _height, 0)
			_follow_v = Vector3.ZERO
			global_position = _follow
	else:
		_glide = GLIDE
	mode_changed.emit(m)

func cycle_mode() -> void:
	if _focus_point != null: return     # inside a building the interior view stays
	var next: String = MODES[(MODES.find(mode) + 1) % MODES.size()]
	if indoors and next == "top": next = MODES[(MODES.find(next) + 1) % MODES.size()]
	set_mode(next)

## Stepping into or out of a room.
func set_indoors(on: bool) -> void:
	if on == indoors: return
	indoors = on
	if on and mode == "top":
		_top_outside = true
		set_mode("third")
	elif not on and _top_outside:
		_top_outside = false
		set_mode("top")

## Work at something with the view eased round to this heading; null lets the follow take over again.
func hold_view(y, steep := HOLD_PITCH, side := 0.0) -> void:
	hold_yaw = y
	_hold_pitch = steep
	_hold_side = side

## Glide in on an interior: closer, steeper, centred on the building, whatever the view.
func focus_on(point: Vector3, dist: float) -> void:
	if _focus_point == null: _saved[mode] = [pitch, distance]
	_focus_point = point
	distance = dist
	pitch = deg_to_rad(-58)
	fov = VIEWS.top.fov
	_glide = GLIDE

## Back to the view the player was in, as they left it.
func release() -> void:
	_focus_point = null
	pitch = _saved[mode][0]
	distance = _saved[mode][1]
	fov = VIEWS[mode].fov
	_glide = GLIDE
