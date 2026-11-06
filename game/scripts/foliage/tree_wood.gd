class_name TreeWood
extends RefCounted
## The wood every tree species is built from: crooked tubes tapering as they go, with rounded tips, collars
## where they grow from a parent and a flared foot. Ported from just-a-simple-tree's wood.js (MIT, Mike
## Fernandez). The reference looks up the wood nearest a point in a spatial grid; here every species already
## knows which branch a child or clump grows from, so that branch's sway is passed along instead.
##
## Vertex data: CUSTOM0 = (flex 0..1, sway phase, height / tree height, 0) for the wind (foliage.gdshaderinc).
## Triangles are wound clockwise for Godot (three.js is counter-clockwise).

const CAP_RINGS := 3            # rings in the dome closing each branch's tip
const COLLAR := 0.9             # a child's base radius / its parent's radius there
const FLARE_HEIGHT := 5.0       # how far up a flared foot spreads / the branch's radius at its start
const FLARE_RINGS := 6
const STIFF_RADIUS := 0.02      # m: wood thinner than this flexes no more than this would
const PHASE_DRIFT := 2.5        # radians the sway's beat drifts along a branch, give or take half
const SPROUT_SPEED := 1.5       # a young tree: how fast a branch lengthens once sprouted / the growth's pace
const YOUNG_THICKNESS := 0.35   # a just-sprouted branch's thickness / full grown
const MIN_LENGTH := 1e-4
# Twigs: thin wood from each leaf clump's centre into it, for its leaves to hang from
const TWIG_REACH := 0.75
const TWIG_THICKNESS := 0.025
const TWIG_THINNER := 0.6
const TWIG_TAPER := 0.4
const TWIG_SEGMENTS := 3
const TWIG_SIDES := 3
const TWIG_LIFT := 0.15
const TWIG_AHEAD := 0.8
const TWIG_CROOKED := 2.0

const UP := Vector3.UP
const SIDE := Vector3.RIGHT
const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))

var p: Dictionary
var rnd: RandomNumberGenerator
var drift_rnd := RandomNumberGenerator.new()
var farthest := 1e-6            # how far along the wood from the ground the farthest grown tip is
var most := 1e-6                # the most flexible tip's flex, to put every flex on 0..1
var pos := PackedVector3Array()
var nrm := PackedVector3Array()
var sway := PackedFloat32Array()   # flex, phase per vertex (raw flex, normalised in build)
var idx := PackedInt32Array()

func _init(params: Dictionary, random: RandomNumberGenerator) -> void:
	p = params
	rnd = random
	drift_rnd.seed = int(p.seed) + 2903

## Turn a direction a random amount round itself, measured from `square`, a direction square to it.
func _kink(d: Vector3, amount: float, r: RandomNumberGenerator, square := Vector3.ZERO) -> Vector3:
	if square == Vector3.ZERO: square = perpendicular(d)
	var axis := square.rotated(d, r.randf() * TAU)
	return d.rotated(axis, (r.randf() - 0.5) * amount).normalized()

## One branch: a crooked tube from `start`, `segments` kinks long, each kink pulled to the sky by up_pull.
## Grown from a parent (o.parent: dir, radius, flex, phase) it starts as a collar as wide as the parent there.
## On a young tree (p.reach set) it is only as long and thick as it has grown, but always draws the same
## randoms, so the branches after it never move. Returns its kinks with their radii, flex and phase.
func branch(start: Vector3, dir: Vector3, full_length: float, full_radius: float, crookedness: float, o: Dictionary) -> Dictionary:
	var parent: Dictionary = o.get("parent", {})
	var from: float = o.get("from", 0.0)
	var segments: int = o.segments
	var length := _grown_length(from, full_length)
	var radius := full_radius * lerpf(YOUNG_THICKNESS, 1.0, length / full_length)
	var points: Array[Vector3] = [start]
	var radii: Array[float] = [float(parent.radius) * COLLAR if parent else radius]
	var d: Vector3 = (parent.dir as Vector3).lerp(dir, 0.5).normalized() if parent else dir.normalized()
	for i in range(1, segments + 1):
		if parent and i == 2: d = dir.normalized()
		d = _kink(d, crookedness, rnd)
		d = (d + UP * float(o.up_pull)).normalized()
		points.append(points[i - 1] + d * (length / segments))
		radii.append(radius * (1.0 - (1.0 - float(o.taper)) * (float(i) / segments)))
	var flexes: Array[float] = [float(parent.get("flex", 0.0))]
	var phases: Array[float] = [float(parent.get("phase", 0.0))]
	var drift := PHASE_DRIFT * (0.5 + drift_rnd.randf()) * (length / full_length)
	for i in range(1, points.size()):
		var thick := maxf((radii[i - 1] + radii[i]) * 0.5, STIFF_RADIUS)
		flexes.append(flexes[i - 1] + points[i].distance_to(points[i - 1]) / thick)
		phases.append(phases[0] + drift * i / segments)
	var br := {"points": points, "radii": radii, "flexes": flexes, "phases": phases}
	if length < MIN_LENGTH: return br
	farthest = maxf(farthest, from + length)
	most = maxf(most, flexes[-1])
	if p.get("measuring", false): return br
	var flare: float = o.get("flare", 0.0)
	var flare_to := minf(radius * FLARE_HEIGHT / length, 0.5) if flare > 0.0 else 0.0
	tube(points, radii, flexes, phases, int(o.get("sides", p.sides)), int(p.smoothness), CAP_RINGS, flare, flare_to)
	return br

func _grown_length(from: float, full_length: float) -> float:
	if not p.has("reach"): return full_length
	return clampf((float(p.front) * float(p.reach) - from) * SPROUT_SPEED, 0.0, full_length)

func tube(kinks: Array[Vector3], kr: Array[float], kf: Array[float], kp: Array[float], sides: int, smooth: int, caps: int, flare: float, flare_to: float) -> void:
	var steps := (kinks.size() - 1) * smooth
	var shares: Array[float] = []
	if flare_to > 0.0:
		for i in FLARE_RINGS: shares.append(float(i) / FLARE_RINGS * flare_to)
	for i in steps + 1:
		if float(i) / steps >= flare_to: shares.append(float(i) / steps)
	var pts: Array[Vector3] = []
	var rad: Array[float] = []
	var flx: Array[float] = []
	var phs: Array[float] = []
	var last := kinks.size() - 1
	for s in shares:
		var at := s * last
		var k := mini(floori(at), last - 1)
		var f := at - k
		if smooth == 1 and flare_to == 0.0: pts.append(kinks[roundi(at)])
		else: pts.append(_catmull(kinks, k, f))
		var widen := 1.0 + flare * pow(1.0 - s / flare_to, 2.0) if s < flare_to else 1.0
		rad.append(lerpf(kr[k], kr[k + 1], f) * widen)
		flx.append(lerpf(kf[k], kf[k + 1], f))
		phs.append(lerpf(kp[k], kp[k + 1], f))

	var base := pos.size()
	var normal := perpendicular((pts[1] - pts[0]).normalized())
	var tangent := Vector3.UP
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		tangent = (b - a).normalized()
		normal = (normal - tangent * normal.dot(tangent)).normalized()   # carried along, so the tube never twists
		_ring(pts[i], rad[i], 0.0, sides, normal, tangent, flx[i], phs[i])
	var end := pts[-1]
	var er := rad[-1]
	for k in range(1, caps + 1):
		var bend := float(k) / caps * PI * 0.5
		_ring(end + tangent * er * sin(bend), er * cos(bend), bend, sides, normal, tangent, flx[-1], phs[-1])
	for i in pts.size() - 1 + caps:
		for j in sides:
			var a := base + i * sides + j
			var b := base + i * sides + (j + 1) % sides
			idx.append_array([a, a + sides, b, b, a + sides, b + sides])

func _ring(center: Vector3, radius: float, bend: float, sides: int, normal: Vector3, tangent: Vector3, flex: float, phase: float) -> void:
	var binormal := tangent.cross(normal)
	for j in sides:
		var ang := float(j) / sides * TAU
		var v := normal * cos(ang) + binormal * sin(ang)
		pos.append(center + v * radius)
		nrm.append((v * cos(bend) + tangent * sin(bend)).normalized())
		sway.append(flex)
		sway.append(phase)

## Centripetal Catmull-Rom between kinks k and k + 1, as the reference's CatmullRomCurve3.
static func _catmull(k: Array[Vector3], i: int, t: float) -> Vector3:
	var p0 := k[maxi(i - 1, 0)]
	var p1 := k[i]
	var p2 := k[i + 1]
	var p3 := k[mini(i + 2, k.size() - 1)]
	if i == 0: p0 = p1 * 2.0 - p2
	if i + 2 >= k.size(): p3 = p2 * 2.0 - p1
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_squared_to(p1), 1e-8), 0.25)
	var t2 := t1 + pow(maxf(p1.distance_squared_to(p2), 1e-8), 0.25)
	var t3 := t2 + pow(maxf(p2.distance_squared_to(p3), 1e-8), 0.25)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var a2 := p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var a3 := p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var b1 := a1 * (t2 - tt) / (t2 - t0) + a2 * (tt - t0) / (t2 - t0)
	var b2 := a2 * (t3 - tt) / (t3 - t1) + a3 * (tt - t1) / (t3 - t1)
	return b1 * (t2 - tt) / (t2 - t1) + b2 * (tt - t1) / (t2 - t1)

## Twigs grown from each clump's centre out into it, `count` in a clump of average size, for its leaves to
## hang from. Each clump keeps its twigs' kinks (clump.twigs). A clump's `wood` is the branch it sits on.
func twigs(clumps: Array, count: int) -> void:
	var mean := 0.0
	for c in clumps: mean += pow(float(c.get("full_radius", c.radius)), 2.0)
	mean = sqrt(mean / maxf(clumps.size(), 1))
	var sides := mini(int(p.sides), TWIG_SIDES)
	for ci in clumps.size():
		var c: Dictionary = clumps[ci]
		var r := RandomNumberGenerator.new()
		r.seed = int(p.seed) + 6151 + ci * 7919
		var wood: Dictionary = c.get("wood", {})
		var radius: float = c.radius
		var thickness := minf(radius * TWIG_THICKNESS, float(wood.radius) * TWIG_THINNER if wood else INF)
		var n := maxi(1, roundi(count * float(c.get("full_radius", radius)) / mean)) if count > 0 else 0
		var turn := Basis.from_euler(Vector3(r.randf() * 6.28, r.randf() * 6.28, r.randf() * 6.28))
		var flatten: float = c.get("flatten", 1.0)
		c.twigs = []
		for i in n:
			var y := 1.0 - 2.0 * (i + 0.5) / n
			var ring := sqrt(1.0 - y * y)
			var ang := i * GOLDEN_ANGLE
			var out := turn * Vector3(cos(ang) * ring, y, sin(ang) * ring)
			if wood: out = (out + (wood.dir as Vector3) * TWIG_AHEAD).normalized()
			out.y *= flatten
			var length := out.length() * radius * TWIG_REACH * (0.8 + r.randf() * 0.4)
			var d := out.normalized()
			var square := turn * Vector3(-sin(ang), 0.0, cos(ang))
			var kinks: Array[Vector3] = [c.position]
			var radii: Array[float] = [thickness]
			for k in range(1, TWIG_SEGMENTS + 1):
				square = (square - d * square.dot(d)).normalized()
				d = _kink(d, float(p.crookedness) * TWIG_CROOKED, r, square)
				d = (d + UP * TWIG_LIFT).normalized()
				kinks.append(kinks[k - 1] + d * (length / TWIG_SEGMENTS))
				radii.append(thickness * (1.0 - (1.0 - TWIG_TAPER) * float(k) / TWIG_SEGMENTS))
			if length < MIN_LENGTH: continue
			var flex: float = wood.get("flex", 0.0)
			var phase: float = wood.get("phase", 0.0)
			var fl: Array[float] = []
			var ph: Array[float] = []
			for k in kinks.size():
				fl.append(flex)
				ph.append(phase)
			tube(kinks, radii, fl, ph, sides, 1, 1, 0.0, 0.0)
			c.twigs.append(kinks)

## The wood as a mesh, its flexes on 0..1 and its heights over `height` (the tree's, for the wind's bend).
func build(height: float) -> ArrayMesh:
	var m := ArrayMesh.new()
	if pos.is_empty(): return m
	var custom := PackedFloat32Array()
	custom.resize(pos.size() * 4)
	for i in pos.size():
		custom[i * 4] = minf(sway[i * 2] / most, 1.0)
		custom[i * 4 + 1] = sway[i * 2 + 1]
		custom[i * 4 + 2] = pos[i].y / height
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_CUSTOM0] = custom
	arr[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m

## Where a branch is, which way it goes, how thick it is and how it sways, `at` of the way along it.
static func along(br: Dictionary, at: float) -> Dictionary:
	var pts: Array = br.points
	var segs := pts.size() - 1
	var k := mini(floori(at * segs), segs - 1)
	var f := at * segs - k
	var a: Vector3 = pts[k]
	var b: Vector3 = pts[k + 1]
	return {"point": a.lerp(b, f), "dir": (b - a).normalized(), "radius": lerpf(br.radii[k], br.radii[k + 1], f),
		"flex": lerpf(br.flexes[k], br.flexes[k + 1], f), "phase": lerpf(br.phases[k], br.phases[k + 1], f)}

## A direction from its compass bearing and its rise off level, in radians.
static func heading(around: float, rise: float) -> Vector3:
	return Vector3(cos(around) * cos(rise), sin(rise), sin(around) * cos(rise))

## Lean a direction away from itself by `angle`, on the side `around`.
static func splay(d: Vector3, around: float, angle: float) -> Vector3:
	var axis := perpendicular(d).rotated(d, around)
	return d.rotated(axis, angle)

## A direction square to v: square to the sky, turning smoothly to square to SIDE as v nears upright.
static func perpendicular(v: Vector3) -> Vector3:
	var turn := smoothstep(0.87, 0.93, absf(v.y))
	if turn >= 1.0: return v.cross(SIDE).normalized()
	var square := v.cross(UP).normalized()
	if turn <= 0.0: return square
	return square.lerp(v.cross(SIDE).normalized(), turn).normalized()

## How much longer a branch heading `around` is on a crown heavier by `heavy` towards `side`.
static func lopsided(around: float, side: float, heavy: float) -> float:
	return 1.0 + heavy * cos(around - side)
