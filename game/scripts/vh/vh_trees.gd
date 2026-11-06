class_name VHTrees
extends RefCounted
## Port of the reference's trees.ts: species-driven branching trees (tapered bark tubes with
## parallel-transport frames, cluster leaf cards on the outer branches, conifer whorls, roots),
## each with a high and a low LOD. Vertex data: COLOR = bark/leaf AO tint, UV2 = wind (weight, phase).
## Triangles are wound clockwise for Godot (three.js is counter-clockwise).

const DEG := PI / 180.0
const LEAF_DENSITY := 1.45     # leaf cards per metre of twig, over each species' own figure
const LEAF_SCALE := 0.82       # and each card that much smaller: a finer, fuller crown
const SPECIES := {
	"broadleaf": {"kind": "deciduous", "leaf": "broad", "height": [3.4, 4.4], "radius": [0.2, 0.27], "lean": 0.2, "gnarl": 0.24, "levels": 3,
		"children": [4, 5, 4], "angle": [36, 44, 48], "lenRatio": [0.78, 0.56, 0.55], "start": [0.55, 0.22, 0.2], "upward": [0.025, 0.05, 0.05],
		"leafLevel": 2, "leafPerM": 4.2, "leafSize": [1.0, 1.4], "bark": [0.5, 0.43, 0.36], "roots": true},
	"oak": {"kind": "deciduous", "leaf": "oak", "height": [2.4, 3.1], "radius": [0.32, 0.42], "lean": 0.12, "gnarl": 0.36, "levels": 3,
		"children": [6, 4, 4], "angle": [58, 44, 46], "lenRatio": [1.05, 0.58, 0.52], "start": [0.62, 0.2, 0.2], "upward": [0.012, 0.03, 0.04],
		"leafLevel": 2, "leafPerM": 3.9, "leafSize": [1.1, 1.45], "bark": [0.46, 0.4, 0.34], "roots": true},
	"young": {"kind": "deciduous", "leaf": "broad", "height": [2.4, 3.4], "radius": [0.08, 0.12], "lean": 0.08, "gnarl": 0.14, "levels": 2,
		"children": [7, 5], "angle": [34, 40], "lenRatio": [0.55, 0.5], "start": [0.4, 0.3], "upward": [0.08, 0.06],
		"leafLevel": 1, "leafPerM": 5.5, "leafSize": [0.75, 1.0], "bark": [0.55, 0.5, 0.42]},
	"blossom": {"kind": "deciduous", "leaf": "blossom", "height": [1.9, 2.5], "radius": [0.13, 0.18], "lean": 0.12, "gnarl": 0.3, "levels": 3,
		"children": [4, 4, 3], "angle": [46, 44, 40], "lenRatio": [0.8, 0.56, 0.5], "start": [0.65, 0.25, 0.25], "upward": [0.03, 0.04, 0.05],
		"leafLevel": 2, "leafPerM": 4.4, "leafSize": [0.85, 1.1], "bark": [0.45, 0.38, 0.33]},
	"spruce": {"kind": "conifer", "leaf": "needle", "height": [11, 17], "radius": [0.22, 0.32], "lean": 0.03, "gnarl": 0.05, "levels": 1,
		"children": [6], "angle": [95], "lenRatio": [0.3], "start": [0.15], "upward": [0.07],
		"leafLevel": 1, "leafPerM": 4.8, "leafSize": [0.95, 1.3], "bark": [0.4, 0.33, 0.28]},
	"shrub": {"kind": "shrub", "leaf": "shrub", "height": [0.7, 1.2], "radius": [0.025, 0.04], "lean": 0.3, "gnarl": 0.3, "levels": 2,
		"children": [6, 3], "angle": [32, 45], "lenRatio": [1, 0.5], "start": [0, 0.3], "upward": [0.04, 0.04],
		"leafLevel": 1, "leafPerM": 9, "leafSize": [0.45, 0.65], "bark": [0.4, 0.35, 0.3]},
}

class Geo:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var wind := PackedVector2Array()
	var idx := PackedInt32Array()
	func count() -> int: return pos.size()
	func tri(a: int, b: int, c: int) -> void:
		idx.append(a); idx.append(c); idx.append(b)      # flip to Godot's clockwise front faces
	func build() -> ArrayMesh:
		var m := ArrayMesh.new()
		if pos.is_empty(): return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV2] = wind
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

static func _perp(d: Vector3) -> Array:
	var a := Vector3(0, 1, 0) if absf(d.y) < 0.95 else Vector3(1, 0, 0)
	var u := d.cross(a).normalized()
	var v := d.cross(u).normalized()
	return [u, v]

static func _deviate(d: Vector3, ang: float, az: float) -> Vector3:
	var b := _perp(d)
	return (d * cos(ang) + b[0] * (cos(az) * sin(ang)) + b[1] * (sin(az) * sin(ang))).normalized()

static func _poly_at(pts: Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(pts.size() - 2, floori(f))
	return (pts[i] as Vector3).lerp(pts[i + 1], f - i)

static func _poly_dir(pts: Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(pts.size() - 2, floori(f))
	return ((pts[i + 1] as Vector3) - pts[i]).normalized()

static func _tube(g: Geo, br: Dictionary, radial: int, bark: Array, tree_h: float) -> void:
	var pts: Array = br.pts
	var n := pts.size()
	var T: Array = []
	var N: Array = []
	for i in n: T.append(((pts[mini(i + 1, n - 1)] as Vector3) - pts[maxi(i - 1, 0)]).normalized())
	N.append(_perp(T[0])[0])
	for i in range(1, n):
		var axis: Vector3 = (T[i - 1] as Vector3).cross(T[i])
		var l := axis.length()
		var nn: Vector3 = N[i - 1]
		if l > 1e-6: nn = nn.rotated(axis / l, acos(clampf((T[i - 1] as Vector3).dot(T[i]), -1.0, 1.0)))
		N.append(nn)
	var base := g.count()
	var v_acc := 0.0
	var u_rep := 2.0 if br.rad[0] > 0.12 else 1.0
	for i in n:
		if i > 0: v_acc += (pts[i] as Vector3).distance_to(pts[i - 1])
		var B: Vector3 = (T[i] as Vector3).cross(N[i])
		var p: Vector3 = pts[i]
		var ao := lerpf(0.55, 1.0, clampf(p.y / 1.6, 0.0, 1.0)) if br.level == 0 else 0.92
		var w: float = pow(clampf(p.y / tree_h, 0.0, 1.0), 2.0) * 0.5 if br.level == 0 else br.wind0 + (float(i) / maxi(1, n - 1)) * 0.3
		for j in radial + 1:
			var a := float(j) / radial * TAU
			var nv: Vector3 = (N[i] as Vector3) * cos(a) + B * sin(a)
			var r: float = br.rad[i]
			g.pos.append(p + nv * r)
			g.nrm.append(nv)
			g.uv.append(Vector2(float(j) / radial * u_rep, v_acc / 1.3))
			g.col.append(Color(bark[0] * ao, bark[1] * ao, bark[2] * ao))
			g.wind.append(Vector2(w, br.phase))
	for i in n - 1:
		for j in radial:
			var a := base + i * (radial + 1) + j
			var b := a + radial + 1
			g.tri(a, a + 1, b)
			g.tri(a + 1, b + 1, b)

static func _cards(g: Geo, leaves: Array, keep_every: int, size_mul: float, cone: bool, rnd: VHNoise) -> void:
	if leaves.is_empty(): return
	var c := Vector3.ZERO
	for L in leaves: c += L.p
	c /= leaves.size()
	var rad := 0.0
	for L in leaves: rad += (L.p as Vector3).distance_to(c)
	rad = maxf(0.3, rad / leaves.size()) * 1.35
	for i in leaves.size():
		if i % keep_every: continue
		var L: Dictionary = leaves[i]
		var s: float = L.s * size_mul
		var up: Vector3 = L.up
		var right: Vector3 = up.cross(L.n)
		if right.length_squared() < 1e-6: right = Vector3(1, 0, 0)
		right = right.normalized()
		var out: Vector3
		if cone: out = (Vector3(L.p.x, 0, L.p.z).normalized() + Vector3(0, 0.55, 0)).normalized()
		else: out = (((L.p as Vector3) - c) * Vector3(1, 0.8, 1)).normalized()
		var face: Vector3 = -(L.n as Vector3) if (L.n as Vector3).dot(out) < 0.0 else L.n
		var nn := (face * 0.3 + out * 0.7).normalized()
		var depth := clampf(Vector2(L.p.x, L.p.z).length() / (rad * 0.9), 0.0, 1.0) if cone else clampf((L.p as Vector3).distance_to(c) / rad, 0.0, 1.0)
		var ao := clampf(0.48 + 0.62 * depth + (L.p.y - c.y) / (rad * 6.0), 0.45, 1.08) * (0.88 + rnd.next() * 0.24)
		var tint := 0.94 + rnd.next() * 0.12
		var b := g.count()
		for o in [[-0.5, -0.1, 0.0, 0.0], [0.5, -0.1, 1.0, 0.0], [0.5, 0.9, 1.0, 1.0], [-0.5, 0.9, 0.0, 1.0]]:
			g.pos.append((L.p as Vector3) + right * (o[0] * s) + up * (o[1] * s))
			g.nrm.append(nn)
			g.uv.append(Vector2(o[2], o[3]))
			g.col.append(Color(ao * tint, ao, ao * (2.0 - tint) * 0.98))
			g.wind.append(Vector2(L.w + o[3] * 0.15, L.ph))
		g.tri(b, b + 1, b + 2)
		g.tri(b, b + 2, b + 3)

## {high: {trunk, leaves}, low: {trunk, leaves}, leaf, height, trunk_radius, crown_radius}
static func build(species: String, seed: int, opts := {}) -> Dictionary:
	var sp: Dictionary = SPECIES[species]
	var rnd := VHNoise.rng(seed)
	var R := func(a: float, b: float) -> float: return a + (b - a) * rnd.next()
	var branches: Array = []
	var leaves: Array = []
	var r0: float = R.call(sp.radius[0], sp.radius[1])
	var levels: int = sp.levels

	var place_leaves := func(br: Dictionary, length: float) -> void:
		if br.level < int(sp.leafLevel): return
		var terminal: bool = br.level == levels
		var count := roundi(length * float(sp.leafPerM) * LEAF_DENSITY * (1.0 if terminal else 0.55))
		for k in count:
			var t: float = R.call(0.25 if terminal else 0.5, 1.0)
			var p := _poly_at(br.pts, t)
			var bd := _poly_dir(br.pts, t)
			var s: float = R.call(sp.leafSize[0], sp.leafSize[1]) * LEAF_SCALE
			if sp.get("hanging", false):
				var up := Vector3((rnd.next() - 0.5) * 0.25, -1.0, (rnd.next() - 0.5) * 0.25).normalized()
				var a := rnd.next() * TAU
				leaves.append({"p": p + Vector3((rnd.next() - 0.5) * 0.3, 0.1, (rnd.next() - 0.5) * 0.3), "up": up, "n": Vector3(cos(a), 0, sin(a)), "s": s * R.call(0.8, 1.2), "w": br.wind0 + 0.35, "ph": rnd.next()})
			else:
				var up := (bd * 0.75 + Vector3((rnd.next() - 0.5) * 0.9, 0.35 + rnd.next() * 0.4, (rnd.next() - 0.5) * 0.9)).normalized()
				var n := Vector3(rnd.next() - 0.5, rnd.next() * 0.8, rnd.next() - 0.5).normalized()
				n = (n - up * n.dot(up)).normalized()
				p += Vector3((rnd.next() - 0.5) * 0.25, (rnd.next() - 0.5) * 0.2, (rnd.next() - 0.5) * 0.25)
				leaves.append({"p": p, "up": up, "n": n, "s": s, "w": br.wind0 + 0.25 + t * 0.15, "ph": rnd.next()})

	var grow_ref: Array = [null]       # lambdas capture by value: recurse through a shared slot
	var grow := func(start: Vector3, dir: Vector3, length: float, rad: float, level: int, wind0: float) -> void:
		var seg_len := 0.45 if level == 0 else (0.4 if level == 1 else 0.32)
		var segs := maxi(2, ceili(length / seg_len))
		var pts: Array = [start]
		var rads: Array = [rad]
		var d := dir
		var p := start
		var tip := rad * 0.3 if level >= levels else rad * 0.42
		var upw: Array = sp.upward
		for i in range(1, segs + 1):
			d.x += (rnd.next() - 0.5) * float(sp.gnarl)
			d.y += (rnd.next() - 0.5) * float(sp.gnarl) * 0.6
			d.z += (rnd.next() - 0.5) * float(sp.gnarl)
			d.y += (float(upw[level]) if level < upw.size() else 0.04) * (length / segs)
			if sp.kind != "shrub" and level > 0 and d.y < -0.25: d.y = -0.25
			d = d.normalized()
			p += d * (length / segs)
			pts.append(p)
			rads.append(lerpf(rad, tip, pow(float(i) / segs, 0.85)))
		if level == 0:
			rads[0] *= 1.5
			if rads.size() > 2: rads[1] *= 1.12
		var br := {"pts": pts, "rad": rads, "level": level, "wind0": wind0, "phase": rnd.next() * 6.283}
		branches.append(br)
		if level < levels:
			var n := maxi(1, roundi(float(sp.children[level]) * R.call(0.75, 1.25)))
			var st: float = sp.start[level]
			var az := rnd.next() * 6.283
			for k in n:
				var t := lerpf(st, 0.96, (k + R.call(0.15, 0.85)) / n)
				var pos := _poly_at(pts, t)
				var pd := _poly_dir(pts, t)
				var fi := t * (pts.size() - 1)
				var i0 := mini(pts.size() - 2, floori(fi))
				var prad := lerpf(rads[i0], rads[i0 + 1], fi - i0)
				az += 2.39996 + R.call(-0.35, 0.35)
				var cdir := _deviate(pd, (float(sp.angle[level]) + R.call(-12.0, 12.0)) * DEG, az)
				var clen: float = length * float(sp.lenRatio[level]) * (1.0 - 0.5 * ((t - st) / maxf(0.05, 1.0 - st))) * R.call(0.8, 1.15)
				grow_ref[0].call(pos, cdir, clen, prad * R.call(0.55, 0.72), level + 1, wind0 + 0.22 + t * 0.2)
		place_leaves.call(br, length)
	grow_ref[0] = grow

	var tree_h: float
	if sp.kind == "conifer":
		var H: float = R.call(sp.height[0], sp.height[1])
		tree_h = H
		var segs := 16
		var pts: Array = []
		var rad: Array = []
		var bx := (rnd.next() - 0.5) * 0.5
		var bz := (rnd.next() - 0.5) * 0.5
		for i in segs + 1:
			var t := float(i) / segs
			pts.append(Vector3(bx * t * t, -0.3 + t * (H + 0.3), bz * t * t))
			rad.append(lerpf(r0, 0.015, pow(t, 0.9)))
		rad[0] *= 1.4
		branches.append({"pts": pts, "rad": rad, "level": 0, "wind0": 0.0, "phase": 0.0})
		var crown_base: float = H * R.call(0.08, 0.18)
		var y := crown_base
		var wi := 0
		while y < H * 0.95:
			var rel := (y - crown_base) / (H - crown_base)
			var n := roundi(R.call(5.0, 7.0))
			var length: float = (H * 0.29 * pow(1.0 - rel, 0.92) + 0.25) * R.call(0.85, 1.12)
			var tp := _poly_at(pts, (y + 0.3) / (H + 0.3))
			var trad := lerpf(r0, 0.015, pow(y / H, 0.9))
			for k in n:
				var az: float = wi * 0.7 + float(k) / n * TAU + R.call(-0.25, 0.25)
				var dir := Vector3(cos(az), lerpf(-0.45, 0.15, rel) + R.call(-0.1, 0.1), sin(az)).normalized()
				var bp: Array = [tp]
				var brr: Array = [trad * 0.35 + 0.012]
				var d := dir
				var p := tp
				for i in range(1, 5):
					d.y += 0.07 + (rnd.next() - 0.5) * 0.05
					d = d.normalized()
					p += d * (length / 4.0)
					bp.append(p)
					brr.append(lerpf(brr[0], 0.008, i / 4.0))
				var w0 := 0.3 + rel * 0.4
				branches.append({"pts": bp, "rad": brr, "level": 1, "wind0": w0, "phase": rnd.next() * 6.283})
				var cards := maxi(2, roundi(length * float(sp.leafPerM) * LEAF_DENSITY))
				for c in cards:
					var t := lerpf(0.12, 1.0, (c + rnd.next()) / cards)
					var pp := _poly_at(bp, t)
					var bd := _poly_dir(bp, t)
					var up := (bd + Vector3((rnd.next() - 0.5) * 0.5, (rnd.next() - 0.4) * 0.3, (rnd.next() - 0.5) * 0.5)).normalized()
					var nn := Vector3((rnd.next() - 0.5) * 0.8, 1.0, (rnd.next() - 0.5) * 0.8).normalized()
					nn = (nn - up * nn.dot(up)).normalized()
					var s: float = R.call(sp.leafSize[0], sp.leafSize[1]) * LEAF_SCALE * lerpf(1.0, 0.6, rel) * lerpf(1.0, 0.72, t)
					leaves.append({"p": pp + up * (-s * 0.15), "up": up, "n": nn, "s": s, "w": w0 + 0.2 + t * 0.3, "ph": rnd.next()})
			y += R.call(0.4, 0.62) * lerpf(1.0, 0.6, rel)
			wi += 1
		for c in 7:
			var up := Vector3((rnd.next() - 0.5) * 0.6, 1.0, (rnd.next() - 0.5) * 0.6).normalized()
			leaves.append({"p": Vector3(bx, H - 0.9 + c * 0.13, bz), "up": up, "n": Vector3(rnd.next() - 0.5, 0.1, rnd.next() - 0.5).normalized(), "s": 0.75, "w": 0.95, "ph": rnd.next()})
	elif sp.kind == "shrub":
		var H: float = R.call(sp.height[0], sp.height[1])
		tree_h = H
		var stems := roundi(R.call(5.0, 8.0))
		for k in stems:
			var az: float = float(k) / stems * TAU + R.call(-0.3, 0.3)
			var dir := Vector3(cos(az) * sin(R.call(0.25, 0.8)), 1.0, sin(az) * sin(R.call(0.25, 0.8))).normalized()
			grow.call(Vector3(R.call(-0.08, 0.08), -0.05, R.call(-0.08, 0.08)), dir, H * R.call(0.75, 1.1), r0, 1, 0.3)
	else:
		var length: float = R.call(sp.height[0], sp.height[1])
		var lean: float = opts.lean if opts.has("lean") else float(sp.lean) * (0.4 + 0.6 * rnd.next())
		var ld: float = opts.leanDir if opts.has("leanDir") else rnd.next() * TAU
		var dir := Vector3(sin(lean) * cos(ld), cos(lean), sin(lean) * sin(ld))
		grow.call(Vector3(0, -0.3, 0), dir, length, r0, 0, 0.0)
		tree_h = length * 2.2
		if sp.get("roots", false):
			var nr := 5
			for k in nr:
				var az: float = float(k) / nr * TAU + R.call(-0.4, 0.4)
				var rp: Array = []
				var rr: Array = []
				for i in 5:
					var t := i / 4.0
					var dist: float = t * R.call(0.9, 1.4) * (r0 * 5.0)
					rp.append(Vector3(cos(az) * dist, 0.25 - t * 0.55 - t * t * 0.1, sin(az) * dist))
					rr.append(lerpf(r0 * 0.55, r0 * 0.12, t))
				branches.append({"pts": rp, "rad": rr, "level": 0, "wind0": 0.0, "phase": 0.0})

	var bark: Array = sp.bark
	var radial_high := [14, 9, 6, 4]
	var radial_low := [5, 4, 3, 3]
	var tH := Geo.new()
	var tL := Geo.new()
	var lH := Geo.new()
	var lL := Geo.new()
	for br in branches:
		if br.rad[0] < 0.008: continue
		_tube(tH, br, radial_high[mini(3, br.level)], bark, tree_h)
		# low LOD: the reference keeps level <= 1; whorl twigs vanish behind needle cards, so conifers keep only the trunk
		# ponytail: our valley holds thousands of spruces vs the reference's ~20, revisit if close-up low LODs look bare
		if (br.level <= 1 and not (sp.kind == "conifer" and br.level == 1)) or br.rad[0] > 0.05: _tube(tL, br, radial_low[mini(3, br.level)], bark, tree_h)
	var cone: bool = sp.kind == "conifer"
	_cards(lH, leaves, 1, 1.0, cone, rnd)
	_cards(lL, leaves, 2, 1.42, cone, VHNoise.rng(seed + 1))
	var top := 0.0
	var cr := 0.0
	for L in leaves:
		top = maxf(top, L.p.y + L.s)
		cr = maxf(cr, Vector2(L.p.x, L.p.z).length())
	if sp.kind == "shrub": r0 = 0.0
	return {"high": {"trunk": tH.build(), "leaves": lH.build()}, "low": {"trunk": tL.build(), "leaves": lL.build()},
		"leaf": sp.leaf, "height": top, "trunk_radius": r0, "crown_radius": cr}

## Fern rosette: arching frond cards.
static func build_fern(seed: int) -> ArrayMesh:
	var rnd := VHNoise.rng(seed)
	var g := Geo.new()
	var n := 8
	for k in n:
		var a := float(k) / n * TAU + (rnd.next() - 0.5) * 0.5
		var L := 0.55 + rnd.next() * 0.35
		var w := 0.26
		var dx := cos(a)
		var dz := sin(a)
		var sx := -dz
		var sz := dx
		var base := g.count()
		var segs := 4
		for i in segs + 1:
			var t := float(i) / segs
			var y := sin(t * PI * 0.75) * 0.42 * L + 0.02
			var r := t * L
			for side in [-0.5, 0.5]:
				g.pos.append(Vector3(dx * r + sx * side * w * (1.0 - t * 0.4), y, dz * r + sz * side * w * (1.0 - t * 0.4)))
				g.nrm.append(Vector3(dx * 0.3, 0.95, dz * 0.3))
				g.uv.append(Vector2(side + 0.5, t))
				var ao := 0.6 + t * 0.45
				g.col.append(Color(ao, ao, ao))
				g.wind.append(Vector2(0.25 + t * 0.6, rnd.next()))
		for i in segs:
			var q := base + i * 2
			g.tri(q, q + 1, q + 2)
			g.tri(q + 1, q + 3, q + 2)
	return g.build()
