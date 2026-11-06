class_name TreeSpecies
extends RefCounted
## How each species grows its wood and leaf clumps, and how a tree's age reshapes it. Ported from
## just-a-simple-tree's oak.js, pine.js, cypress.js, bush.js and tree-age.js (MIT, Mike Fernandez).
## grow(params) -> {wood: TreeWood, clumps: [{position, radius, flatten?, birth, wood?, foot?}]}

const MATURE := 0.6             # the age at which a tree is exactly as its settings grow it

## The page's starting settings, which every species starts from (the oak's), and each species' own.
const BASE := {
	"seed": 8263, "tree_age": MATURE, "size": 4.87, "trunk_thickness": 0.21, "base_flare": 1.69, "trunk_height": 0.0,
	"split_height": 0.41, "split_scatter": 0.0, "main_limbs": 3, "levels": 1, "branches": 5, "whorls": 9,
	"whorl_branches": 6, "droop": -1.0, "slenderness": 1.0, "cypress_branches": 20, "bush_clumps": 1,
	"spread": 0.89, "crookedness": 0.34, "sides": 10, "smoothness": 1, "twigs": 5, "variety": 1.0,
	"cards_per_clump": 136, "card_size": 0.27, "roundness": 0.58, "clump_size": 1.0, "ao_distance": 2.5,
	"blades": 5, "blade_width": 0.32, "flutter": 0.25,
}
const SPECIES := {
	"oak": {},
	"pine": {"size": 5.27, "crookedness": 0.45, "base_flare": 1.4, "clump_size": 1.25, "cards_per_clump": 22,
		"card_size": 0.36, "blades": 5, "blade_width": 0.14, "roundness": 0.0, "flutter": 0.09},
	"cypress": {"clump_size": 1.03, "roundness": 0.0, "flutter": 0.07, "droop": -0.16, "size": 5.27, "crookedness": 0.5,
		"base_flare": 1.0, "trunk_height": 1.22, "blades": 7, "blade_width": 0.12, "card_size": 0.17, "cards_per_clump": 110},
	"bush": {"size": 5.09, "spread": 0.79, "woodless": true},
}

## Leaf and wood ramps, shadow -> mid -> light (sRGB), and what the leaves turn to in autumn. Green spreads
## the Blender bank trees' 438e4b / 89bd57 over three bands, with the reference's warm light; bark is the
## reference's spring wood warmed to taupe. Conifers a deeper, cooler green so species read apart; blossom
## the bank cherry's pinks (efb2c7, f4d0da, db95b1) deepened for the shadow band.
const PALETTES := {
	"green": {"leaves": ["2f7559", "4f9e52", "a4d160"], "wood": ["6e5a55", "8a7262", "b8a086"]},
	"conifer": {"leaves": ["255f52", "3f8a5c", "8cc271"], "wood": ["5e4c48", "7a6354", "a08b74"]},
	"blossom": {"leaves": ["c9799c", "e9a3bd", "f6d2dc"], "wood": ["8d8a99", "aca7b8", "cfcad8"]},
}
const TURNED := ["d0632e", "f2a23a", "f7d66a"]

static func params_for(species: String, overrides := {}) -> Dictionary:
	var p := BASE.duplicate()
	p.merge(SPECIES[species], true)
	p.merge(overrides, true)
	p.species = species
	return p

# --- age (tree-age.js) -------------------------------------------------------------------------------------
const AGES := [0.0, 0.15, 0.35, MATURE, 1.0]
const FRONT := [0.3, 0.45, 0.72, 1.0, 1.0]
const BY_AGE := {
	"size": [0.5, 0.65, 0.85, 1.0, 1.1],
	"trunk_thickness": [0.45, 0.55, 0.75, 1.0, 1.5],
	"base_flare": [0.15, 0.35, 0.7, 1.0, 1.45],
	"trunk_height": [0.5, 0.65, 0.85, 1.0, 1.1],
	"split_height": [1.45, 1.3, 1.1, 1.0, 0.92],
	"spread": [0.85, 0.9, 0.95, 1.0, 1.12],
	"crookedness": [0.6, 0.72, 0.86, 1.0, 1.5],
	"clump_size": [0.8, 0.85, 0.93, 1.0, 0.94],
}
const CLUMP_GROWS := 0.2

## The value at an age of a monotone cubic through `values` at AGES: never overshoots, exact at each age.
static func _curve(values: Array, age: float) -> float:
	var n := AGES.size()
	var step := func(i: int) -> float: return (values[i + 1] - values[i]) / (AGES[i + 1] - AGES[i])
	var slope := func(i: int) -> float:
		if i == 0: return step.call(0)
		if i == n - 1: return step.call(n - 2)
		var a: float = step.call(i - 1)
		var b: float = step.call(i)
		return 0.0 if a * b <= 0.0 else 2.0 / (1.0 / a + 1.0 / b)
	var k := 0
	while k < n - 2 and age > AGES[k + 1]: k += 1
	var h: float = AGES[k + 1] - AGES[k]
	var t: float = (age - AGES[k]) / h
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * values[k] + (t3 - 2 * t2 + t) * h * slope.call(k) \
		+ (3 * t2 - 2 * t3) * values[k + 1] + (t3 - t2) * h * slope.call(k + 1)

## A species' tree at the age p.tree_age gives. A young one is grown twice: measured full grown, to know
## how far its farthest tip reaches and where each clump is, then only as far as its age has taken it.
static func grow_aged(p: Dictionary) -> Dictionary:
	var age := clampf(float(p.tree_age), 0.0, 1.0)
	var s := p.duplicate()
	s.front = _curve(FRONT, age)
	for key in BY_AGE: s[key] = float(p[key]) * _curve(BY_AGE[key], age)
	if s.front >= 1.0: return grow(s)
	var m := s.duplicate()
	m.measuring = true
	var full := grow(m)
	var reach: float = full.wood.farthest
	s.reach = reach
	var young := grow(s)
	var front: float = s.front * reach
	for i in young.clumps.size():
		var fc: Dictionary = full.clumps[i]
		var at: float = fc.birth * reach
		young.clumps[i].full_radius = fc.radius
		young.clumps[i].radius = maxf(fc.radius * smoothstep(at - CLUMP_GROWS * reach, at, front), 1e-4)
	return young

static func grow(p: Dictionary) -> Dictionary:
	match p.species:
		"pine": return _pine(p)
		"cypress": return _cypress(p)
		"bush": return _bush(p)
	return _oak(p)

## A tree's own character, from a random of its own: vary(v, by) is v give or take by, as far as variety goes.
class Character:
	var r := RandomNumberGenerator.new()
	var variety: float
	func _init(p: Dictionary) -> void:
		r.seed = int(p.seed) + 3571
		variety = p.variety
	func vary(v: float, by: float) -> float: return v + (r.randf() * 2.0 - 1.0) * by * variety
	func bearing() -> float: return r.randf() * TAU

static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

## A clump on the tip (or `at` along) of a branch, sitting on that branch's wood.
static func _wood_at(br: Dictionary, at: float) -> Dictionary:
	var w := TreeWood.along(br, minf(at, 0.999))
	return {"radius": w.radius, "dir": w.dir, "flex": w.flex, "phase": w.phase, "point": w.point}

# --- oak: a short trunk splitting low into limbs that branch again ------------------------------------------
static func _oak(p: Dictionary) -> Dictionary:
	const SEGMENTS := 4
	const LENGTH_FALLOFF := 0.7
	const THICKNESS_FALLOFF := 0.7
	const LIMBS_SPAN := 0.7
	const TIP_CLUMP := 0.6
	var shape := {"segments": SEGMENTS, "taper": 0.6, "up_pull": 0.06}
	var random := _rng(int(p.seed))
	var wood := TreeWood.new(p, random)
	var ch := Character.new(p)
	var size: float = p.size * ch.vary(1.0, 0.12)
	var split: float = p.split_height * ch.vary(1.0, 0.25)
	var spread: float = p.spread * ch.vary(1.0, 0.2)
	var lean := TreeWood.splay(Vector3.UP, ch.bearing(), ch.vary(0.0, 0.1))
	var side := ch.bearing()
	var heavy := ch.vary(0.0, 0.25)
	var tips: Array = []   # [branch, scale, end]

	var grow_branch := func(f: Callable, start: Vector3, d: Vector3, length: float, radius: float, depth: int, parent: Dictionary, from: float) -> void:
		var o := shape.duplicate()
		o.parent = parent
		o.from = from
		var br := wood.branch(start, d, length, radius, p.crookedness, o)
		if depth == 0:
			tips.append([br, length, from + length])
			return
		var forked := false
		for c in int(p.branches):
			var k := 2 + floori(random.randf() * (SEGMENTS - 1))
			if k == SEGMENTS: forked = true
			var pd: Vector3 = (br.points[k] - br.points[k - 1]).normalized()
			var around := (c + random.randf() * 0.5) / float(p.branches) * TAU
			var cd := TreeWood.splay(pd, around, spread * (0.6 + random.randf() * 0.6))
			var cl := length * LENGTH_FALLOFF * (0.8 + random.randf() * 0.4)
			f.call(f, br.points[k], cd, cl, br.radii[k] * THICKNESS_FALLOFF, depth - 1,
				{"dir": pd, "radius": br.radii[k], "flex": br.flexes[k], "phase": br.phases[k]}, from + float(k) / SEGMENTS * length)
		if not forked: tips.append([br, length * LENGTH_FALLOFF, from + length])

	var split_len := size * split
	var trunk_len := split_len + float(p.trunk_height)
	var trunk := wood.branch(Vector3.ZERO, lean, trunk_len, p.trunk_thickness, p.crookedness * 0.3,
		{"segments": SEGMENTS, "taper": 0.6, "up_pull": 0.06, "flare": p.base_flare})
	var span := LIMBS_SPAN * float(p.split_scatter) * split_len / trunk_len
	var scatter := _rng(int(p.seed) + 104729)
	for l in int(p.main_limbs):
		var at := 1.0 if l == 0 else 1.0 - scatter.randf() * span
		var w := TreeWood.along(trunk, at) if at < 1.0 else {"point": trunk.points[SEGMENTS],
			"dir": (trunk.points[SEGMENTS] - trunk.points[SEGMENTS - 1]).normalized(), "radius": trunk.radii[SEGMENTS],
			"flex": trunk.flexes[SEGMENTS], "phase": trunk.phases[SEGMENTS]}
		var around := (l + random.randf() * 0.5) / float(p.main_limbs) * TAU
		var d := TreeWood.splay(w.dir, around, spread * (0.8 + random.randf() * 0.4))
		var length := size * (1.0 - split * at) * (0.7 + random.randf() * 0.2) * TreeWood.lopsided(around, side, heavy)
		grow_branch.call(grow_branch, w.point, d, length, float(w.radius) * 0.75, int(p.levels), w, trunk_len * at)

	var leaf := _rng(int(p.seed) + 7919)
	var clumps: Array = []
	for t in tips:
		var br: Dictionary = t[0]
		var radius: float = float(t[1]) * TIP_CLUMP * (0.8 + leaf.randf() * 0.4) * float(p.clump_size)
		var w := _wood_at(br, 1.0)
		clumps.append({"position": br.points[SEGMENTS], "radius": radius, "birth": float(t[2]) / wood.farthest, "wood": w})
	return {"wood": wood, "clumps": clumps}

# --- pine: a straight trunk ringed by whorls of drooping branches carrying flat pads ------------------------
static func _pine(p: Dictionary) -> Dictionary:
	const HEIGHT := 1.3
	const BARE := 0.16
	const TOP := 0.93
	const REACH := 0.34
	const SHORTEST := 0.18
	const DROOP := 0.12
	const PADS := [0.4, 0.7, 1.0]
	const PAD := 0.18
	const FLATTEN := 0.45
	const SMALLEST := 0.03
	const CORE := 0.3
	const CORE_LARGEST := 0.05
	const CORES_FROM := 0.45
	const LEADER := 0.03
	const LEADER_TIP := 0.3
	const LEADER_CLUMPS := 3
	const TOP_PADS := 0.7
	var random := _rng(int(p.seed))
	var wood := TreeWood.new(p, random)
	var ch := Character.new(p)
	var height: float = p.size * HEIGHT * ch.vary(1.0, 0.12)
	var width := ch.vary(1.0, 0.2)
	var bare := ch.vary(BARE, 0.07)
	var droop := clampf(float(p.droop) + ch.vary(0.0, 0.3), -1.0, 1.0)
	var lean := TreeWood.splay(Vector3.UP, ch.bearing(), ch.vary(0.0, 0.05))
	var side := ch.bearing()
	var heavy := ch.vary(0.0, 0.2)
	var trunk := wood.branch(Vector3.ZERO, lean, height, p.trunk_thickness, p.crookedness * 0.3,
		{"segments": 12, "taper": 0.08, "up_pull": 0.4, "flare": p.base_flare})
	var branches: Array = []
	var cores: Array = []
	var whorls: int = p.whorls
	for w in whorls:
		var t := float(w) / (whorls - 1) if whorls > 1 else 0.0
		var at := lerpf(bare, TOP, t) + (random.randf() - 0.5) * (0.4 / whorls)
		var tw := TreeWood.along(trunk, at)
		var reach := height * REACH * width * lerpf(1.0, SHORTEST, t)
		if t >= CORES_FROM: cores.append({"position": tw.point, "radius": minf(reach * CORE, height * CORE_LARGEST), "from": at * height, "wood": tw})
		for b in int(p.whorl_branches):
			var around := (b + (random.randf() - 0.5) * 0.5) / float(p.whorl_branches) * TAU + w * TreeWood.GOLDEN_ANGLE
			var rise := lerpf(0.05, 0.6, t) + (random.randf() - 0.5) * 0.2
			var length := reach * (0.85 + random.randf() * 0.3) * TreeWood.lopsided(around, side, heavy)
			var from := at * height
			var br := wood.branch(tw.point, TreeWood.heading(around, rise), length, float(tw.radius) * 0.45, p.crookedness * 0.5,
				{"parent": tw, "from": from, "segments": 5, "taper": 0.35, "up_pull": -droop * DROOP})
			branches.append({"br": br, "length": length, "from": from, "last": w == whorls - 1})
	var leaf := _rng(int(p.seed) + 7919)
	var clumps: Array = []
	var tuft := height * SMALLEST
	for b in branches:
		for along in ([1.0] if b.last else PADS):
			var radius: float = maxf(b.length * PAD * (1.2 - 0.5 * along), tuft) * (0.85 + leaf.randf() * 0.3) * float(p.clump_size) * (TOP_PADS if b.last else 1.0)
			var w := _wood_at(b.br, along)
			clumps.append({"position": w.point, "radius": radius, "flatten": FLATTEN, "birth": (b.from + along * b.length) / wood.farthest, "wood": w})
	for c in cores:
		clumps.append({"position": c.position, "radius": maxf(c.radius, tuft) * float(p.clump_size), "birth": c.from / wood.farthest, "wood": c.wood})
	for s in LEADER_CLUMPS:
		var at := lerpf(TOP, 1.0, float(s) / (LEADER_CLUMPS - 1))
		var w := _wood_at(trunk, at)
		clumps.append({"position": w.point, "radius": height * LEADER * lerpf(1.0, LEADER_TIP, float(s) / (LEADER_CLUMPS - 1)) * float(p.clump_size),
			"birth": at * height / wood.farthest, "wood": w})
	return {"wood": wood, "clumps": clumps}

# --- cypress: a tall narrow flame, short branches climbing a spiral --------------------------------------------
static func _cypress(p: Dictionary) -> Dictionary:
	const HEIGHT := 1.32
	const BARE := 0.05
	const TOP := 0.95
	const WIDTH := 0.11
	const TIP := 1.6
	const FULL_FOOT := 0.4
	const BRANCH_SEGMENTS := 3
	const RISE := 1.05
	const DROOP := 0.12
	const PAD := 0.6
	const FULL_TOP := 0.8
	const CORES := 16
	const SMALLEST := 0.03
	var random := _rng(int(p.seed))
	var wood := TreeWood.new(p, random)
	var ch := Character.new(p)
	var height: float = p.size * HEIGHT * ch.vary(1.0, 0.1)
	var width := WIDTH * ch.vary(1.0, 0.2)
	var tip := ch.vary(TIP, 0.5)
	var lean := TreeWood.splay(Vector3.UP, ch.bearing(), ch.vary(0.0, 0.05))
	var trunk_h: float = p.trunk_height
	var trunk_len := height + trunk_h
	var on_trunk := func(at: float) -> float: return (trunk_h + at * height) / trunk_len
	var half_width := func(at: float) -> float:
		var up := maxf(at - BARE, 0.0) / (1.0 - BARE)
		var sh := (1.0 - pow(up, tip)) * (1.0 + FULL_FOOT * pow(1.0 - up, 3.0))
		return height * width * maxf(sh, 0.0) / float(p.slenderness)
	var trunk := wood.branch(Vector3.ZERO, lean, trunk_len, p.trunk_thickness, p.crookedness * 0.2,
		{"segments": 14, "taper": 0.1, "up_pull": 0.5, "flare": p.base_flare})
	var branches: Array = []
	var count: int = p.cypress_branches
	for i in count:
		var at := lerpf(BARE, TOP, (i + random.randf() * 0.6) / count)
		var tw := TreeWood.along(trunk, on_trunk.call(at))
		var around := i * TreeWood.GOLDEN_ANGLE + (random.randf() - 0.5) * 0.4
		var rise := RISE + (random.randf() - 0.5) * 0.2
		var length := maxf(float(half_width.call(at)) / cos(rise) * (0.8 + random.randf() * 0.3), height * SMALLEST * 2.0)
		var from: float = on_trunk.call(at) * trunk_len
		var br := wood.branch(tw.point, TreeWood.heading(around, rise), length, float(tw.radius) * 0.35, p.crookedness * 0.4,
			{"parent": tw, "from": from, "segments": BRANCH_SEGMENTS, "taper": 0.4, "up_pull": -float(p.droop) * DROOP})
		branches.append({"br": br, "length": length, "from": from})
	var leaf := _rng(int(p.seed) + 7919)
	var tuft := height * SMALLEST
	var clump_radius := func(at: float, by: float) -> float:
		return maxf(float(half_width.call(at)) * by, tuft) * (1.0 + FULL_TOP * pow(clampf(at, 0.0, 1.0), 2.0))
	var clumps: Array = []
	for b in branches:
		for k in range(1, BRANCH_SEGMENTS + 1):
			var along := float(k) / BRANCH_SEGMENTS
			var position: Vector3 = b.br.points[k]
			var radius: float = clump_radius.call((position.y - trunk_h) / height, PAD) * (0.85 + leaf.randf() * 0.3)
			clumps.append({"position": position, "radius": radius * float(p.clump_size), "birth": (b.from + along * b.length) / wood.farthest,
				"wood": _wood_at(b.br, along)})
	for s in CORES + 1:
		var at := lerpf(BARE, 0.999, float(s) / CORES)
		var w := _wood_at(trunk, on_trunk.call(at))
		clumps.append({"position": w.point, "radius": float(clump_radius.call(at, PAD * 1.2)) * float(p.clump_size),
			"birth": float(on_trunk.call(at)) * trunk_len / wood.farthest, "wood": w})
	return {"wood": wood, "clumps": clumps}

# --- bush: no wood, a low dome of clumps on the ground ----------------------------------------------------------
static func _bush(p: Dictionary) -> Dictionary:
	const HEIGHT := 0.5
	const WIDTH := 0.9
	const MIDDLE := 0.5
	const EDGE := 0.3
	const SINK := 0.85
	var wood := TreeWood.new(p, _rng(int(p.seed)))
	var ch := Character.new(p)
	var height: float = p.size * HEIGHT * ch.vary(1.0, 0.15)
	var width: float = height * WIDTH * float(p.spread) * ch.vary(1.0, 0.2)
	var side := ch.bearing()
	var heavy := ch.vary(0.0, 0.2)
	var random := _rng(int(p.seed) + 7919)
	var clumps: Array = []
	var count: int = p.bush_clumps
	for i in count:
		var around := i * TreeWood.GOLDEN_ANGLE + (random.randf() - 0.5) * 0.4
		var out := sqrt(float(i) / (count - 1)) if count > 1 else 0.0
		var reach := width * out * (0.85 + random.randf() * 0.3) * TreeWood.lopsided(around, side, heavy)
		var radius := height * lerpf(MIDDLE, EDGE, out) * (0.85 + random.randf() * 0.3) * float(p.clump_size)
		var position := Vector3(cos(around) * reach, radius * SINK, sin(around) * reach)
		# no wood: each clump bobs on a beat of its own, its young leaves gather at its foot
		var beat := _rng(int(p.seed) + 2903 + i)
		clumps.append({"position": position, "radius": radius, "birth": out, "foot": Vector3(position.x, 0.0, position.z),
			"swing": {"flex": 1.0, "phase": beat.randf() * TAU}})
	return {"wood": wood, "clumps": clumps}
