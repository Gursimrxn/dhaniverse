class_name Gait
extends RefCounted
## How a body moves, on its own skeleton rather than through clips. Each foot is either on the ground, where it stays put in the world until it
## lifts, or stepping to where the body will be: so feet don't slide, steps land on the real floor, stopping brings the feet under him, and
## turning on the spot is a turn of the hips and then a step. The pelvis carries the weight (bob, sway, a lag behind the feet when he starts and
## stops), the spine leans into speed and turns, and the arms swing against the legs. All in the skeleton's units; rest-pose bones lie along +Y.

signal stepped(where: Vector3, heavy: float)   # a foot came down

const STRIDE_WALK := 1.5           # m, a full cycle of both feet, at a stroll: about three steps a second at his brisk walk
const STRIDE_FAST := 2.6           # m, at a run: four steps a second, both feet off the ground between them
const SPEED_FAST := 5.2            # m/s it's a full run
const STANCE_WALK := 0.6           # of a cycle a foot is down
const STANCE_RUN := 0.3
const LIFT_WALK := 0.085           # m a swinging foot clears the ground
const LIFT_RUN := 0.17
const STILL := 0.12                # m/s: slower than this he's standing
const SETTLE_STEP := 0.2           # s a shuffling step takes when he's stopped
const SETTLE_AT := 0.09            # m out of place before a standing foot bothers to move
const SETTLE_TURN := 0.75          # radians twisted before it steps round
const LEAN_SPEED := 0.035          # radians forward per m/s
const LEAN_ACCEL := 0.018          # radians per m/s² into a start, back on a stop
const LEAN_TURN := 0.028           # radians per m/s² across, into a corner
const BOB_WALK := 0.028            # in skeleton units
const BOB_RUN := 0.05
const SWAY := 0.032
const TWIST := 0.13                # radians of the hips each way
const ARM_WALK := 0.42             # radians either side
const ARM_RUN := 0.8
const ELBOW_WALK := 0.45           # radians it stays bent
const ELBOW_RUN := 1.25
const SPRING := 90.0               # the pelvis's lag behind the feet
const DAMP := 15.0
const SPRING_STEP := 1.0 / 120.0    # s: the spring is stepped no longer than this
const LAG_MOST := 0.12             # skeleton units: however hard the start or stop (or a hitch that looks like one)
const INERTIA := 0.012             # skeleton units of lag per m/s²
const HIP_DROP := 0.055            # how far the pelvis sits below straight legs
const BENT_WALK := 0.9             # moving, the hip's height over the ground as a share of the leg's length: knees bent, so a planted foot has room
const BENT_RUN := 0.84             # to pass under him
const STANCE_LEAST := 0.18         # of a cycle: however fast, a foot is down at least this long
const RE_AIM := 0.06               # m off where a flying foot should land before it's re-aimed
const TOE_OFF := 0.97              # of the leg's length from the hip: a foot left that far behind comes up
const STEP_MOST := 1.0 / 45.0      # s: the feet are stepped no longer than this at a time
const AIR_MOST := 0.4              # s a step is in the air at most: starting off slowly, the cycle is long, but a step isn't
const ROOM_USED := 0.85            # of the most a planted foot could pass under the hip: the rest is for bob, sway and lag

var body: Node3D                   # what's facing where he faces, and moves with him
var sk: Skeleton3D
var floor_ray := Callable()        # f(from, to) -> height of what's under there, or INF
var carrying_right := false        # something's posing the right arm: leave it

var sitting := 0.0                 # 0..1
var seat_forward := 0.34           # skeleton units his feet sit ahead of him, when sat
var seat_foot_y := 0.02            # and how high they are
var sit_lean := 0.0                # radians forward, when sat
var grips: Array = []              # where his hands hold on, left and right (skeleton space), when sat on something
var enabled := true                # off, the clip underneath has him (lying down)
var overreach := 0.0               # m: the most a planted foot has been asked to go past the leg's reach (held to it, it slides), for the checks
var overreach_air := 0.0           # m: the same for a foot in the air (held to it, its swing is a little shorter: unseen)
var breath := 0.0

var _i := {}                       # bone name -> index
var _pelvis := 0
var _feet: Array[Dictionary] = []
var _phase := 0.0
var _lag := Vector3.ZERO
var _lag_v := Vector3.ZERO
var _v := Vector3.ZERO
var _accel := Vector3.ZERO
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _lean := Vector2.ZERO
var _shift := 0.0                  # standing, which leg his weight is on
var _shift_to := 0.0
var _shift_in := 2.0
var _thigh := 0.0
var _shin := 0.0
var _leg := 0.0                    # hip to ankle, skeleton units
var _hip_y := 0.0                  # the hip over the ground, standing straight
var _hip_rest := Vector3.ZERO
var _scale := 1.0
var _ground_y := 0.0
var _sub_shift := Vector3.ZERO      # stepping a piece of a long frame: where the body was then, from where it is now
var _move := 0.0                   # 0 standing .. 1 moving, eased

func _init(on: Skeleton3D, facing: Node3D) -> void:
	sk = on
	body = facing
	for i in sk.get_bone_count(): _i[sk.get_bone_name(i)] = i
	_thigh = sk.get_bone_global_rest(_i["UpperLeg.L"]).origin.distance_to(sk.get_bone_global_rest(_i["LowerLeg.L"]).origin)
	_shin = sk.get_bone_global_rest(_i["LowerLeg.L"]).origin.distance_to(sk.get_bone_global_rest(_i["Foot.L"]).origin)
	_leg = _thigh + _shin
	_hip_y = sk.get_bone_global_rest(_i["UpperLeg.L"]).origin.y
	_pelvis = _i["Body_2"] if _i.has("Body_2") else _i["Body"]     # the same bone, under the name each export gave it
	_hip_rest = sk.get_bone_rest(_pelvis).origin
	for side in ["L", "R"]:
		_feet.append({"bone": _i["Foot." + side], "upper": _i["UpperLeg." + side], "lower": _i["LowerLeg." + side], "home": sk.get_bone_global_rest(_i["Foot." + side]).origin, "side": 1.0 if side == "L" else -1.0,
			"at": Vector3.INF, "yaw": 0.0, "from": Vector3.ZERO, "from_yaw": 0.0, "to": Vector3.ZERO, "t": -1.0, "len": 0.2, "lift": LIFT_WALK, "ahead_s": 0.0})

func _world_scale() -> float:
	return sk.global_basis.get_scale().y

## Everything in one go, once a frame, over whatever the animation left: the idle clip's pose is what's underneath.
func update(delta: float) -> void:
	if not enabled: return
	_scale = _world_scale()
	if _scale < 0.001 or not sk.global_transform.origin.is_finite(): return     # drawn at no size, or nowhere yet: nothing to pose
	var at := body.global_position
	if _last_pos == Vector3.INF:
		_last_pos = at
		_last_yaw = body.global_rotation.y
		_ground_y = at.y
	var teleported := at.distance_to(_last_pos) > 2.5
	var v := Vector3.ZERO if teleported else (at - _last_pos) / maxf(delta, 0.001)
	var was := at if teleported else _last_pos
	_last_pos = at
	v.y = 0.0
	var a := (v - _v) / maxf(delta, 0.001)
	_v = _v.lerp(v, 1.0 - exp(-18.0 * delta))
	_accel = _accel.lerp(a, 1.0 - exp(-7.0 * delta))
	var speed := _v.length()
	_move = move_toward(_move, 1.0 if speed > STILL else 0.0, delta * 5.0)
	var fast := clampf((speed - 1.5) / (SPEED_FAST - 1.5), 0.0, 1.0)
	if teleported:
		for f in _feet: f.at = Vector3.INF
	# a long frame (a slow machine) is stepped in short pieces: each foot comes up and down when it should, not at the frame
	var pieces := maxi(ceili(delta / STEP_MOST), 1)
	for j in pieces:
		var sub := was.lerp(at, float(j + 1) / pieces)
		_sub_shift = sub - at
		_step_feet(delta / pieces, speed, fast, sub)
	_sub_shift = Vector3.ZERO
	_pose_pelvis(delta, speed, fast)
	_pose_spine(fast)
	_pose_arms(fast)
	for f in _feet: _pose_leg(f)

func _facing_yaw() -> float:
	return body.global_rotation.y

## Where this foot would be standing if the body were here, on the ground.
func _home(f: Dictionary, at: Vector3, ahead := Vector3.ZERO) -> Vector3:
	var h: Vector3 = f.home
	var w := at + Basis(Vector3.UP, _facing_yaw()) * Vector3(h.x * _scale, 0.0, 0.0) + ahead
	var y: float = floor_ray.call(w + Vector3.UP * 0.7, w + Vector3.DOWN * 0.9) if floor_ray.is_valid() else INF
	w.y = y if y != INF else at.y
	return w

func _step_feet(delta: float, speed: float, fast: float, at: Vector3) -> void:
	for f in _feet:
		if f.at == Vector3.INF:
			f.at = _home(f, at)
			f.yaw = _facing_yaw()
			f.t = -1.0
	var stride := lerpf(STRIDE_WALK, STRIDE_FAST, fast) * lerpf(0.65, 1.0, clampf(speed / 1.5, 0.0, 1.0))
	var stance := lerpf(STANCE_WALK, STANCE_RUN, fast)
	# a planted foot goes from in front of the hip to behind it while the body passes over: no further than the leg reaches.
	# Short legs at speed: the foot's down for less of the cycle, and then the steps come quicker.
	var h := lerpf(BENT_WALK, BENT_RUN, fast)
	var room := 2.0 * _leg * sqrt(1.0 - h * h) * _scale * ROOM_USED
	if room > 0.01 and stance * stride > room:
		stance = maxf(room / stride, STANCE_LEAST)
		stride = minf(stride, room / stance)
	if speed > STILL:
		var adv := speed * delta / stride
		_phase = fmod(_phase + adv, 1.0)
		var cycle := stride / maxf(speed, 0.1)
		for i in 2:
			var f: Dictionary = _feet[i]
			var p1 := fmod(_phase + i * 0.5, 1.0)
			# its stance ends before the next frame: up it comes now rather than a frame late (at a few frames a second, a frame
			# is a long way at a run), and a step whose end fell between two frames, past the cycle's wrap, isn't missed
			# and one still down in the first half of its swing (it landed late) goes up at once
			var past := p1 - stance
			# and one the hip has left as far behind as the leg reaches comes up there, toe-off, whatever the cycle says
			if f.t < 0.0 and (fposmod(stance - p1, 1.0) < minf(adv, 0.5) or (past >= 0.0 and past < (1.0 - stance) * 0.5) or _at_full_stretch(f)):
				var air := (1.0 - stance) * cycle
				air = minf(air, AIR_MOST)
				_lift(f, at + _v * air, _v * (stance * cycle * 0.5), air, lerpf(LIFT_WALK, LIFT_RUN, fast))
				f.ahead_s = stance * cycle * 0.5
	else:
		_settle(delta, at)
	for f in _feet:
		if f.t < 0.0: continue
		# where he'll be when it comes down changes as he speeds up, slows or turns: it comes down there, not where he was headed
		if speed > STILL and f.ahead_s > 0.0:
			var left: float = (1.0 - f.t) * float(f.len)
			var land := at + _v * left
			var aim := land + _v * float(f.ahead_s)
			if Vector2(aim.x - (f.to as Vector3).x, aim.z - (f.to as Vector3).z).length() > RE_AIM:
				f.to = _home(f, land, _v * float(f.ahead_s))
		f.t += delta / float(f.len)
		if f.t >= 1.0:
			f.t = -1.0
			f.at = f.to
			f.yaw = _facing_yaw()
			stepped.emit(f.at, clampf(speed / SPEED_FAST, 0.0, 1.0))
		else:
			var k: float = smoothstep(0.0, 1.0, f.t)
			f.at = (f.from as Vector3).lerp(f.to, k) + Vector3.UP * (float(f.lift) * sin(PI * f.t))
			f.yaw = lerp_angle(f.from_yaw, _facing_yaw(), k)
	# a foot can never be further than the leg reaches: on a stumble or a slide it gives up and catches up
	var reach := (_thigh + _shin) * _scale * 1.25
	for f in _feet:
		if f.t < 0.0 and (f.at as Vector3).distance_to(at) > reach * 1.6: _lift(f, at, Vector3.ZERO, 0.12, LIFT_WALK)

## A planted foot left behind the hip as far as the leg goes, or nearly (in front, it has only just landed).
func _at_full_stretch(f: Dictionary) -> bool:
	var hip := sk.global_transform * sk.get_bone_global_pose(f.upper).origin + _sub_shift
	var from_hip := (f.at as Vector3) - hip
	return from_hip.dot(_v) < 0.0 and from_hip.length() > _leg * _scale * TOE_OFF

func _lift(f: Dictionary, body_then: Vector3, ahead: Vector3, seconds: float, height: float) -> void:
	f.ahead_s = 0.0
	f.from = f.at
	f.from_yaw = f.yaw
	f.to = _home(f, body_then, ahead)
	f.t = 0.0
	f.len = maxf(seconds, 0.05)
	f.lift = height

## Standing: a foot left behind or twisted too far steps back under him, one at a time.
func _settle(delta: float, at: Vector3) -> void:
	_shift_in -= delta
	if _shift_in <= 0.0:
		_shift_in = randf_range(3.5, 8.0)
		_shift_to = randf_range(-1.0, 1.0)
	_shift = lerpf(_shift, _shift_to, 1.0 - exp(-1.6 * delta))
	if _feet[0].t >= 0.0 or _feet[1].t >= 0.0: return
	var worst: Dictionary = {}
	var most := 0.0
	for f in _feet:
		var off: float = Vector2((f.at as Vector3).x - _home(f, at).x, (f.at as Vector3).z - _home(f, at).z).length()
		var turned: float = absf(angle_difference(f.yaw, _facing_yaw()))
		var need: float = maxf(off / SETTLE_AT, turned / SETTLE_TURN)
		if need > most and need >= 1.0:
			most = need
			worst = f
	if not worst.is_empty(): _lift(worst, at, Vector3.ZERO, SETTLE_STEP, LIFT_WALK * 0.7)

func _pose_pelvis(delta: float, speed: float, fast: float) -> void:
	var yaw := Basis(Vector3.UP, -_facing_yaw())
	var a_local := yaw * _accel
	# the pelvis lags behind what the feet are doing, and swings back
	var pull := (Vector3(-a_local.x, 0.0, -a_local.z) * INERTIA).limit_length(LAG_MOST)
	# in short steps: one long frame (a slow machine, a hitch) would throw a stiff spring off rather than settle it
	var left := delta
	while left > 0.0:
		var h := minf(left, SPRING_STEP)
		_lag_v += (pull - _lag) * SPRING * h - _lag_v * DAMP * h
		_lag += _lag_v * h
		left -= h
	var bob := lerpf(BOB_WALK, BOB_RUN, fast) * _move
	var c := _phase * TAU
	var bent := maxf(lerpf(HIP_DROP, HIP_DROP * 1.9, fast), _hip_y - _leg * lerpf(BENT_WALK, BENT_RUN, fast))
	var drop := bent * _move + HIP_DROP * 0.5 * (1.0 - _move)
	var p := _hip_rest + Vector3(sin(c) * SWAY * _move * (1.0 - fast * 0.5), -drop - cos(c * 2.0) * bob * 0.5, 0.0) + _lag
	p.x += _shift * 0.03 * (1.0 - _move)
	# sitting takes him down onto what's under him
	p.y -= sitting * (_hip_rest.y - 0.42)
	# on uneven ground, down to the lower foot
	var feet_low: float = minf((_feet[0].at as Vector3).y, (_feet[1].at as Vector3).y)
	var want := clampf((feet_low - body.global_position.y) / maxf(_scale, 0.01), -0.3, 0.05)
	_ground_y = lerpf(_ground_y, want, 1.0 - exp(-12.0 * delta))
	p.y += _ground_y
	var pelvis: int = _pelvis
	sk.set_bone_pose_position(pelvis, p)
	_lean = _lean.lerp(Vector2(a_local.x * LEAN_TURN, (speed * LEAN_SPEED + a_local.z * LEAN_ACCEL) * _move).limit_length(0.5), 1.0 - exp(-8.0 * delta))
	var q := Quaternion(Vector3.RIGHT, _lean.y * 0.35 + sit_lean * sitting) * Quaternion(Vector3.FORWARD, _lean.x * 0.5) * Quaternion(Vector3.UP, -cos(c) * TWIST * _move)
	sk.set_bone_pose_rotation(pelvis, q * sk.get_bone_rest(pelvis).basis.get_rotation_quaternion())

func _pose_spine(fast: float) -> void:
	var c := _phase * TAU
	var counter := cos(c) * TWIST * 1.4 * _move
	breath += 0.016
	var breathe := sin(breath * 1.5) * 0.012 * (1.0 - _move * 0.6) + sin(c * 2.0) * 0.012 * _move * (1.0 + fast)
	var abdomen: int = _i["Abdomen"]
	sk.set_bone_pose_rotation(abdomen, Quaternion(Vector3.RIGHT, _lean.y * 0.35 + breathe) * Quaternion(Vector3.UP, counter * 0.5) * sk.get_bone_pose_rotation(abdomen))
	var torso: int = _i["Torso"]
	sk.set_bone_pose_rotation(torso, Quaternion(Vector3.RIGHT, _lean.y * 0.35 + breathe) * Quaternion(Vector3.FORWARD, _lean.x * 0.5) * Quaternion(Vector3.UP, counter * 0.5) * sk.get_bone_pose_rotation(torso))

## The arms hang from the shoulders and swing against the legs, bent more the faster he goes.
func _pose_arms(fast: float) -> void:
	var c := _phase * TAU
	var swing := lerpf(ARM_WALK, ARM_RUN, fast) * _move
	var bend := lerpf(0.12, lerpf(ELBOW_WALK, ELBOW_RUN, fast), _move)
	if sitting > 0.5 and grips.size() == 2:
		_arm_to("L", grips[0], 1.0)
		if not carrying_right: _arm_to("R", grips[1], -1.0)
		return
	for side in [["L", 1.0], ["R", -1.0]]:
		if side[0] == "R" and carrying_right: continue
		var s: float = side[1]
		var ang := -cos(c) * s * swing         # against the same side's leg: back as that foot lands
		var upper: int = _i["UpperArm." + side[0]]
		var lower: int = _i["LowerArm." + side[0]]
		# straight down and a touch out, swung about the shoulder's own side axis
		var down := Basis(Vector3.RIGHT, -ang) * Vector3(s * 0.2, -0.97, 0.02)
		_aim(upper, (sk.global_basis.inverse().orthonormalized() * body.global_basis.orthonormalized() * down).normalized())
		var fore := Basis(Vector3.RIGHT, -ang - bend) * Vector3(s * 0.12, -0.97, 0.05)
		_aim(lower, (sk.global_basis.inverse().orthonormalized() * body.global_basis.orthonormalized() * fore).normalized())

## Shoulder to hand, in two bones, the elbow out and down.
func _arm_to(side: String, target: Vector3, s: float) -> void:
	var upper: int = _i["UpperArm." + side]
	var lower: int = _i["LowerArm." + side]
	var fist: int = _i["Fist." + side]
	var a := sk.get_bone_global_rest(upper).origin.distance_to(sk.get_bone_global_rest(lower).origin)
	var b := sk.get_bone_global_rest(lower).origin.distance_to(sk.get_bone_global_rest(fist).origin)
	var from := sk.get_bone_global_pose(upper).origin
	var to := target - from
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var dir := to.normalized()
	var along := (d * d + a * a - b * b) / (2.0 * d)
	var h := sqrt(maxf(a * a - along * along, 0.0))
	var pole := Vector3(s * 0.7, -0.7, -0.2).normalized()
	var side_axis := dir.cross(pole).normalized()
	var out := side_axis.cross(dir).normalized()
	var elbow := from + dir * along + out * h
	_aim(upper, (elbow - from).normalized())
	_aim(lower, (from + dir * d - elbow).normalized())

## Hip to foot, in two bones, the knee out in front of him.
func _pose_leg(f: Dictionary) -> void:
	var to_sk := sk.global_transform.affine_inverse()
	var foot: Vector3 = to_sk * (f.at as Vector3)
	var flat_yaw: float = angle_difference(_facing_yaw(), f.yaw)
	var roll := 0.0
	if f.t >= 0.0:     # heel to toe: toes down as it leaves, up as it comes in
		roll = lerpf(0.75, -0.35, f.t) * sin(PI * clampf(f.t * 1.2, 0.0, 1.0))
	if sitting > 0.0:
		foot = foot.lerp(Vector3(f.home.x, seat_foot_y, seat_forward), sitting)
	var hip := sk.get_bone_global_pose(f.upper).origin
	if not foot.is_finite() or foot.distance_to(hip) < 0.001: foot = hip + Vector3.DOWN * (_thigh + _shin) * 0.9
	var reach := _thigh + _shin - 0.001
	var short := (foot - hip).length() - reach
	if short > 0.0:
		if f.t < 0.0: overreach = maxf(overreach, short * _scale)
		else: overreach_air = maxf(overreach_air, short * _scale)
		foot = hip + (foot - hip).limit_length(reach)
	sk.set_bone_pose_position(f.bone, foot)
	var rest_q: Quaternion = sk.get_bone_rest(f.bone).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(f.bone, Quaternion(Vector3.UP, flat_yaw) * Quaternion(Vector3.RIGHT, roll) * rest_q)
	var to := foot - hip
	var d := clampf(to.length(), absf(_thigh - _shin) + 0.01, _thigh + _shin - 0.001)
	var dir := to.normalized()
	var along := (d * d + _thigh * _thigh - _shin * _shin) / (2.0 * d)
	var h := sqrt(maxf(_thigh * _thigh - along * along, 0.0))
	# the knee bends the way the foot points, whichever way the body's turned
	var pole := Basis(Vector3.UP, flat_yaw * 0.5) * Vector3.BACK
	var side := dir.cross(pole).normalized()
	var fwd := side.cross(dir).normalized()
	var knee := hip + dir * along + fwd * h
	_aim(f.upper, (knee - hip).normalized())
	_aim(f.lower, (hip + dir * d - knee).normalized())

## Turn a bone so it points along a direction in the skeleton's frame.
func _aim(bone: int, dir: Vector3) -> void:
	if dir.is_zero_approx() or not dir.is_finite(): return
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(bone)).basis.orthonormalized()
	var g := parent * Basis(sk.get_bone_pose_rotation(bone))
	if g.y.is_zero_approx(): return
	var aimed := Basis(Quaternion(g.y.normalized(), dir)) * g
	sk.set_bone_pose_rotation(bone, (parent.inverse() * aimed).get_rotation_quaternion())
