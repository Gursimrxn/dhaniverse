class_name TreeBuilder
extends RefCounted
## Procedural stylized trees: tapered branching trunks + clouds of leaf cards
## (expanded to face the camera in leaves.gdshader). Deterministic per seed.

const SIDES := 7

static func build(species: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cards: Array = []     # [centre, normal, depth, size]
	match species:
		"broad": _broad(rng, bark, cards, 1.0)
		"blossom": _broad(rng, bark, cards, 0.62)
		"pine": _pine(rng, bark, cards)
		"willow": _willow(rng, bark, cards)
		"bush", "flower_bush": _bush(rng, cards)
	bark.generate_normals()
	return {"bark": bark.commit(), "leaves": _cards_mesh(cards, rng, species == "blossom" or species == "flower_bush", 0.85 if species == "blossom" else 0.35)}

# --- trunks -------------------------------------------------------------------
static func _tube(st: SurfaceTool, pts: Array, radii: Array, ground_y := 0.0) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.FORWARD if absf(dir.y) > 0.9 else Vector3.UP).normalized()
		var up := side.cross(dir).normalized()
		for k in SIDES:
			var t0 := TAU * k / SIDES
			var t1 := TAU * (k + 1) / SIDES
			var o0 := side * cos(t0) + up * sin(t0)
			var o1 := side * cos(t1) + up * sin(t1)
			var ra: float = radii[i]
			var rb: float = radii[i + 1]
			var v := [a + o0 * ra, a + o1 * ra, b + o1 * rb, b + o0 * rb]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(float(i) / pts.size(), ground_y, 0, 1))
				st.add_vertex(v[idx])

static func _limb(rng: RandomNumberGenerator, start: Vector3, dir: Vector3, length: float, r0: float, segs := 4, droop := 0.0) -> Array:
	var pts := [start]
	var radii := [r0]
	var p := start
	var d := dir.normalized()
	for i in segs:
		d = (d + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.1, 0.2) - droop, rng.randf_range(-0.25, 0.25))).normalized()
		p += d * length / segs
		pts.append(p)
		radii.append(r0 * (1.0 - float(i + 1) / (segs + 1.5)))
	return [pts, radii]

static func _clump(rng: RandomNumberGenerator, cards: Array, centre: Vector3, radius: float, count: int, crown_centre: Vector3, size: float) -> void:
	for i in count:
		# biased towards the surface so the silhouette stays lumpy, not a ball
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var r := radius * pow(rng.randf(), 0.35)
		var pos := centre + dir * r
		var n := ((pos - crown_centre).normalized() * 0.6 + dir * 0.4).normalized()
		cards.append([pos, n, r / radius, size * rng.randf_range(0.75, 1.25)])

# --- species --------------------------------------------------------------------
static func _broad(rng: RandomNumberGenerator, st: SurfaceTool, cards: Array, scale: float) -> void:
	var trunk_h := rng.randf_range(2.6, 3.6) * scale
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 1, rng.randf_range(-0.25, 0.25))
	var t := _limb(rng, Vector3.ZERO, lean, trunk_h, 0.34 * scale, 3)
	# root flare
	t[1][0] *= 1.5
	_tube(st, t[0], t[1])
	var top: Vector3 = t[0][-1]
	var crown_c := top + Vector3(0, 2.2 * scale, 0)
	var n_limbs := rng.randi_range(3, 5)
	for i in n_limbs:
		var ang := TAU * i / n_limbs + rng.randf_range(-0.4, 0.4)
		var d := Vector3(cos(ang), rng.randf_range(0.6, 1.3), sin(ang))
		var limb := _limb(rng, top, d, rng.randf_range(2.0, 3.4) * scale, 0.2 * scale, 3)
		_tube(st, limb[0], limb[1])
		var tip: Vector3 = limb[0][-1]
		_clump(rng, cards, tip + Vector3(0, 0.4, 0), rng.randf_range(1.5, 2.2) * scale, int(110 * scale), crown_c, 0.95 * scale)
	# a top clump closes the crown but keeps gaps between the limb clumps
	_clump(rng, cards, crown_c + Vector3(0, 1.0 * scale, 0), 2.0 * scale, int(90 * scale), crown_c, 1.0 * scale)

static func _pine(rng: RandomNumberGenerator, st: SurfaceTool, cards: Array) -> void:
	var h := rng.randf_range(8.0, 12.5)
	var t := _limb(rng, Vector3.ZERO, Vector3(rng.randf_range(-0.06, 0.06), 1, rng.randf_range(-0.06, 0.06)), h, 0.3, 5)
	t[1][0] *= 1.4
	_tube(st, t[0], t[1])
	var tiers := rng.randi_range(5, 7)
	var crown_c := Vector3(0, h * 0.55, 0)
	for i in tiers:
		var f := float(i) / tiers
		var y := lerpf(h * 0.28, h * 0.95, f)
		var rad := lerpf(2.6, 0.5, f) * rng.randf_range(0.85, 1.15)
		var arms := int(lerpf(7, 3, f))
		for k in arms:
			var ang := TAU * k / arms + rng.randf() * 0.8 + i
			# drooping fan: cards along a short arm that sags at the tip
			for j in 4:
				var u := float(j + 1) / 4.0
				var p := Vector3(cos(ang) * rad * u, y - u * u * 0.9, sin(ang) * rad * u)
				var n := (Vector3(cos(ang), 0.5, sin(ang)) + (p - crown_c).normalized() * 0.3).normalized()
				cards.append([p + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), n, 0.4 + u * 0.6, rng.randf_range(0.7, 1.0)])
	cards.append([Vector3(0, h + 0.2, 0), Vector3.UP, 1.0, 0.6])

static func _willow(rng: RandomNumberGenerator, st: SurfaceTool, cards: Array) -> void:
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 1, rng.randf_range(-0.5, 0.5))
	var t := _limb(rng, Vector3.ZERO, lean, rng.randf_range(3.0, 4.0), 0.32, 3)
	t[1][0] *= 1.5
	_tube(st, t[0], t[1])
	var top: Vector3 = t[0][-1]
	var crown_c := top + Vector3(0, 1.0, 0)
	for i in 9:
		var ang := TAU * i / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(ang), 0, sin(ang))
		var reach := rng.randf_range(1.8, 3.2)
		var start := top + out * reach * 0.5 + Vector3(0, rng.randf_range(0.6, 1.4), 0)
		# hanging curtain strands
		for j in 10:
			var u := float(j) / 9.0
			var p := start + out * reach * 0.5 * (1.0 + u * 0.3) - Vector3(0, u * u * 3.2, 0)
			cards.append([p, (p - crown_c).normalized(), 0.5 + 0.5 * (1.0 - u), rng.randf_range(0.55, 0.8)])
	_clump(rng, cards, crown_c + Vector3(0, 0.6, 0), 2.0, 40, crown_c, 0.9)

static func _bush(rng: RandomNumberGenerator, cards: Array) -> void:
	var c := Vector3(0, 0.55, 0)
	for i in rng.randi_range(2, 3):
		var o := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.3, 0.7), rng.randf_range(-0.6, 0.6))
		_clump(rng, cards, o, rng.randf_range(0.6, 0.9), 16, c, 0.55)

# --- leaf card mesh ---------------------------------------------------------------
static func _cards_mesh(cards: Array, rng: RandomNumberGenerator, blossom: bool, bloom_chance := 0.85) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for c in cards:
		var base := verts.size()
		var col := Color(c[2], rng.randf(), c[3], 1.0 if (blossom and rng.randf() < bloom_chance) else 0.0)
		for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(c[0]); norms.append(c[1]); uvs.append(uv); cols.append(col)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# cards are expanded in the shader: grow bounds so culling doesn't pop them
	m.custom_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 16, 12))
	return m

## Distant LOD for billboard-card foliage: keeps one card in `keep` (cards = triangles joined by
## shared vertices, so it works whatever order the importer left them in). The far material
## enlarges the survivors so the crown keeps its mass.
static func thin_cards(mesh: Mesh, keep: int) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array(range(nv))
		var parent := PackedInt32Array(range(nv))
		for t in range(0, idx.size(), 3):
			for k in [1, 2]:
				var a := _root(parent, idx[t])
				var b := _root(parent, idx[t + k])
				if a != b: parent[b] = a
		var cards := {}                  # root vertex -> triangle starts (Arrays: packed arrays copy on write)
		for t in range(0, idx.size(), 3):
			cards.get_or_add(_root(parent, idx[t]), []).append(t)
		var kept := PackedInt32Array()
		var i := 0
		for r in cards:
			if i % keep == 0:
				for t in cards[r]: kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
			i += 1
		arr[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.custom_aabb = mesh.get_aabb().grow(3.0)
	return out

static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
