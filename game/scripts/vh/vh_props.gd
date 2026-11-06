class_name VHProps
extends RefCounted
## Ports of the reference's rocks.ts (fractured noise boulders), structures.ts (LED bollards, the
## slender bridge) and distant.ts (the ring-tower city, silhouette trees for the far hills).
## Geometry is authored counter-clockwise like three.js and flipped once when built.

## Non-indexed triangle soup with flat or supplied normals, flipped to Godot's winding on build().
class Bag:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	func tri(a: Vector3, b: Vector3, c: Vector3, k: Color, uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
		var n := (b - a).cross(c - a).normalized()
		for v in [[a, uva], [c, uvc], [b, uvb]]:
			pos.append(v[0]); nrm.append(n); col.append(k); uv.append(v[1])
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, k: Color) -> void:
		tri(a, b, c, k); tri(a, c, d, k)
	## Axis box centred on t.origin.
	func box(t: Transform3D, s: Vector3, k: Color) -> void:
		var h := s * 0.5
		var p := []
		for i in 8: p.append(t * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
		for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], k)
	## Cylinder / cone (r1 = 0) standing on t.origin, three.js style (centred: offset applied by caller).
	func cyl(t: Transform3D, r0: float, r1: float, h: float, seg: int, k: Color) -> void:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var b0 := t * Vector3(sin(a0) * r0, 0, cos(a0) * r0)
			var b1 := t * Vector3(sin(a1) * r0, 0, cos(a1) * r0)
			var u0 := t * Vector3(sin(a0) * r1, h, cos(a0) * r1)
			var u1 := t * Vector3(sin(a1) * r1, h, cos(a1) * r1)
			if r1 > 0.0: quad(b0, b1, u1, u0, k)
			else: tri(b0, b1, u0, k)
			tri(t * Vector3(0, 0, 0), b1, b0, k)
			if r1 > 0.0: tri(t * Vector3(0, h, 0), u0, u1, k)
	func build() -> ArrayMesh:
		var m := ArrayMesh.new()
		if pos.is_empty(): return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

# --- rocks ------------------------------------------------------------------------------------------------
static var _rock_noise: VHNoise

## three.js IcosahedronGeometry(1, detail) with merged vertices: [Array of unit Vector3, indices (Godot winding)].
static func icosphere(detail: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var iv := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var ii := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var verts: Array = []
	var index := {}
	var idx := PackedInt32Array()
	var add := func(p: Vector3) -> int:
		var q := p.normalized()
		var key := Vector3i(roundi(q.x * 1e4), roundi(q.y * 1e4), roundi(q.z * 1e4))
		if index.has(key): return index[key]
		index[key] = verts.size()
		verts.append(q)
		return verts.size() - 1
	var cols := detail + 1
	for f in range(0, ii.size(), 3):
		var a: Vector3 = iv[ii[f]]
		var b: Vector3 = iv[ii[f + 1]]
		var c: Vector3 = iv[ii[f + 2]]
		var v: Array = []
		for i in cols + 1:
			var aj := a.lerp(c, float(i) / cols)
			var bj := b.lerp(c, float(i) / cols)
			var rows := cols - i
			var row: Array = []
			for j in rows + 1:
				row.append(aj if j == 0 and i == cols else aj.lerp(bj, float(j) / rows if rows > 0 else 0.0))
			v.append(row)
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := j / 2
				var tri: Array
				if j % 2 == 0: tri = [v[i][k + 1], v[i + 1][k], v[i][k]]
				else: tri = [v[i][k + 1], v[i + 1][k + 1], v[i + 1][k]]
				var i0: int = add.call(tri[0])
				var i1: int = add.call(tri[1])
				var i2: int = add.call(tri[2])
				idx.append(i0); idx.append(i2); idx.append(i1)
	return [verts, idx]

## Icosphere (three.js PolyhedronGeometry subdivision, merged) displaced by simplex fBm, cut by planes.
static func rock(seed: int, detail := 6, angular := 1.0) -> ArrayMesh:
	if _rock_noise == null: _rock_noise = VHNoise.simplex(777)
	var S := _rock_noise
	var rnd := VHNoise.rng(seed)
	var ico := icosphere(detail)
	var verts: Array = ico[0]
	var idx: PackedInt32Array = ico[1]
	var cuts: Array = []
	var nc := roundi(lerpf(3.0, 7.0, rnd.next()) * angular)
	for i in nc: cuts.append([Vector3(rnd.next() - 0.5, (rnd.next() - 0.5) * 1.2, rnd.next() - 0.5).normalized(), lerpf(0.55, 0.85, rnd.next())])
	cuts.append([Vector3(0, -1, 0), 0.35])
	var off := rnd.next() * 100.0
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	for q in verts:
		var vv: Vector3 = q
		var disp := S.fbm3(vv.x * 1.3 + off, vv.y * 1.3, vv.z * 1.3, 4) * 0.32 + (1.0 - absf(S.noise3(vv.x * 3.2 + off, vv.y * 3.2, vv.z * 3.2))) * 0.07
		vv *= 1.0 + disp
		for c in cuts:
			var e: float = vv.dot(c[0]) - c[1]
			if e > 0.0: vv -= c[0] * (e * 0.9)
		vv.x += S.noise3(vv.x * 6.0 + off, vv.y * 6.0, vv.z * 6.0) * 0.02
		vv.y += S.noise3(vv.x * 6.0, vv.y * 6.0 + off, vv.z * 6.0) * 0.02
		pos.append(vv)
		var ao := clampf(0.62 + disp * 1.1 + (vv.y + 0.35) * 0.22, 0.4, 1.05)
		col.append(Color(ao, ao, ao))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pos.size():
		st.set_color(col[i])
		st.add_vertex(pos[i])
	for i in idx: st.add_index(i)
	st.generate_normals()
	return st.commit()

# --- bollards + light pools -----------------------------------------------------------------------------------
## Metal base, LED tube, cap. Returns [metal Bag, led Bag]-ready geometry appended in place.
static func bollard(metal: Bag, led: Bag, p: Vector3) -> void:
	metal.box(Transform3D(Basis(), p + Vector3(0, 0.2, 0)), Vector3(0.13, 0.4, 0.13), Color(1, 1, 1))
	led.cyl(Transform3D(Basis(), p + Vector3(0, 0.4, 0)), 0.038, 0.038, 1.55, 10, Color(1, 1, 1))
	metal.box(Transform3D(Basis(), p + Vector3(0, 1.99, 0)), Vector3(0.11, 0.08, 0.11), Color(1, 1, 1))

## Additive warm disc conforming to the ground around a bollard (UV = glow texture coords).
static func light_pool(bag: Bag, p: Vector3, height: Callable, r := 2.8) -> void:
	var seg := 24
	var ground := func(x: float, z: float) -> float:
		var g := maxf(height.call(x, z), p.y - 0.02)
		return (p.y if absf(g - p.y) < 0.3 else g) + 0.04
	var c := Vector3(p.x, ground.call(p.x, p.z), p.z)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var x0 := p.x + cos(a0) * r
		var z0 := p.z + sin(a0) * r
		var x1 := p.x + cos(a1) * r
		var z1 := p.z + sin(a1) * r
		bag.tri(c, Vector3(x1, ground.call(x1, z1), z1), Vector3(x0, ground.call(x0, z0), z0), Color(1, 1, 1),
			Vector2(0.5, 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5))

# --- the slender bridge (structures.ts), built along local +X from 0 to L ------------------------------------------
## Returns {paving, concrete, metal, led_soft: Bag}. deck_y(u) gives the deck height for u in 0..1.
static func bridge(L: float, width: float, deck_y: Callable) -> Dictionary:
	var b := {"paving": Bag.new(), "concrete": Bag.new(), "metal": Bag.new(), "led_soft": Bag.new()}
	var hw := width * 0.5
	var N := 56
	var white := Color(1, 1, 1)
	var prev: Array = []
	for i in N + 1:
		var x := L * i / N
		var y: float = deck_y.call(float(i) / N)
		var t := 2.0 * i / N - 1.0
		var depth := 0.72 + 0.55 * t * t
		var row := [Vector3(x, y, hw), Vector3(x, y, -hw), Vector3(x, y - 0.26, -hw), Vector3(x, y - depth, -1.0), Vector3(x, y - depth, 1.0), Vector3(x, y - 0.26, hw)]
		if not prev.is_empty():
			b.paving.quad(prev[0], row[0], row[1], prev[1], white)
			for k in [1, 2, 3, 4]:
				b.concrete.quad(prev[k], row[k], row[k + 1], prev[k + 1], white)
			b.concrete.quad(prev[5], row[5], row[0], prev[0], white)
		prev = row
	var top: float = deck_y.call(0.0)
	for e in [[0.0, -1.0], [L, 1.0]]:
		var ax: float = e[0]
		var dir: float = e[1]
		b.concrete.box(Transform3D(Basis(), Vector3(ax + dir * 1.8, top - 1.9, 0)), Vector3(3.8, 3.8, width + 0.8), white)
		b.paving.box(Transform3D(Basis(), Vector3(ax + dir * 2.2, top - 0.05, 0)), Vector3(4.4, 0.1, width), white)
		for s in [-1.0, 1.0]:
			b.concrete.box(Transform3D(Basis(), Vector3(ax + dir * 2.2, top + 0.25, s * (hw + 0.2))), Vector3(4.4, 0.6, 0.4), white)
	for side in [-1.0, 1.0]:
		var zr: float = side * (hw - 0.08)
		for i in N:
			var xa := L * i / N
			var xb := L * (i + 1) / N
			var ya: float = deck_y.call(float(i) / N)
			var yb: float = deck_y.call(float(i + 1) / N)
			var len := Vector2(xb - xa, yb - ya).length()
			var rot := Basis(Vector3(0, 0, 1), atan2(yb - ya, xb - xa))
			var m := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5, zr)
			b.metal.box(Transform3D(rot, m + Vector3(0, 1.06, 0)), Vector3(len + 0.01, 0.05, 0.07), white)
			b.metal.box(Transform3D(rot, m + Vector3(0, 0.12, 0)), Vector3(len + 0.01, 0.03, 0.04), white)
			b.led_soft.box(Transform3D(rot, m + Vector3(0, 1.02, -side * 0.04)), Vector3(len + 0.01, 0.015, 0.012), white)
			for k in 5:
				var bx := xa + (k + 0.5) / 5.0 * (xb - xa)
				var by: float = deck_y.call(bx / L)
				b.metal.box(Transform3D(Basis(), Vector3(bx, by + 0.58, zr)), Vector3(0.016, 0.96, 0.016), white)
			if i % 4 == 0: b.metal.box(Transform3D(Basis(), Vector3(xa, ya + 0.55, zr)), Vector3(0.06, 1.1, 0.06), white)
	return b

# --- distant city (distant.ts createCity) ------------------------------------------------------------------------
static func _prism(bag: Bag, cx: float, cz: float, w: float, d: float, h: float, ch: float, taper: float, slope: float, tint: float) -> void:
	var ring := func(sx: float, sz: float) -> Array:
		var hw := w / 2.0 * sx
		var hd := d / 2.0 * sz
		var c := ch * minf(sx, sz)
		return [[-hw + c, -hd], [hw - c, -hd], [hw, -hd + c], [hw, hd - c], [hw - c, hd], [-hw + c, hd], [-hw, hd - c], [-hw, -hd + c]]
	var b: Array = ring.call(1.0, 1.0)
	var t: Array = ring.call(taper, taper)
	var top := func(x: float) -> float: return h + slope * (x / (w / 2.0))
	var k := Color(tint, tint, tint)
	for i in 8:
		var j := (i + 1) % 8
		var p0 := Vector3(cx + b[i][0], 0, cz + b[i][1])
		var p1 := Vector3(cx + b[j][0], 0, cz + b[j][1])
		var p2 := Vector3(cx + t[j][0], top.call(t[j][0]), cz + t[j][1])
		var p3 := Vector3(cx + t[i][0], top.call(t[i][0]), cz + t[i][1])
		bag.tri(p0, p2, p1, k)
		bag.tri(p0, p3, p2, k)
	for i in range(1, 7):
		bag.tri(Vector3(cx + t[0][0], top.call(t[0][0]), cz + t[0][1]), Vector3(cx + t[i + 1][0], top.call(t[i + 1][0]), cz + t[i + 1][1]), Vector3(cx + t[i][0], top.call(t[i][0]), cz + t[i][1]), k)

static func _torus(bag: Bag, xf: Transform3D, R: float, r: float, rs: int, ts: int, tint: float) -> void:
	var k := Color(tint, tint, tint)
	var P := func(i: int, j: int) -> Vector3:
		var u := TAU * j / ts
		var v := TAU * i / rs
		return xf * Vector3((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r * sin(v))
	for i in rs:
		for j in ts:
			bag.quad(P.call(i, j), P.call(i + 1, j), P.call(i + 1, j + 1), P.call(i, j + 1), k)

## Returns {solid: ArrayMesh, glow: ArrayMesh}; origin = city centre on the ground.
static func city() -> Dictionary:
	var rnd := VHNoise.rng(88)
	var R := func(a: float, b: float) -> float: return a + (b - a) * rnd.next()
	var solid := Bag.new()
	var glow := Bag.new()
	var strip := func(x: float, z: float, y0: float, y1: float, w: float) -> void:
		glow.box(Transform3D(Basis(), Vector3(x, (y0 + y1) / 2.0, z)), Vector3(w, y1 - y0, 0.8), Color(1, 1, 1))
	_prism(solid, 0, 0, 86, 74, 650, 10, 0.86, 0, 1.0)
	_prism(solid, -50, 6, 34, 52, 735, 6, 0.9, 45, 0.97)
	_prism(solid, 44, -4, 32, 48, 560, 6, 0.88, -25, 1.02)
	_prism(solid, 6, 40, 64, 26, 600, 5, 0.9, 0, 0.98)
	_prism(solid, 82, 12, 28, 30, 430, 5, 0.85, 30, 1.0)
	_prism(solid, -20, -38, 40, 24, 520, 5, 0.9, 0, 1.01)
	solid.cyl(Transform3D(Basis(), Vector3(14, 650, 0)), 15, 0, 380, 8, Color(1.04, 1.04, 1.04))
	solid.cyl(Transform3D(Basis(), Vector3(-52, 735 - 15, 6)), 7, 0, 170, 6, Color(1.04, 1.04, 1.04))
	strip.call(0, 37.5, 120, 560, 3)
	strip.call(-22, 37.5, 200, 600, 2)
	strip.call(-50, 32.5, 160, 680, 2.4)
	strip.call(44, 20.5, 90, 470, 2)
	strip.call(82, 27.5, 60, 380, 2)
	var flat := Basis(Vector3(1, 0, 0), PI / 2.0)
	_torus(solid, Transform3D(Basis(Vector3(1, 0, 0), 0.05) * Basis(Vector3(0, 0, 1), 0.07) * Basis.from_scale(Vector3(1, 2.2, 1)) * flat, Vector3(20, 430, 0)), 330, 6, 6, 180, 1.05)
	_torus(glow, Transform3D(Basis(Vector3(1, 0, 0), 0.05) * Basis(Vector3(0, 0, 1), 0.07) * flat, Vector3(20, 428, 0)), 323, 1.6, 4, 180, 1.0)
	_torus(glow, Transform3D(Basis(Vector3(0, 0, 1), -0.04) * flat, Vector3(0, 150, 0)), 130, 3.2, 6, 140, 1.0)
	_torus(solid, Transform3D(Basis(Vector3(0, 0, 1), 0.05) * flat, Vector3(10, 255, 0)), 95, 2.2, 6, 120, 1.03)
	for i in 46:
		var r := 105.0 + pow(rnd.next(), 0.75) * 560.0
		var a := rnd.next() * TAU
		var x := cos(a) * r * 1.25
		var z := sin(a) * r * 0.8
		var h: float = (390.0 * exp(-r / 250.0) + 45.0) * R.call(0.55, 1.15)
		var w: float = R.call(18.0, 46.0)
		var d: float = R.call(18.0, 46.0)
		_prism(solid, x, z, w, d, h, R.call(2.0, 8.0), R.call(0.8, 1.0), R.call(-10.0, 10.0) if rnd.next() < 0.3 else 0.0, R.call(0.92, 1.06))
		if rnd.next() < 0.35:
			var cr: float = R.call(2.0, 5.0)
			var chh: float = h * R.call(0.15, 0.35)
			solid.cyl(Transform3D(Basis(), Vector3(x, h + h * 0.12 - chh * 0.5, z)), cr, 0, chh, 6, Color(1.03, 1.03, 1.03))
		if rnd.next() < 0.4: strip.call(x, z + d / 2.0 + 0.3, h * 0.25, h * 0.85, 1.2)
	return {"solid": solid.build(), "glow": glow.build()}

# --- distant silhouette trees (distant.ts createDistantForest) --------------------------------------------------------
static func distant_conifer() -> ArrayMesh:
	var b := Bag.new()
	var dark := Color("1f3317").srgb_to_linear()
	var mid := Color("2c4420").srgb_to_linear()
	var trunk := Color("3b2f24").srgb_to_linear()
	b.cyl(Transform3D(Basis(), Vector3(0, 0, 0)), 0.32, 0.25, 2.2, 5, trunk)
	b.cyl(Transform3D(Basis(), Vector3(0, 4.0 - 2.6, 0)), 2.4, 0, 5.2, 7, dark)
	b.cyl(Transform3D(Basis(), Vector3(0, 6.8 - 2.2, 0)), 1.8, 0, 4.4, 7, dark)
	b.cyl(Transform3D(Basis(), Vector3(0, 9.3 - 1.8, 0)), 1.1, 0, 3.6, 7, mid)
	return b.build()

static func distant_broad() -> ArrayMesh:
	var b := Bag.new()
	var S := VHNoise.simplex(31337)
	var mid := Color("2c4420").srgb_to_linear()
	var trunk := Color("3b2f24").srgb_to_linear()
	b.cyl(Transform3D(Basis(), Vector3(0, 0, 0)), 0.4, 0.3, 3.0, 5, trunk)
	var blob := rock_blob(S)
	for i in range(0, blob.size(), 3):
		b.tri(blob[i] + Vector3(0, 5.6, 0), blob[i + 1] + Vector3(0, 5.6, 0), blob[i + 2] + Vector3(0, 5.6, 0), mid)
	return b.build()

## Noisy icosahedron (radius 3.2, detail 1) as a triangle list.
static func rock_blob(S: VHNoise) -> Array:
	var ico := icosphere(1)
	var v: Array = ico[0]
	var idx: PackedInt32Array = ico[1]
	var out: Array = []
	for t in range(0, idx.size(), 3):
		for k in [0, 2, 1]:
			var p: Vector3 = (v[idx[t + k]] as Vector3) * 3.2
			var kk := 1.0 + S.noise3(p.x * 0.6, p.y * 0.6, p.z * 0.6) * 0.25
			out.append(Vector3(p.x * kk, p.y * kk * 0.85, p.z * kk))
	return out
