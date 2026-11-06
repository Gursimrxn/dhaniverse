class_name TreeFoliage
extends RefCounted
## A whole tree as two meshes: its wood (TreeWood) and its leaves. The crown follows just-a-simple-tree's
## foliage.js (MIT, Mike Fernandez), after trungduyng's Blender anime-tree pipeline: leaf clusters scattered
## over each leaf clump, lit with the clump's normals, so a crown reads as a few soft volumes through the cel
## ramp (shaders/foliage). Each cluster's ambient occlusion is worked out here, and clusters buried deep and
## dark inside a neighbouring clump are left out. The leaves themselves are geometry, as on the Blender bank
## trees (dhaniverse-v2 foliage_library.blend): a star of diamond blades per cluster, each folded along its
## midrib, in one of two tones, so they stay crisp at any distance with no texture or alpha cut-out.
##
## Baked into one mesh per tree template, with what the shader needs per vertex:
##   NORMAL  the clump's normal there          CUSTOM3 xyz: the blade facet's own normal, w: 0 leaf, 1 or 2 a flower
##   COLOR   rgb: the clump's tint x the cluster's tone, a: the cluster's AO (light let in, 0..1)
##   CUSTOM0 xyz: the card's centre, w: its order through the season (who unfolds / turns / drops first)
##   CUSTOM1 xyz: the point on its twig it hangs from, w: the centre's height / tree height (wind bend)
##   CUSTOM2 xyz: where it sits in the crown, over the crown's half size (the shadow side), w: its swing, packed

const CARD_RATIO := 1.8         # card width / clump radius
const TILT := 0.6               # how far a card leans off its clump's surface, at most
const AO_RAYS := 8
const AO_NEIGHBOURS := 16
const NEIGHBOUR_FADE := 0.25
const LEAF_DENSITY := 1.1512925 # -ln(0.1) / 2: a ray straight through a clump keeps 10% of the light
const BURIED := 0.8
const HIDDEN := 0.1
const FADE_IN := 0.15
const SMALLEST_CARD := 0.005
const WARMTH := 0.45            # a clump's colours drift warmer/cooler and lighter/darker by these at variation 1
const LIGHTNESS := 0.35
const VARIATION := 0.25
const TONES := [0.84, 1.1]       # each cluster takes one of two tones (the Blender bank trees' two vertex colours)
const CUP := 0.22               # how far a blade's tip lifts off its clump, of its length


static var _ao_dirs: Array[Vector3] = []

## The lighter copy for farther away (the reference's lod.js, its second level): fewer sides round the wood
## and no twigs; a third of the cards, grown to cover for those left out, flat (one square each).
const LOD_SIDES := 0.5
const LOD_CARDS := 0.3

## Grow a tree from params (TreeSpecies.params_for) and bake its meshes: the wood, its twigs (only seen while
## the leaves unfold, thin or are gone; twigs_show), the leaf cards, and the lighter copies of wood and cards.
## -> {wood, twigs, leaves, low_wood, low_leaves: ArrayMesh, height, crown_radius, trunk_radius, flutter}
static func build(p: Dictionary) -> Dictionary:
	var g := TreeSpecies.grow_aged(p)
	var wood: TreeWood = g.wood
	var clumps: Array = g.clumps
	for c in clumps:
		if not c.has("swing"):
			var w: Dictionary = c.get("wood", {})
			c.swing = {"flex": minf(float(w.get("flex", 0.0)) / wood.most, 1.0), "phase": float(w.get("phase", 0.0))}
	var twigs := TreeWood.new(p, null)
	twigs.most = wood.most
	if not p.get("woodless", false): twigs.twigs(clumps, int(p.twigs))
	var height := 0.0
	for v in wood.pos: height = maxf(height, v.y)
	for v in twigs.pos: height = maxf(height, v.y)
	if wood.pos.is_empty():
		for c in clumps: height = maxf(height, c.position.y + c.radius)
	height = maxf(height, 0.1)
	var crown := 0.0
	for c in clumps: crown = maxf(crown, Vector2(c.position.x, c.position.z).length() + float(c.radius))
	# the lighter copy: the same tree grown again with fewer sides (same randoms, so the same shape)
	var lp := p.duplicate()
	lp.sides = maxi(3, roundi(int(p.sides) * LOD_SIDES))
	var low_wood: TreeWood = TreeSpecies.grow_aged(lp).wood
	var kept := maxi(1, roundi(int(p.cards_per_clump) * LOD_CARDS))
	lp.cards_per_clump = kept
	lp.card_size = float(p.card_size) * sqrt(float(p.cards_per_clump) / kept)
	return {"wood": wood.build(height), "twigs": twigs.build(height), "leaves": _cards(clumps, p, height, int(p.blades)),
		"low_wood": low_wood.build(height), "low_leaves": _cards(clumps, lp, height, maxi(3, int(p.blades) - 2)),
		"height": height, "crown_radius": crown, "trunk_radius": 0.0 if wood.pos.is_empty() else float(p.trunk_thickness),
		"flutter": p.flutter}

## build(), kept on disk (user://foliage_cache) so a tree grown once loads at once after: keyed by its
## settings and by the generators' own source, so changing either grows it afresh. Each version of the
## generators' source has its own folder; folders of older versions are swept on first use (they piled up to
## a gigabyte otherwise).
const CACHE_DIR := "user://foliage_cache/"
const MESHES := ["wood", "twigs", "leaves", "low_wood", "low_leaves"]
const SOURCES := ["res://scripts/foliage/tree_wood.gd", "res://scripts/foliage/tree_species.gd", "res://scripts/foliage/tree_foliage.gd"]
static var _source_key := ""

static func build_cached(p: Dictionary) -> Dictionary:
	if _source_key == "":
		for s in SOURCES: _source_key += FileAccess.get_md5(s)
		if _source_key.is_empty(): _source_key = "exported"   # no sources in an export: settings alone
		_sweep(_source_key.md5_text().substr(0, 12))
	var keys := p.keys()
	keys.sort()
	var desc := ""
	for k in keys: desc += "|%s=%s" % [k, p[k]]
	var dir := CACHE_DIR + _source_key.md5_text().substr(0, 12) + "/"
	var base := dir + desc.md5_text()
	var meta := ConfigFile.new()
	if meta.load(base + ".cfg") == OK:
		var t := {}
		for k in meta.get_section_keys("tree"): t[k] = meta.get_value("tree", k)
		var ok := true
		for m in MESHES:
			var r = ResourceLoader.load(base + "_" + m + ".res", "", ResourceLoader.CACHE_MODE_IGNORE)
			if r == null: ok = false; break
			t[m] = r
		if ok: return t
	var built := build(p)
	DirAccess.make_dir_recursive_absolute(dir)
	for m in MESHES: ResourceSaver.save(built[m], base + "_" + m + ".res")
	for k in built:
		if not built[k] is Mesh: meta.set_value("tree", k, built[k])
	meta.save(base + ".cfg")
	return built

## Remove cached trees grown by other versions of the generators (and the flat files of the old layout).
static func _sweep(keep: String) -> void:
	var d := DirAccess.open(CACHE_DIR)
	if d == null: return
	for f in d.get_files(): d.remove(f)
	for sub in d.get_directories():
		if sub == keep: continue
		var sd := DirAccess.open(CACHE_DIR + sub)
		if sd:
			for f in sd.get_files(): sd.remove(f)
		d.remove(sub)

## Whether twigs would be seen at a season: while leaves are still unfolding, or once the first have dropped.
static func twigs_show(season: float) -> bool:
	return season < 0.25 or season > 0.64

static func _cards(clumps: Array, p: Dictionary, height: float, blades: int) -> ArrayMesh:
	var blade_width: float = p.blade_width
	var flower_share: float = p.get("flower_share", 0.0)
	if _ao_dirs.is_empty():
		for i in AO_RAYS:
			var r := sqrt((i + 0.5) / AO_RAYS)
			var a := i * TreeWood.GOLDEN_ANGLE
			_ao_dirs.append(Vector3(r * cos(a), sqrt(1.0 - r * r), r * sin(a)))
	# the crown's box, for where a card sits in it
	var lo := Vector3.ONE * INF
	var hi := -Vector3.ONE * INF
	for c in clumps:
		lo = lo.min(c.position - Vector3.ONE * c.radius)
		hi = hi.max(c.position + Vector3.ONE * c.radius)
	var crown_c := (lo + hi) * 0.5
	var crown_s := ((hi - lo) * 0.5).max(Vector3.ONE * 1e-3)
	var reach: float = p.ao_distance
	var near := _nearest_clumps(clumps, reach)
	var mean := 0.0
	for c in clumps: mean += pow(float(c.get("full_radius", c.radius)), 2.0)
	mean /= maxf(clumps.size(), 1)
	var card_size: float = p.card_size
	var roundness: float = p.roundness

	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()

	for ci in clumps.size():
		var clump: Dictionary = clumps[ci]
		var cpos: Vector3 = clump.position
		var radius: float = clump.radius
		var flatten: float = clump.get("flatten", 1.0)
		var full: float = clump.get("full_radius", radius)
		var cards := maxi(1, roundi(float(p.cards_per_clump) * full * full / mean))
		var seed := int(p.seed) + ci * 7919
		var random := _rng(seed + 104729)
		var tilt_r := _rng(seed + 15485863)
		var order_r := _rng(seed + 32452843)
		var tint_r := _rng(seed + 49979687)
		var flower_r := _rng(seed + 86028121)   # which clusters bloom, and in which of two colours
		var turn := Basis.from_euler(Vector3(random.randf() * 6.28, random.randf() * 6.28, random.randf() * 6.28))
		var clump_order := order_r.randf()
		var light := 1.0 + (tint_r.randf() * 2.0 - 1.0) * LIGHTNESS * VARIATION
		var warm := (tint_r.randf() * 2.0 - 1.0) * WARMTH * VARIATION
		var tint := Color(light * (1.0 + warm), light, light * (1.0 - warm))
		var swing: Dictionary = clump.swing
		var packed := roundf(clampf(swing.flex, 0.0, 1.0) * 1023.0) * 1024.0 + roundf(fposmod(float(swing.phase) / TAU, 1.0) * 1023.0)
		var twigs: Array = clump.get("twigs", [])
		var foot: Vector3 = clump.get("foot", cpos)
		var nb: Array = near[ci]
		for i in cards:
			var y := 1.0 - 2.0 * (i + 0.5) / cards
			var ring := sqrt(1.0 - y * y)
			var ang := i * TreeWood.GOLDEN_ANGLE
			var dir := turn * Vector3(cos(ang) * ring, y, sin(ang) * ring)
			var pt := Vector3(dir.x, dir.y * flatten, dir.z) * (radius * (0.9 + random.randf() * 0.15)) + cpos
			var normal := Vector3(dir.x, dir.y / flatten, dir.z).normalized()
			var lean := (_random_dir(tilt_r) * (TILT * random.randf()) + normal).normalized()
			var size := CARD_RATIO * radius * (0.8 + random.randf() * 0.4)
			var twist := random.randf() * TAU
			var chance := lerpf(order_r.randf(), clump_order, 0.5)
			var burial := _buried(pt, nb)
			# AO: light let in along rays round the normal, through the neighbours in reach
			var blocking: Array = []
			for k in nb.size():
				var o: Dictionary = nb[k].clump
				var ray: Vector3 = o.position - pt
				if nb[k].weight > 0.0 and ray.dot(normal) > -float(o.bound) and ray.length() - float(o.bound) < reach: blocking.append(nb[k])
			var to_normal := _arc(normal)
			var open := 0.0
			for h in _ao_dirs:
				var rd := to_normal * h
				var through := 0.0
				for b in blocking:
					var o: Dictionary = b.clump
					through += b.weight * _chord(pt, rd, o.position, o.radius, reach, o.get("flatten", 1.0)) / float(o.radius)
				open += exp(-LEAF_DENSITY * through)
			open /= AO_RAYS
			var dark := 1.0 - smoothstep(HIDDEN, HIDDEN * (1.0 + FADE_IN), open)
			var shown := 1.0 - burial * dark
			var width := size * shown * card_size
			if width <= SMALLEST_CARD: continue
			var order := lerpf(chance, 1.0 - open, 0.6)   # the more open, the sooner it turns
			var hang := _nearest_on_twigs(pt, cpos, twigs) if not twigs.is_empty() else foot
			# the cluster's frame: its facing, and two axes in its plane turned by its twist
			var helper := Vector3.UP if absf(lean.y) < 0.99 else Vector3.RIGHT
			var across := helper.cross(lean).normalized()
			var along := lean.cross(across)
			var tangent := across * cos(twist) + along * sin(twist)
			var bitangent := lean.cross(tangent)
			var distance := pt.distance_to(cpos)
			var side := (pt - crown_c) / crown_s
			# two tones, a cluster in one or the other, as the Blender bank trees' leaves are
			var tone := TONES[0] if random.randf() < 0.5 else TONES[1]
			var cc := Color(tint.r * tone, tint.g * tone, tint.b * tone, open)
			# a flowering shrub's clusters bloom: round petals, a little smaller, in its first or second flower colour
			var bloom := 0.0
			if flower_r.randf() < flower_share: bloom = 1.0 if flower_r.randf() < 0.7 else 2.0
			var bw := 0.62 if bloom > 0.0 else blade_width
			var bs := 0.8 if bloom > 0.0 else 1.0
			# a star of diamond blades, each folded along its midrib (two facets), cupped out from the clump
			for b in blades:
				var a := TAU * b / blades + (random.randf() - 0.5) * 0.4
				var dv := tangent * cos(a) + bitangent * sin(a)
				var sv := lean.cross(dv)
				var l := width * 0.5 * (0.8 + random.randf() * 0.35) * bs
				var w := l * bw
				var fold := lean * l * 0.12                              # the midrib rises: a shallow V
				var cup := lean * l * CUP
				var corners := [pt, pt + dv * l * 0.42 + sv * w + cup * 0.4, pt + dv * l + cup + fold * 0.5, pt + dv * l * 0.42 - sv * w + cup * 0.4]
				for k in 4:
					var q: Vector3 = corners[k]
					corners[k] = q.lerp(cpos + (q - cpos).normalized() * distance, roundness * 0.5)
				for tri in [[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]]:
					var fn: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
					if fn.dot(normal) < 0.0: fn = -fn
					for v in tri:
						pos.append(v)
						nrm.append(normal)
						col.append(cc)
						c0.append_array([pt.x, pt.y, pt.z, order])
						c1.append_array([hang.x, hang.y, hang.z, pt.y / height])
						c2.append_array([side.x, side.y, side.z, packed])
						c3.append_array([fn.x, fn.y, fn.z, bloom])
	var m := ArrayMesh.new()
	if pos.is_empty(): return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_CUSTOM2] = c2
	arr[Mesh.ARRAY_CUSTOM3] = c3
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	return m

static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

static func _random_dir(r: RandomNumberGenerator) -> Vector3:
	var y := r.randf() * 2.0 - 1.0
	var a := r.randf() * TAU
	var ring := sqrt(1.0 - y * y)
	return Vector3(ring * cos(a), y, ring * sin(a))

## The rotation taking +Y to n.
static func _arc(n: Vector3) -> Basis:
	if n.y < -0.9999: return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, n))

## Each clump's nearest neighbours that could shade its cards: within reach by the gap between surfaces, at
## most AO_NEIGHBOURS, each weighted down as it nears being left out, so nothing pops in or out at once.
static func _nearest_clumps(clumps: Array, reach: float) -> Array:
	for c in clumps: c.bound = float(c.radius) * maxf(float(c.get("flatten", 1.0)), 1.0)
	var lists: Array = []
	for i in clumps.size():
		var found: Array = []
		var ci: Dictionary = clumps[i]
		for j in clumps.size():
			if j == i: continue
			var o: Dictionary = clumps[j]
			var gap: float = (o.position as Vector3).distance_to(ci.position) - float(ci.radius) - float(o.radius)
			if gap < float(ci.radius) * 0.05 + reach: found.append([gap, o])
		found.sort_custom(func(a, b): return a[0] < b[0])
		var out := float(ci.radius) * 0.05 + reach
		if found.size() > AO_NEIGHBOURS: out = minf(out, found[AO_NEIGHBOURS][0])
		var list: Array = []
		for k in mini(found.size(), AO_NEIGHBOURS):
			list.append({"clump": found[k][1], "weight": clampf((out - float(found[k][0])) / (reach * NEIGHBOUR_FADE), 0.0, 1.0)})
		lists.append(list)
	return lists

## How buried a point is in its clump's neighbours, 0..1, easing out towards BURIED of their radius.
static func _buried(pt: Vector3, nb: Array) -> float:
	var most := 0.0
	for b in nb:
		var o: Dictionary = b.clump
		var d := pt - (o.position as Vector3)
		d.y /= float(o.get("flatten", 1.0))
		var depth := d.length() / (BURIED * float(o.radius))
		most = maxf(most, float(b.weight) * (1.0 - smoothstep(1.0 - FADE_IN, 1.0, depth)))
	return most

## How far a ray from `origin` along `dir`, out to `reach`, runs inside a clump squashed upright by flatten.
static func _chord(origin: Vector3, dir: Vector3, center: Vector3, radius: float, reach: float, flatten: float) -> float:
	var x := center.x - origin.x
	var y := (center.y - origin.y) / flatten
	var z := center.z - origin.z
	var dy := dir.y / flatten
	var a := dir.x * dir.x + dy * dy + dir.z * dir.z
	var b := x * dir.x + y * dy + z * dir.z
	var c := x * x + y * y + z * z - radius * radius
	var disc := b * b - a * c
	if disc <= 0.0: return 0.0
	var half := sqrt(disc)
	return maxf(minf((b + half) / a, reach) - maxf((b - half) / a, 0.0), 0.0)

## The nearest point to `pt` on a clump's twigs (each a line through its kinks); its centre if nearer.
static func _nearest_on_twigs(pt: Vector3, center: Vector3, twigs: Array) -> Vector3:
	var best := pt.distance_squared_to(center)
	var out := center
	for kinks in twigs:
		for k in range(1, kinks.size()):
			var q := Geometry3D.get_closest_point_to_segment(pt, kinks[k - 1], kinks[k])
			var d := pt.distance_squared_to(q)
			if d < best:
				best = d
				out = q
	return out
