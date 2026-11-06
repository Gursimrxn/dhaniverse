class_name ValleyTrees
extends RefCounted
## The valley's trees, as just-a-simple-tree grows and dresses them (foliage.js, wind.js; MIT, Mike Fernandez):
## the wood and leaf clumps of its oak, pine, cypress and bush (TreeSpecies / TreeWood, the game's port), at any
## age, and its own leaves: flat cards lying on each clump, cut by a painted atlas ("round cluster" for the oak and
## bush, "willow leaves" for the pine and cypress, as the page sets them), wrapped round the clump by roundness.
## Every card carries what the page's shader reads (shaders/valley/leaf_cards.gdshader):
##   CUSTOM0 xyz: the card's centre, w: its order through the year (who unfolds, turns and drops first)
##   CUSTOM1 xyz: the clump's centre (where a young card sits close in), w: the clump's swing, packed (wind.js)
##   COLOR   rgb: where the card sits in the crown (-1..1 as 0..1), a: its height over the tree's (the sway's bend)

## kind -> species, how many shapes, knob ranges (an age range among them), and the page's card settings
const KINDS := {
	"oak": {"species": "oak", "variants": 4, "vary": {"tree_age": [0.45, 1.0], "size": [4.6, 6.4],
		"main_limbs": [3, 6], "branches": [3, 5], "spread": [0.8, 1.2], "crookedness": [0.25, 0.75], "split_height": [0.25, 0.5],
		"trunk_height": [0.0, 0.8], "clump_size": [0.85, 1.2]}, "cards": [35, 0.92, 0.58], "atlas": "round"},
	"young": {"species": "oak", "variants": 3, "vary": {"tree_age": [0.15, 0.4], "size": [3.5, 4.6],
		"main_limbs": [3, 4], "spread": [0.7, 1.0], "crookedness": [0.2, 0.4], "trunk_height": [0.2, 0.8]}, "cards": [35, 0.92, 0.58], "atlas": "round"},
	"pine": {"species": "pine", "variants": 8, "vary": {"tree_age": [0.2, 1.0], "size": [4.2, 8.5], "whorls": [6, 12],
		"whorl_branches": [4, 8], "droop": [-1.0, -0.15], "crookedness": [0.2, 0.65], "slenderness": [0.8, 1.25], "clump_size": [1.05, 1.4]},
		"cards": [13, 0.8, 0.0], "atlas": "willow"},
	"cypress": {"species": "cypress", "variants": 3, "vary": {"tree_age": [0.4, 1.0], "size": [4.5, 6.8],
		"slenderness": [0.8, 1.3], "trunk_height": [0.3, 1.2], "cypress_branches": [16, 26]}, "cards": [35, 0.46, 0.0], "atlas": "willow"},
	"bush": {"species": "bush", "variants": 4, "vary": {"size": [1.8, 3.2], "bush_clumps": [3, 9], "spread": [0.6, 1.1]},
		"cards": [35, 0.92, 0.58], "atlas": "round"},
}
const CARD_RATIO := 1.8        # card width / clump radius (foliage.js)
const TILT := 0.6              # how far a card leans off its clump's surface, at most
const LOD_SIDES := 0.5         # lod.js: the lighter copy's sides round the wood / the tree's
const LOD_CARDS := 0.3         # and its cards / the tree's

## Variant v of a kind -> {wood, leaves, low_wood, low_leaves: ArrayMesh, atlas, height, crown_radius}
static func build(kind: String, v: int) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + v * 7919 + kind.length() * 131
	var set := {"seed": int(r.seed % 9973)}
	for knob in k.vary:
		var range_: Array = k.vary[knob]
		set[knob] = r.randi_range(range_[0], range_[1]) if range_[0] is int else r.randf_range(range_[0], range_[1])
	var p := TreeSpecies.params_for(k.species, set)
	var g := TreeSpecies.grow_aged(p)
	var wood: TreeWood = g.wood
	for c in g.clumps:      # each clump swings with the branch it grew on (TreeFoliage.build)
		if not c.has("swing"):
			var w: Dictionary = c.get("wood", {})
			c.swing = {"flex": minf(float(w.get("flex", 0.0)) / maxf(wood.most, 1e-4), 1.0), "phase": float(w.get("phase", 0.0))}
	var height := 0.1
	for v3 in wood.pos: height = maxf(height, v3.y)
	for c in g.clumps: height = maxf(height, c.position.y + c.radius)
	var crown := 0.0
	for c in g.clumps: crown = maxf(crown, Vector2(c.position.x, c.position.z).length() + float(c.radius))
	var cards: Array = k.cards
	# the lighter copy for farther off (lod.js, its second level): the same tree grown again with half the sides
	# round the wood (same randoms, so the same shape), a third of the cards grown to cover for those left out
	var lp := p.duplicate()
	lp.sides = maxi(3, roundi(int(p.sides) * LOD_SIDES))
	var low_wood: TreeWood = TreeSpecies.grow_aged(lp).wood
	var kept := maxi(1, roundi(int(cards[0]) * LOD_CARDS))
	return {"wood": wood.build(height), "leaves": _cards(g.clumps, int(p.seed), height, crown, cards[0], cards[1], cards[2]),
		"low_wood": low_wood.build(height), "low_leaves": _cards(g.clumps, int(p.seed), height, crown, kept, cards[1] * sqrt(float(cards[0]) / kept), cards[2]),
		"atlas": k.atlas, "height": height, "crown_radius": crown}

## One flat card per point over each clump, cut 2 x 2 so roundness can wrap it round the clump (one square when flat)
## (foliage.js: flat = centre + the card's axes, wrapped = the clump's centre + the same direction at the
## card's own distance, mixed by roundness). UV picks one of the atlas's four cells.
static func _cards(clumps: Array, seed: int, height: float, crown: float, per_clump: int, card_size: float, roundness: float) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	var mean := 0.0
	for c in clumps: mean += pow(float(c.get("full_radius", c.radius)), 2.0)
	mean /= maxf(clumps.size(), 1)
	var mid := Vector3(0.0, height * 0.6, 0.0)
	var g := 2 if roundness > 0.0 else 1     # squares a card is cut into: they only show once roundness bends it
	for ci in clumps.size():
		var c: Dictionary = clumps[ci]
		var cpos: Vector3 = c.position
		var radius: float = c.radius
		var flatten: float = c.get("flatten", 1.0)
		var full: float = c.get("full_radius", radius)
		var n := maxi(1, roundi(per_clump * full * full / mean))
		var rr := RandomNumberGenerator.new()
		rr.seed = seed + ci * 7919
		var turn := Basis.from_euler(Vector3(rr.randf() * TAU, rr.randf() * TAU, rr.randf() * TAU))
		var clump_order := rr.randf()
		var swing: Dictionary = c.swing
		var packed := roundf(clampf(swing.flex, 0.0, 1.0) * 1023.0) * 1024.0 + roundf(fposmod(float(swing.phase) / TAU, 1.0) * 1023.0)
		for i in n:
			var y := 1.0 - 2.0 * (i + 0.5) / n
			var ring := sqrt(1.0 - y * y)
			var ang := i * TreeWood.GOLDEN_ANGLE
			var dir := turn * Vector3(cos(ang) * ring, y, sin(ang) * ring)
			var centre: Vector3 = cpos + Vector3(dir.x, dir.y * flatten, dir.z) * (radius * (0.9 + rr.randf() * 0.15))
			var normal := Vector3(dir.x, dir.y / flatten, dir.z).normalized()
			var rd := Vector3(rr.randf() * 2.0 - 1.0, rr.randf() * 2.0 - 1.0, rr.randf() * 2.0 - 1.0).normalized()
			var facing := (rd * (TILT * rr.randf()) + normal).normalized()
			var size := CARD_RATIO * radius * (0.8 + rr.randf() * 0.4) * card_size
			var helper := Vector3.RIGHT if absf(facing.y) < 0.92 else Vector3.UP
			var across := helper.cross(facing).normalized()
			var along := facing.cross(across)
			var spin := rr.randf() * TAU
			var tangent := across * cos(spin) + along * sin(spin)
			var bitangent := facing.cross(tangent)
			var cell := rr.randi() % 4
			var order := lerpf(rr.randf(), clump_order, 0.5)
			var reach := (centre - cpos).length()
			var sp := (centre - mid) / maxf(crown, 0.01)
			var tag := Color(clampf(sp.x * 0.5 + 0.5, 0.0, 1.0), clampf(sp.y * 0.5 + 0.5, 0.0, 1.0), clampf(sp.z * 0.5 + 0.5, 0.0, 1.0), clampf(centre.y / height, 0.0, 1.0))
			var base := pos.size()
			for j in g + 1:
				for i2 in g + 1:
					var u := float(i2) / g - 0.5
					var w := float(j) / g - 0.5
					var flat: Vector3 = centre + (tangent * u + bitangent * w) * size
					var wrapped: Vector3 = cpos + (flat - cpos).normalized() * reach
					pos.append(flat.lerp(wrapped, roundness))
					nrm.append(facing.lerp((wrapped - cpos).normalized(), roundness).normalized())
					uv.append(Vector2((cell % 2) * 0.5 + (u + 0.5) * 0.5, (cell / 2) * 0.5 + (w + 0.5) * 0.5))
					col.append(tag)
					c0.append_array(PackedFloat32Array([centre.x, centre.y, centre.z, order]))
					c1.append_array(PackedFloat32Array([cpos.x, cpos.y, cpos.z, packed]))
			for j in g:
				for i2 in g:
					var a0 := base + j * (g + 1) + i2
					idx.append_array(PackedInt32Array([a0, a0 + 1, a0 + g + 1, a0 + 1, a0 + g + 2, a0 + g + 1]))
	var m := ArrayMesh.new()
	if pos.is_empty(): return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	m.custom_aabb = AABB(Vector3(-14, -1, -14), Vector3(28, 30, 28))
	return m

# --- the page's painted atlases (foliage.js paintAtlas / cluster, seed 42), 2 x 2 cells of 256 px, white on black ----
static var _atlases := {}

## "round": thirty small round leaves a cell, any way turned; "willow": eighteen long narrow leaves, all lying
## within 0.35 rad of the x axis.
static func atlas(name: String) -> ImageTexture:
	if _atlases.has(name): return _atlases[name]
	var img := Image.create(512, 512, true, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	var rnd := _Mulberry.new(42)
	var willow := name == "willow"
	var count := 18 if willow else 30
	var small := 40.0 if willow else 12.0
	var large := 58.0 if willow else 18.0
	for v in 4:
		var ox := (v % 2) * 256 + 128
		var oy := (v / 2) * 256 + 128
		for i in count:
			var d := sqrt(rnd.next()) * (118.0 - large)
			var t := rnd.next() * TAU
			var rot := (rnd.next() - 0.5) * 0.7 if willow else rnd.next() * TAU
			var length := small + rnd.next() * (large - small)
			var cx := ox + cos(t) * d
			var cy := oy + sin(t) * d
			var cr := cos(rot)
			var sr := sin(rot)
			for py in range(int(cy - length) - 1, int(cy + length) + 2):
				for px in range(int(cx - length) - 1, int(cx + length) + 2):
					if px < 0 or py < 0 or px >= 512 or py >= 512: continue
					var lx := (px + 0.5 - cx) * cr + (py + 0.5 - cy) * sr
					var ly := -(px + 0.5 - cx) * sr + (py + 0.5 - cy) * cr
					if _inside(lx / length, ly / length, willow): img.set_pixel(px, py, Color.WHITE)
	img.generate_mipmaps()
	_atlases[name] = ImageTexture.create_from_image(img)
	return _atlases[name]

## Inside a leaf of length 2 along x (from -1 to 1): round = an ellipse 0.7 wide; willow = two quadratic curves
## from the base through (-0.2, +-0.26) to the tip.
static func _inside(x: float, y: float, willow: bool) -> bool:
	if not willow: return x * x + (y / 0.7) * (y / 0.7) <= 1.0
	if x <= -1.0 or x >= 1.0: return false
	var t := (-1.6 + sqrt(2.56 + 1.6 * (1.0 + x))) / 0.8
	return absf(y) <= 2.0 * (1.0 - t) * t * 0.26

## mulberry32, the generator foliage.js paints with
class _Mulberry:
	var a: int
	func _init(seed: int) -> void:
		a = seed & 0xFFFFFFFF
	func next() -> float:
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t := a
		t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
		t = t ^ ((t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF)
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
