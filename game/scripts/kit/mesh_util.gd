class_name MeshUtil
extends RefCounted
## Procedural mesh builder for the architecture kit.
## Primitives are appended into one SurfaceTool per material key ("solid", "cloth",
## "leaf", "glow", "glass") so a finished piece is ONE ArrayMesh with one surface per
## material = one draw call per material. Colour lives in vertex colour (stored
## linear), UV.x carries the sway weight read by kit.gdshader.
##
## Every primitive takes a local Transform3D `t`; `base` is applied on top so
## sub-assemblies (a stall inside a market hall) can be merged into the parent mesh.

static var _mats: Dictionary = {}

var base := Transform3D.IDENTITY
var sway := 0.0                 # constant sway weight for new vertices
var sway_fn := Callable()       # optional f(p_local: Vector3) -> float, overrides `sway`
var colliders: Array = []       # [Transform3D, Vector3 size]

var _st: Dictionary = {}
var _tris: Dictionary = {}
var _t := Transform3D.IDENTITY  # current primitive: local transform
var _full := Transform3D.IDENTITY
var _nb := Basis.IDENTITY       # normal matrix


static func xf(pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scl), pos)


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial = ShaderMaterial.new()
	if key == "glass":
		m.shader = load("res://shaders/glass.gdshader")
		m.set_shader_parameter("tint", Color(0.3, 0.46, 0.55))
	else:
		m.shader = load("res://shaders/kit.gdshader")
		match key:
			"cloth": m.set_shader_parameter("sway", 0.07); m.set_shader_parameter("grain", 0.03)
			"leaf": m.set_shader_parameter("sway", 0.05); m.set_shader_parameter("grain", 0.1)
			"glow": m.set_shader_parameter("emissive", 1.4); m.set_shader_parameter("grain", 0.0)
	_mats[key] = m
	return m


# --- low level --------------------------------------------------------------------
func _begin(t: Transform3D) -> void:
	_t = t
	_full = base * t
	_nb = _full.basis.inverse().transposed()


func _surf(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
		_tris[key] = 0
	return _st[key]


func _w(q: Vector3) -> float:
	return clampf(sway_fn.call(_t * q), 0.0, 1.0) if sway_fn.is_valid() else sway


## One triangle in primitive-local coords with per-vertex normals. Winding is
## fixed automatically so the front face looks along the normals (Godot = CW).
func _tri(key: String, q0: Vector3, q1: Vector3, q2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, col: Color) -> void:
	var st := _surf(key)
	var p0 := _full * q0
	var p1 := _full * q1
	var p2 := _full * q2
	var m0 := (_nb * n0).normalized()
	var m1 := (_nb * n1).normalized()
	var m2 := (_nb * n2).normalized()
	var w0 := _w(q0)
	var w1 := _w(q1)
	var w2 := _w(q2)
	if (p1 - p0).cross(p2 - p0).dot(m0 + m1 + m2) > 0.0:
		var tp := p1; p1 = p2; p2 = tp
		var tn := m1; m1 = m2; m2 = tn
		var tw := w1; w1 = w2; w2 = tw
	var c := col.srgb_to_linear()
	st.set_color(c)
	st.set_normal(m0); st.set_uv(Vector2(w0, 0)); st.add_vertex(p0)
	st.set_normal(m1); st.set_uv(Vector2(w1, 0)); st.add_vertex(p1)
	st.set_normal(m2); st.set_uv(Vector2(w2, 0)); st.add_vertex(p2)
	_tris[key] += 1


## Flat convex polygon (fan) facing `n`, in primitive-local coords.
func _poly(key: String, pts: Array, n: Vector3, col: Color) -> void:
	for i in range(1, pts.size() - 1):
		_tri(key, pts[0], pts[i], pts[i + 1], n, n, n, col)


# --- public primitives ------------------------------------------------------------
## Flat polygon in local coords of `t`.
func face(key: String, t: Transform3D, pts: Array, n: Vector3, col: Color) -> void:
	_begin(t)
	_poly(key, pts, n, col)


## Box centred on t.origin. bevel > 0 chamfers every edge (44 tris instead of 12).
func box(key: String, t: Transform3D, size: Vector3, col: Color, bevel := 0.0) -> void:
	_begin(t)
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var e := h - Vector3.ONE * b
	for a in 3:
		for sg in [-1.0, 1.0]:
			var a1 := (a + 1) % 3
			var a2 := (a + 2) % 3
			var pts := []
			for uv in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
				var p := Vector3()
				p[a] = h[a] * sg
				p[a1] = e[a1] * uv.x
				p[a2] = e[a2] * uv.y
				pts.append(p)
			var n := Vector3()
			n[a] = sg
			_poly(key, pts, n, col)
	if b <= 0.0:
		return
	for a3 in 3:   # edges parallel to axis a3
		var a1 := (a3 + 1) % 3
		var a2 := (a3 + 2) % 3
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var pts := []
				for k in [[1, 0, 1.0], [1, 0, -1.0], [0, 1, -1.0], [0, 1, 1.0]]:
					var p := Vector3()
					p[a1] = (h[a1] if k[0] == 1 else e[a1]) * s1
					p[a2] = (h[a2] if k[1] == 1 else e[a2]) * s2
					p[a3] = e[a3] * k[2]
					pts.append(p)
				var n := Vector3()
				n[a1] = s1
				n[a2] = s2
				_poly(key, pts, n.normalized(), col)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				_poly(key, [Vector3(h.x, e.y, e.z) * s, Vector3(e.x, h.y, e.z) * s, Vector3(e.x, e.y, h.z) * s], s.normalized(), col)


## Cylinder/cone standing on t.origin along +Y. Smooth sides unless flat.
func cyl(key: String, t: Transform3D, r0: float, r1: float, h: float, sides: int, col: Color, caps := true, flat := false) -> void:
	_begin(t)
	var slope := (r0 - r1) / h
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		if flat:
			n0 = ((d0 + d1) * 0.5 + Vector3(0, slope, 0)).normalized()
			n1 = n0
		var b0 := d0 * r0
		var b1 := d1 * r0
		var t0 := d0 * r1 + Vector3(0, h, 0)
		var t1 := d1 * r1 + Vector3(0, h, 0)
		_tri(key, b0, b1, t1, n0, n1, n1, col)
		if r1 > 0.0001:
			_tri(key, b0, t1, t0, n0, n1, n0, col)
		if caps:
			if r1 > 0.0001:
				_tri(key, Vector3(0, h, 0), t0, t1, Vector3.UP, Vector3.UP, Vector3.UP, col)
			_tri(key, Vector3.ZERO, b1, b0, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, col)


## Cylinder between two local points (rails, ropes, braces).
func segment(key: String, a: Vector3, b: Vector3, r: float, col: Color, sides := 4, t := Transform3D.IDENTITY) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var y := d / l
	var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	cyl(key, t * Transform3D(Basis(x, y, z), a), r, r, l, sides, col, false, sides <= 4)


## UV sphere centred on t.origin (scale t for ellipsoids).
func sphere(key: String, t: Transform3D, r: float, col: Color, segs := 6, rings := 4) -> void:
	_begin(t)
	var pts := []
	for j in rings + 1:
		var v := PI * j / rings
		var row := []
		for i in segs + 1:
			var u := TAU * i / segs
			row.append(Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u)))
		pts.append(row)
	for j in rings:
		for i in segs:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			if j > 0:
				_tri(key, a * r, b * r, c * r, a, b, c, col)
			if j < rings - 1:
				_tri(key, a * r, c * r, d * r, a, c, d, col)


## Triangular prism: base width w on y=0 (centred on x), apex at y=h, depth d along z.
func prism(key: String, t: Transform3D, w: float, h: float, d: float, col: Color) -> void:
	_begin(t)
	var z := d * 0.5
	var l := Vector3(-w * 0.5, 0, 0)
	var r := Vector3(w * 0.5, 0, 0)
	var top := Vector3(0, h, 0)
	var zf := Vector3(0, 0, z)
	_poly(key, [l + zf, r + zf, top + zf], Vector3.BACK, col)
	_poly(key, [l - zf, r - zf, top - zf], Vector3.FORWARD, col)
	var nl := Vector3(-h, w * 0.5, 0).normalized()
	var nr := Vector3(h, w * 0.5, 0).normalized()
	_poly(key, [l + zf, top + zf, top - zf, l - zf], nl, col)
	_poly(key, [r + zf, top + zf, top - zf, r - zf], nr, col)
	_poly(key, [l + zf, r + zf, r - zf, l - zf], Vector3.DOWN, col)


## Simple box collider (local transform, rotation allowed, no scale).
func collider(t: Transform3D, size: Vector3) -> void:
	colliders.append([base * t, size])


func tri_count() -> int:
	var n := 0
	for k in _tris:
		n += _tris[k]
	return n


## Bake everything into a Node3D: one MeshInstance3D (one surface per material) +
## one StaticBody3D with box shapes.
func to_node(node_name := "Piece") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var mesh := ArrayMesh.new()
	for key in _st:
		var st: SurfaceTool = _st[key]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, MeshUtil.mat(key))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	root.add_child(mi)
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		for c in colliders:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = c[1]
			cs.shape = shape
			cs.transform = c[0]
			body.add_child(cs)
		root.add_child(body)
	root.set_meta("tris", tri_count())
	return root
