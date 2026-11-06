extends Node3D
## Arus, the protagonist (P001), in his default costume as the archive describes it: a felt hat, a long wool robe
## over a tan inner layer, dark teal wool trousers, a leather belt with a metal buckle, leather boots with cloth
## tops, and short hair (materials MI_P001_001_Hat / Robe / Inner / Pants / Belt / Buckle / Boots / BootsCloth /
## Hair / Skin / Face / Eye). Colours are the archive's accent colours where it gives them (hat, robe, inner,
## trousers, boots); skin, hair and buckle colours are not in the archive, so they are chosen to fit.
## The body is built from smooth lathed and elliptical meshes on a jointed skeleton of Node3Ds, and shaded with
## shaders/vh/character.gdshader.
##
## Behaviour follows the character systems documented in the reference archive (code-inventory 08):
##   - blinks at random every 3 to 8 s (DT_CharaHeadAnimData BlinkData: MinBlinkDelayTime 3, Max 8);
##   - the head and eyes look at what the player looks at, clamped to yaw 35 / pitch 20 degrees and eased at an
##     interpolation speed of 0.3 per 60 Hz frame (Coord_Field_Default, DT_EyeLookAtParameter);
##   - the fringe swings as verlet chains with stiffness 0.3, damping 0.5 and real gravity, stepped at
##     60 Hz (the KawaiiPhysics settings most of the archive's characters use).
## The walk advances by the distance actually travelled, so the feet keep pace with the ground.

const SKIN := Color("a0704e")       # not in the archive: a warm medium brown
const HAT := Color("4a6e4f")        # MI_P001_001_Hat fuzz colour (archive)
const ROBE := Color("3d5a32")       # MI_P001_001_Robe fuzz colour, olive wool (archive)
const INNER := Color("98826a")      # MI_P001_001_Inner decal colour, tan (archive)
const PANTS := Color("2e4a4a")      # MI_P001_001_Pants fuzz colour, dark teal wool (archive)
const LEATHER := Color("4a2e1c")    # MI_P001_001_Boots decal colour, dark brown leather (archive)
const BRASS := Color("a08c5c")      # MI_P001_001_Buckle: metal, not in the archive
const HAIR := Color("2a1d14")       # MI_P001_001_Hair: not in the archive
const LIP := Color("8a4f40")
const IRIS := Color("4a2e1e")

const SIZE := 0.8                   # the whole figure, against the player's 1.6 m collision capsule
const STRIDE := 0.78 * SIZE         # metres per step, at this size
const BLINK_MIN := 3.0
const BLINK_MAX := 8.0
const BLINK_TIME := 0.16
const LOOK_YAW := deg_to_rad(35.0)
const LOOK_PITCH := deg_to_rad(20.0)
const LOOK_INTERP := 0.3            # per 60 Hz frame
const STIFFNESS := 0.3
const DAMPING := 0.5
const GRAVITY := Vector3(0.0, -9.8, 0.0)

static var _shader: Shader
var parts: Array[MeshInstance3D] = []
var _mats := {}

# skeleton
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var thighs: Array[Node3D] = []
var knees: Array[Node3D] = []
var ankles: Array[Node3D] = []
var lids: Array[MeshInstance3D] = []
var irises: Array[Node3D] = []

# motion state
var _phase := 0.0
var _move := 0.0                    # 0 standing .. 1 walking .. 1.5 running
var _t := 0.0
var _blink_in := 2.0
var _blink_t := -1.0
var _look := Vector2.ZERO           # current head yaw / pitch
var look_target := Vector2.ZERO     # wanted head yaw / pitch (set by the player)
var _chains: Array = []             # [pivot Node3D, length, rest dir (local), tip pos, prev tip pos]
var _rng := RandomNumberGenerator.new()
var wave_amount := 0.0              # extra raise of the right arm (wave), tweened

func _ready() -> void:
	scale = Vector3.ONE * SIZE
	_rng.randomize()
	_blink_in = _rng.randf_range(BLINK_MIN, BLINK_MAX)
	_build()

# --- materials and meshes -----------------------------------------------------------------------------------------
func _mat(c: Color, kind: int, detail := 1.0) -> ShaderMaterial:
	var key := "%s|%d|%s" % [c.to_html(), kind, detail]
	if _mats.has(key): return _mats[key]
	if _shader == null: _shader = load("res://shaders/vh/character.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("detail", detail)
	_mats[key] = m
	return m

## A surface of revolution about +Y from a profile of (y, radius) points, with an elliptical cross-section
## (sx across, sz front to back) and exact normals (the inverse-transpose of the ellipse), capped at both ends.
static func lathe(profile: PackedVector2Array, seg := 24, sx := 1.0, sz := 1.0, a0 := 0.0, a1 := TAU) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := profile.size()
	for i in n:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, n - 1)]
		var t := Vector2(b.y - a.y, b.x - a.x)          # d(radius), d(y) along the profile
		var pn := Vector2(t.y, -t.x).normalized()        # outward in the (radius, y) plane
		if pn.x < 0.0: pn = -pn
		for j in seg + 1:
			var ang := lerpf(a0, a1, float(j) / seg)
			var c := cos(ang)
			var s := sin(ang)
			var r: float = profile[i].y
			pos.append(Vector3(c * r * sx, profile[i].x, s * r * sz))
			nrm.append(Vector3(pn.x * c / sx, pn.y, pn.x * s / sz).normalized())
			uv.append(Vector2(float(j) / seg, float(i) / (n - 1)))
	for i in n - 1:
		for j in seg:
			var a := i * (seg + 1) + j
			var b := a + seg + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func ellipsoid(r: Vector3, seg := 24, rings := 14) -> ArrayMesh:
	var prof := PackedVector2Array()
	for i in rings + 1:
		var a := PI * float(i) / rings - PI * 0.5
		prof.append(Vector2(sin(a) * r.y, cos(a) * r.x))
	return lathe(prof, seg, 1.0, r.z / r.x)

## A tapered limb from 0 down to -len: radius r0 at the top to r1 at the bottom, rounded ends.
static func limb(length: float, r0: float, r1: float, sx := 1.0, sz := 1.0) -> ArrayMesh:
	var prof := PackedVector2Array()
	for i in 6:
		var a := PI * 0.5 * float(i) / 5.0
		prof.append(Vector2(-length - sin(PI * 0.5 - a) * r1 * 0.6 + r1 * 0.6, cos(PI * 0.5 - a) * r1))
	for i in range(1, 10):
		var t := float(i) / 10.0
		prof.append(Vector2(-length * (1.0 - t), lerpf(r1, r0, smoothstep(0.0, 1.0, t))))
	for i in 6:
		var a := PI * 0.5 * float(i) / 5.0
		prof.append(Vector2(sin(a) * r0 * 0.6, cos(a) * r0))
	var fixed := PackedVector2Array()
	for i in prof.size():
		fixed.append(prof[i])
	return lathe(fixed, 20, sx, sz)

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	parts.append(mi)
	return mi

func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j

# --- the body ---------------------------------------------------------------------------------------------------------
func _build() -> void:
	var skin := _mat(SKIN, 0)
	var robe := _mat(ROBE, 10)
	var inner := _mat(INNER, 1)
	var pants := _mat(PANTS, 10)
	var leather := _mat(LEATHER, 3)
	var brass := _mat(BRASS, 9)
	var cloth_top := _mat(PANTS, 10, 1.6)
	hips = _joint(self, Vector3(0, 0.95, 0))
	# trousers: the hips and waist sit under the robe's hem
	_part(hips, lathe(PackedVector2Array([Vector2(-0.12, 0.0), Vector2(-0.11, 0.1), Vector2(-0.06, 0.15), Vector2(0.0, 0.156), Vector2(0.06, 0.15), Vector2(0.075, 0.0)]), 28, 1.0, 0.64), pants)
	spine = _joint(hips, Vector3(0, 0.08, 0))
	chest = _joint(spine, Vector3(0, 0.22, 0))
	# the robe: long, wool, from the shoulders to the upper thigh, flatter front to back
	_part(spine, lathe(PackedVector2Array([
		Vector2(-0.2, 0.205), Vector2(-0.1, 0.195), Vector2(0.0, 0.178), Vector2(0.1, 0.172), Vector2(0.2, 0.188),
		Vector2(0.28, 0.2), Vector2(0.33, 0.19), Vector2(0.355, 0.13), Vector2(0.37, 0.078)]), 40, 1.0, 0.66), robe)
	# belt of leather round the waist, with a brass buckle at the front
	_part(spine, lathe(PackedVector2Array([Vector2(-0.012, 0.176), Vector2(0.018, 0.182)]), 40, 1.0, 0.7), leather)
	_part(spine, ellipsoid(Vector3(0.018, 0.017, 0.006), 14, 8), brass, Vector3(0.0, 0.003, 0.178))
	# inner layer showing at the open collar
	_part(chest, ellipsoid(Vector3(0.05, 0.055, 0.02), 18, 10), inner, Vector3(0, 0.1, 0.085))
	# neck and head
	neck = _joint(chest, Vector3(0, 0.15, 0))
	_part(neck, limb(0.09, 0.05, 0.057, 1.0, 1.05), skin, Vector3(0, 0.075, 0))
	head = _joint(neck, Vector3(0, 0.068, 0.012))
	_build_head(skin, _mat(HAIR, 4))
	# arms: long robe sleeves to the wrist, a tan inner cuff, bare hands
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var sh := _joint(chest, Vector3(0.178 * sx, 0.11, 0))
		_part(sh, ellipsoid(Vector3(0.052, 0.05, 0.05), 18, 10), robe, Vector3(-0.01 * sx, 0.0, 0))
		_part(sh, limb(0.27, 0.052, 0.045, 1.0, 0.95), robe, Vector3(0, -0.005, 0))
		var el := _joint(sh, Vector3(0, -0.28, 0))
		_part(el, limb(0.24, 0.042, 0.032, 1.0, 0.9), robe)
		_part(el, lathe(PackedVector2Array([Vector2(-0.218, 0.0), Vector2(-0.218, 0.03), Vector2(-0.2, 0.034), Vector2(-0.2, 0.0)]), 20, 1.0, 0.85), inner)
		if i == 0: _part(el, lathe(PackedVector2Array([Vector2(-0.12, 0.0), Vector2(-0.12, 0.03), Vector2(-0.104, 0.03), Vector2(-0.104, 0.0)]), 16, 1.0, 0.9), brass)
		var hand := _joint(el, Vector3(0, -0.255, 0))
		_part(hand, ellipsoid(Vector3(0.036, 0.05, 0.016), 16, 10), skin, Vector3(0, -0.035, 0.002))
		_part(hand, ellipsoid(Vector3(0.032, 0.035, 0.014), 14, 8), skin, Vector3(0, -0.085, 0.006), Vector3(0.25, 0, 0))
		_part(hand, limb(0.045, 0.011, 0.009), skin, Vector3(0.03 * sx, -0.02, 0.018), Vector3(0.3, 0, 0.5 * sx))
		shoulders.append(sh)
		elbows.append(el)
	# legs: trousers, leather boots with cloth tops
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var th := _joint(hips, Vector3(0.09 * sx, -0.04, 0))
		_part(th, limb(0.44, 0.082, 0.058, 1.0, 1.0), pants)
		var kn := _joint(th, Vector3(0, -0.44, 0))
		_part(kn, limb(0.4, 0.06, 0.05, 1.0, 1.0), pants, Vector3(0, 0.025, 0))
		# turned-up hem
		_part(kn, lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.052), Vector2(0.035, 0.053), Vector2(0.035, 0.0)]), 20), pants, Vector3(0, -0.385, 0))
		var an := _joint(kn, Vector3(0, -0.395, 0))
		# cloth top of the boot, a band round the ankle
		_part(an, lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.07), Vector2(0.01, 0.075), Vector2(0.02, 0.0)]), 20, 1.0, 1.0), cloth_top, Vector3(0, 0.0, 0), Vector3(1, 1, 1))
		_part(an, ellipsoid(Vector3(0.052, 0.05, 0.135), 20, 12), leather, Vector3(0, -0.03, 0.045))
		_part(an, ellipsoid(Vector3(0.054, 0.024, 0.14), 20, 8), _mat(Color("2a1a10"), 3), Vector3(0, -0.058, 0.045))
		thighs.append(th)
		knees.append(kn)
		ankles.append(an)

func _build_head(skin: Material, hair: Material) -> void:
	# skull and face: an egg from the chin up to the crown, narrower than it is deep
	_part(head, lathe(PackedVector2Array([
		Vector2(-0.004, 0.0), Vector2(0.004, 0.034), Vector2(0.02, 0.058), Vector2(0.045, 0.074), Vector2(0.075, 0.085), Vector2(0.1, 0.09),
		Vector2(0.135, 0.092), Vector2(0.17, 0.085), Vector2(0.2, 0.066), Vector2(0.22, 0.038), Vector2(0.228, 0.0)]), 32, 0.86, 1.05), skin)
	# ears
	for sx in [-1.0, 1.0]:
		_part(head, ellipsoid(Vector3(0.012, 0.028, 0.02), 12, 8), skin, Vector3(0.077 * sx, 0.1, -0.005))
	# the felt hat: a crown and a brim, worn over the hair
	var hat := _mat(HAT, 10, 1.2)
	_part(head, lathe(PackedVector2Array([Vector2(0.19, 0.0), Vector2(0.19, 0.11), Vector2(0.22, 0.115), Vector2(0.265, 0.11), Vector2(0.29, 0.085), Vector2(0.292, 0.0)]), 32, 1.0, 1.0), hat)
	_part(head, lathe(PackedVector2Array([Vector2(0.186, 0.0), Vector2(0.184, 0.2), Vector2(0.19, 0.24), Vector2(0.196, 0.25), Vector2(0.2, 0.22), Vector2(0.2, 0.0)]), 36, 1.0, 1.0), hat)
	# nose, lips
	_part(head, ellipsoid(Vector3(0.009, 0.019, 0.011), 14, 10), skin, Vector3(0, 0.083, 0.09), Vector3(0.3, 0, 0))
	_part(head, ellipsoid(Vector3(0.022, 0.005, 0.01), 14, 8), _mat(LIP, 0), Vector3(0, 0.047, 0.083))
	# eyes: whites, irises with catchlights, lids that close on a blink, brows
	for sx in [-1.0, 1.0]:
		var eye := _joint(head, Vector3(0.031 * sx, 0.112, 0.087))
		_part(eye, ellipsoid(Vector3(0.0125, 0.0105, 0.009), 16, 10), _mat(Color("f2eee8"), 6))
		var ir := _joint(eye, Vector3(0, 0, 0.008))
		_part(ir, ellipsoid(Vector3(0.0085, 0.0085, 0.0022), 16, 8), _mat(IRIS, 7))
		irises.append(ir)
		var lid := _part(eye, ellipsoid(Vector3(0.0145, 0.0125, 0.0115), 16, 10), skin, Vector3(0, 0.002, -0.001))
		lid.scale = Vector3(1, 0.05, 1)
		lid.position.y = 0.011
		lids.append(lid)
		_part(head, ellipsoid(Vector3(0.019, 0.004, 0.006), 12, 6), hair, Vector3(0.033 * sx, 0.134, 0.09), Vector3(0, 0, -0.12 * sx))
	# hair: a close cap over the skull, fuller at the top and back, and sideburns
	_part(head, lathe(PackedVector2Array([
		Vector2(0.15, 0.0), Vector2(0.152, 0.07), Vector2(0.17, 0.093), Vector2(0.195, 0.088),
		Vector2(0.218, 0.066), Vector2(0.235, 0.036), Vector2(0.241, 0.0)]), 32, 0.9, 1.07), hair, Vector3(0, 0, -0.004))
	_part(head, ellipsoid(Vector3(0.083, 0.085, 0.07), 24, 14), hair, Vector3(0, 0.12, -0.03))
	for sx in [-1.0, 1.0]:
		_part(head, ellipsoid(Vector3(0.01, 0.03, 0.022), 12, 8), hair, Vector3(0.077 * sx, 0.135, 0.015))
	# loose locks at the fringe, swinging on their springs
	for k in 5:
		var x := (float(k) - 2.0) * 0.022
		var pivot := _joint(head, Vector3(x, 0.2, 0.072 - absf(x) * 0.3))
		_part(pivot, limb(0.045, 0.016, 0.004, 1.3, 0.55), hair, Vector3.ZERO, Vector3(-1.9, 0, x * 3.0))
		_add_chain(pivot, 0.045, Vector3(0, 0.3, 0.95).normalized())

## A swinging part: its pivot points along `rest` (pivot-local) at rest and is pulled by its tip's inertia.
func _add_chain(pivot: Node3D, length: float, rest: Vector3) -> void:
	_chains.append([pivot, length, rest, Vector3.ZERO, Vector3.ZERO, pivot.transform.basis, false])

# --- motion -----------------------------------------------------------------------------------------------------------
## speed: ground speed (m/s); dt: the physics step. Called by the player every physics frame.
func step(speed: float, dt: float) -> void:
	_t += dt
	_move = lerpf(_move, clampf(speed / 4.2, 0.0, 1.6), 1.0 - exp(-8.0 * dt))
	_phase += speed * dt / STRIDE * PI
	var w := clampf(_move, 0.0, 1.0)
	var run := clampf(_move - 1.0, 0.0, 0.6) / 0.6
	var s := sin(_phase)
	# legs: hip swing, knee flex in the swing phase, the foot kept near level
	for i in 2:
		var ph := _phase + (PI if i == 1 else 0.0)
		var sw := sin(ph)
		var amp := lerpf(0.42, 0.62, run) * w
		thighs[i].rotation.x = -sw * amp
		var knee := maxf(0.0, sin(ph - 1.25)) * lerpf(0.75, 1.25, run) * w + 0.04
		knees[i].rotation.x = knee
		ankles[i].rotation.x = -thighs[i].rotation.x - knee + clampf(-cos(ph) * 0.25 * w, -0.1, 0.3)
	# arms: counter-swing, elbows bent more as the pace picks up; hands relaxed at rest
	for i in 2:
		var ph := _phase + (0.0 if i == 1 else PI)
		var side := -1.0 if i == 0 else 1.0
		shoulders[i].rotation.x = -sin(ph) * lerpf(0.32, 0.55, run) * w
		shoulders[i].rotation.z = side * (0.09 + 0.03 * w) + (wave_amount if i == 1 else 0.0)
		elbows[i].rotation.x = -(0.18 + w * 0.25 + run * 0.6) + minf(0.0, sin(ph)) * 0.15 * w
	# pelvis and torso: the bob of each step, the hips' turn against the shoulders', a lean into a run
	var breathe := sin(_t * 1.6)
	hips.position.y = 0.95 + absf(s) * 0.035 * w - 0.012 * w + breathe * 0.002 * (1.0 - w)
	hips.rotation.y = s * 0.09 * w
	hips.rotation.z = -cos(_phase) * 0.03 * w + sin(_t * 0.35) * 0.012 * (1.0 - w)
	spine.rotation.y = -s * 0.07 * w
	spine.rotation.x = 0.04 * w + 0.12 * run
	chest.scale = Vector3(1.0, 1.0 + breathe * 0.006, 1.0 + breathe * 0.012)
	_update_head(dt)
	_update_blink(dt)
	_update_chains(dt)

func _update_head(dt: float) -> void:
	var k := 1.0 - pow(1.0 - LOOK_INTERP, dt * 60.0)
	var want := Vector2(clampf(look_target.x, -LOOK_YAW, LOOK_YAW), clampf(look_target.y, -LOOK_PITCH, LOOK_PITCH))
	_look = _look.lerp(want, k)
	# the neck takes a third, the head the rest; the eyes lead a little
	neck.rotation = Vector3(_look.y * 0.3, _look.x * 0.3, 0.0)
	head.rotation = Vector3(_look.y * 0.7, _look.x * 0.7, 0.0)
	for ir in irises:
		ir.position.x = clampf((want.x - _look.x) * 0.02, -0.003, 0.003)
		ir.position.y = clampf((want.y - _look.y) * 0.02, -0.002, 0.002)

func _update_blink(dt: float) -> void:
	if _blink_t < 0.0:
		_blink_in -= dt
		if _blink_in <= 0.0:
			_blink_t = 0.0
			_blink_in = _rng.randf_range(BLINK_MIN, BLINK_MAX)
	var closed := 0.0
	if _blink_t >= 0.0:
		_blink_t += dt
		var u := _blink_t / BLINK_TIME
		closed = 1.0 - absf(u * 2.0 - 1.0)
		if u >= 1.0: _blink_t = -1.0
	for lid in lids:
		lid.scale.y = lerpf(0.05, 1.0, closed)
		lid.position.y = lerpf(0.011, 0.0, closed)

## Verlet tip per swinging part (KawaiiPhysics style): carry its momentum, damp it, pull it back toward rest,
## let gravity act, keep it at its length from the pivot, then turn the pivot to point at it.
func _update_chains(dt: float) -> void:
	for c in _chains:
		var pivot: Node3D = c[0]
		var length: float = c[1]
		var rest_local: Vector3 = c[2]
		var parent := pivot.get_parent() as Node3D
		var base: Basis = c[5]
		var origin := pivot.global_position
		var rest_dir := (parent.global_transform.basis * (base * rest_local)).normalized()
		var rest_tip := origin + rest_dir * length
		if not c[6]:
			c[3] = rest_tip
			c[4] = rest_tip
			c[6] = true
		var tip: Vector3 = c[3]
		var prev: Vector3 = c[4]
		var nxt := tip + (tip - prev) * (1.0 - DAMPING) + GRAVITY * dt * dt
		nxt = nxt.lerp(rest_tip, STIFFNESS)
		nxt = origin + (nxt - origin).normalized() * length
		c[4] = tip
		c[3] = nxt
		# rotate the pivot so its rest direction turns onto the tip's direction
		var cur := (nxt - origin).normalized()
		var axis := rest_dir.cross(cur)
		var ang := rest_dir.angle_to(cur)
		var world_rot := Basis.IDENTITY
		if axis.length() > 1e-5 and ang > 1e-4: world_rot = Basis(axis.normalized(), minf(ang, 1.2))
		var pb := parent.global_transform.basis.orthonormalized()
		pivot.transform.basis = pb.inverse() * world_rot * pb * base

## A wave of the right hand (resting in bed, greetings).
func wave() -> void:
	var tw := create_tween()
	tw.tween_property(self, "wave_amount", 2.5, 0.2).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "wave_amount", 2.1, 0.15)
	tw.tween_property(self, "wave_amount", 2.5, 0.15)
	tw.tween_property(self, "wave_amount", 0.0, 0.3).set_trans(Tween.TRANS_SINE)

## 0..1 bounce of the walk, for the first-person head bob.
func bob() -> float:
	return absf(sin(_phase)) * clampf(_move, 0.0, 1.0)
