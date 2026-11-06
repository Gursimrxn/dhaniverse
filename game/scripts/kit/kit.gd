class_name Kit
extends RefCounted
## Parametric cozy architecture kit. Every public builder returns a Node3D whose
## origin is the ground centre of its footprint, front facing +Z, metres, +Y up.
## cfg keys all have defaults; `seed` drives every random choice so variants differ
## but rebuild identically. Internals `_xxx(mb, ...)` write into a shared MeshUtil so
## composite pieces (hall + stalls + awnings) bake into a single mesh.

# Shades derived from the Brand palette (Brand autoload holds the base hues).
const TIMBER_D := Color("6f4529")
const TIMBER_L := Color("c08a5a")
const WEATHERED := Color("9c7a58")
const STONE_D := Color("7d8382")
const STONE_L := Color("bdbfba")
const IRON := Color("2a3138")
const CANVAS := Color("f3eee0")
const ROPE := Color("c9a66b")
const CHALK := Color("2c3a34")
const WALLS := [Color("b7c4a6"), Color("8ea8c6"), Color("b65e4c"), Color("c9775a"), Color("9aa58f"), Color("a7b8a0")]
const FLOWERS := [Color("ef6f5e"), Color("f2b632"), Color("f4a6bd"), Color("f6f1e4"), Color("9b8fd6"), Color("e8894f")]


static func _rng(cfg: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(int(cfg.get("seed", 0)) * 7919 + 17)
	return r


static func _jit(c: Color, r: RandomNumberGenerator, amt := 0.06) -> Color:
	var k := r.randf_range(-amt, amt)
	return Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k * 0.8, 0, 1))


static func _leaf(r: RandomNumberGenerator) -> Color:
	return _jit([Brand.LEAF_MID, Brand.LEAF_DEEP, Color("7cbc4c"), Color("468a3c")][r.randi() % 4], r, 0.04)


static func _xf(x: float, y: float, z: float, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshUtil.xf(Vector3(x, y, z), rot, scl)


## Run `f(mb)` with mb.base temporarily multiplied by `t` (sub-assembly helper).
static func _with(mb: MeshUtil, t: Transform3D, f: Callable) -> void:
	var keep := mb.base
	mb.base = keep * t
	f.call(mb)
	mb.base = keep


# =====================================================================================
# Roofs
# =====================================================================================
## Slate gable roof, ridge along local Z. span = wall-to-wall width across X.
static func _gable_roof(mb: MeshUtil, t: Transform3D, span: float, length: float, pitch: float, eave_y: float, overhang: float, col: Color, trim: Color, r: RandomNumberGenerator, end_overhang := -1.0) -> float:
	var p := deg_to_rad(pitch)
	var half := span * 0.5 + overhang
	var rise := span * 0.5 * tan(p)
	var thick := 0.16
	var eo := overhang if end_overhang < 0.0 else end_overhang
	var L := length + eo * 2.0
	var slab := half / cos(p) + thick * tan(p) * 0.5
	for s in [-1.0, 1.0]:
		var nrm := Vector3(s * sin(p), cos(p), 0)
		var c := Vector3(s * half * 0.5, eave_y + rise - half * 0.5 * tan(p), 0) + nrm * thick * 0.5
		var rot := Basis(Vector3.BACK, -s * p)
		mb.box("solid", t * Transform3D(rot, c), Vector3(slab, thick, L), _jit(col, r, 0.02), 0.035)
		# slate courses: low raised strips running along the ridge
		var courses := maxi(2, int(slab / 0.42))
		for k in courses:
			var f := (k + 0.6) / courses
			var pc: Vector3 = c + Vector3(cos(p) * s, -sin(p), 0) * ((f - 0.5) * slab) + nrm * (thick * 0.5 + 0.012)
			mb.box("solid", t * Transform3D(rot, pc), Vector3(0.05, 0.03, L - 0.04), col.darkened(0.18))
		# bargeboards under both gable ends
		for e in [-1.0, 1.0]:
			mb.box("solid", t * Transform3D(rot, c - nrm * (thick * 0.5 + 0.08) + Vector3(0, 0, e * (L * 0.5 - 0.05))), Vector3(slab, 0.16, 0.08), trim)
		# fascia along the eave
		mb.box("solid", t * _xf(s * (half - 0.02), eave_y - overhang * tan(p) - 0.02, 0), Vector3(0.09, 0.16, L - 0.04), trim)
	mb.box("solid", t * _xf(0, eave_y + rise + thick * 0.9, 0), Vector3(0.26, 0.14, L + 0.04), col.darkened(0.25), 0.04)
	return rise


# =====================================================================================
# Windows / doors
# =====================================================================================
## Window centred on t (wall surface at local z=0, facing +Z).
static func _window(mb: MeshUtil, t: Transform3D, ww: float, wh: float, frame: Color, shutter, box: bool, r: RandomNumberGenerator) -> void:
	mb.box("solid", t * _xf(0, 0, 0.03), Vector3(ww + 0.16, wh + 0.16, 0.06), frame, 0.02)
	mb.box("glass", t * _xf(0, 0, 0.065), Vector3(ww - 0.02, wh - 0.02, 0.02), Color.WHITE)
	mb.box("solid", t * _xf(0, 0, 0.09), Vector3(0.05, wh, 0.04), frame)
	mb.box("solid", t * _xf(0, wh * 0.12, 0.09), Vector3(ww, 0.05, 0.04), frame)
	mb.box("solid", t * _xf(0, -wh * 0.5 - 0.1, 0.08), Vector3(ww + 0.3, 0.07, 0.17), Brand.STONE, 0.02)
	if shutter != null:
		for s in [-1.0, 1.0]:
			mb.box("solid", t * _xf(s * (ww * 0.5 + 0.08 + ww * 0.22), 0, 0.04), Vector3(ww * 0.44, wh + 0.06, 0.05), shutter, 0.015)
			mb.box("solid", t * _xf(s * (ww * 0.5 + 0.08 + ww * 0.22), 0, 0.07), Vector3(ww * 0.3, 0.04, 0.02), (shutter as Color).darkened(0.25))
	if box:
		var by := -wh * 0.5 - 0.3
		mb.box("solid", t * _xf(0, by, 0.17), Vector3(ww + 0.1, 0.22, 0.24), TIMBER_D, 0.03)
		var n := int(ww / 0.22)
		for i in n:
			var x := (i + 0.5) / n * ww - ww * 0.5
			mb.sphere("leaf", t * _xf(x, by + 0.15, 0.2, Vector3.ZERO, Vector3(1, 0.8, 1)), r.randf_range(0.12, 0.16), _leaf(r), 5, 3)
			if r.randf() < 0.7:
				mb.sphere("solid", t * _xf(x + r.randf_range(-0.06, 0.06), by + 0.26, 0.27), 0.05, FLOWERS[r.randi() % FLOWERS.size()], 4, 3)


static func _door(mb: MeshUtil, t: Transform3D, col: Color, frame: Color) -> void:
	mb.box("solid", t * _xf(0, 1.08, 0.03), Vector3(1.2, 2.26, 0.06), frame, 0.02)
	mb.box("solid", t * _xf(0, 1.02, 0.07), Vector3(0.96, 2.04, 0.05), col, 0.02)
	for py in [0.55, 1.45]:
		mb.box("solid", t * _xf(0, py, 0.1), Vector3(0.66, 0.6 if py < 1 else 0.7, 0.02), col.darkened(0.15))
	mb.sphere("solid", t * _xf(0.36, 1.0, 0.12), 0.04, Brand.GOLD, 5, 3)
	mb.box("solid", t * _xf(0, 0.09, 0.35), Vector3(1.5, 0.18, 0.6), Brand.STONE, 0.04)
	# little slate hood over the door
	mb.box("solid", t * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(22)), Vector3(0, 2.42, 0.32)), Vector3(1.55, 0.08, 0.7), Brand.SLATE, 0.02)
	for s in [-1.0, 1.0]:
		mb.segment("solid", Vector3(s * 0.66, 2.0, 0.04), Vector3(s * 0.66, 2.32, 0.55), 0.035, TIMBER_D, 4, t)


# =====================================================================================
# House
# =====================================================================================
## cfg: seed, width, depth, floors, floor_height, roof_pitch, wall (Color), roof (Color),
## trim (Color), accent (door/shutters Color), gable_front (bool), chimney (bool),
## pergola (bool), shutters (bool), flower_boxes (bool)
static func house(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	_house(mb, cfg)
	return mb.to_node("House")


static func _house(mb: MeshUtil, cfg: Dictionary) -> void:
	var r := _rng(cfg)
	var w: float = cfg.get("width", snappedf(r.randf_range(4.6, 6.6), 0.1))
	var d: float = cfg.get("depth", snappedf(r.randf_range(4.4, 5.8), 0.1))
	var floors: int = cfg.get("floors", r.randi_range(1, 2))
	var fh: float = cfg.get("floor_height", 2.7)
	var pitch: float = cfg.get("roof_pitch", r.randf_range(32.0, 44.0))
	var wall: Color = cfg.get("wall", WALLS[r.randi() % WALLS.size()])
	var roof: Color = cfg.get("roof", Brand.SLATE)
	var trim: Color = cfg.get("trim", [Brand.INK, Color("2f3a40"), TIMBER_D][r.randi() % 3])
	var accent: Color = cfg.get("accent", [Brand.TEAL, Color("4f7b5a"), TIMBER_D, Color("3e6f8e"), Brand.CORAL][r.randi() % 5])
	var gable_front: bool = cfg.get("gable_front", r.randf() < 0.5)
	var chimney: bool = cfg.get("chimney", r.randf() < 0.6)
	var pergola: bool = cfg.get("pergola", r.randf() < 0.5)
	var shutters: bool = cfg.get("shutters", r.randf() < 0.5)
	var boxes: bool = cfg.get("flower_boxes", true)

	var plinth := 0.4
	var H := floors * fh
	var eave := plinth + H
	mb.box("solid", _xf(0, plinth * 0.5, 0), Vector3(w + 0.24, plinth, d + 0.24), STONE_D, 0.05)
	mb.box("solid", _xf(0, plinth + H * 0.5, 0), Vector3(w, H, d), wall, 0.05)
	for f in range(1, floors):
		mb.box("solid", _xf(0, plinth + f * fh, 0), Vector3(w + 0.08, 0.16, d + 0.08), trim.lerp(wall, 0.3), 0.02)
	# corner quoins in stone for a sturdier read
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box("solid", _xf(sx * (w * 0.5 - 0.1), plinth + H * 0.5, sz * (d * 0.5 - 0.1)), Vector3(0.28, H, 0.28), wall.darkened(0.12), 0.03)

	var span := w if gable_front else d
	var length := d if gable_front else w
	var rt := Transform3D.IDENTITY if gable_front else Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var rise := _gable_roof(mb, rt, span, length, pitch, eave, 0.45, roof, trim, r)
	mb.prism("solid", rt * _xf(0, eave, 0), span, rise, length, wall)
	if chimney:
		var cx := span * 0.25 * (1.0 if r.randf() < 0.5 else -1.0)
		var cz := length * r.randf_range(-0.25, 0.25)
		var top := eave + rise + 0.5
		mb.box("solid", rt * _xf(cx, (eave + top) * 0.5 + 0.2, cz), Vector3(0.55, top - eave + 0.4, 0.55), Brand.STONE.lerp(Color("b65e4c"), 0.4), 0.04)
		mb.box("solid", rt * _xf(cx, top + 0.45, cz), Vector3(0.68, 0.12, 0.68), STONE_D, 0.03)

	# front door + windows on all four facades
	var door_x: float = cfg.get("door_x", snappedf(r.randf_range(-0.25, 0.25) * w, 0.1))
	_door(mb, _xf(door_x, plinth, d * 0.5), accent, trim)
	var faces := [[Transform3D(Basis(), Vector3(0, 0, d * 0.5)), w], [Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -d * 0.5)), w],
		[Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w * 0.5, 0, 0)), d], [Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-w * 0.5, 0, 0)), d]]
	for fi in faces.size():
		var ft: Transform3D = faces[fi][0]
		var fw: float = faces[fi][1]
		var n := maxi(1, int((fw - 0.8) / 1.7))
		for f in floors:
			for i in n:
				var x := (i + 0.5) / n * (fw - 0.8) - (fw - 0.8) * 0.5
				if fi == 0 and f == 0 and absf(x - door_x) < 1.2:
					continue
				var wh := 1.15 if f == 0 else 1.05
				var y := plinth + f * fh + 1.45
				_window(mb, ft * _xf(x, y, 0), 0.9, wh, trim, accent if shutters else null, boxes and fi == 0 and r.randf() < 0.6, r)
	mb.collider(_xf(0, eave * 0.5, 0), Vector3(w + 0.24, eave, d + 0.24))
	if pergola:
		var pw := minf(w * 0.7, 3.2)
		_with(mb, _xf(w * 0.5 + 1.25, 0, d * 0.5 - pw * 0.5 - 0.2, Vector3(0, 90, 0)), func(m): _pergola(m, {"seed": cfg.get("seed", 0), "width": pw, "depth": 2.2, "height": 2.5}))


# =====================================================================================
# Pergola with vines
# =====================================================================================
## cfg: seed, width, depth, height, vines (0..1 density), flowers (bool)
static func pergola(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	_pergola(mb, cfg)
	return mb.to_node("Pergola")


static func _pergola(mb: MeshUtil, cfg: Dictionary) -> void:
	var r := _rng(cfg)
	r.seed += 31
	var w: float = cfg.get("width", 3.0)
	var d: float = cfg.get("depth", 2.4)
	var h: float = cfg.get("height", 2.5)
	var vines: float = cfg.get("vines", 0.8)
	var flowers: bool = cfg.get("flowers", true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (w * 0.5 - 0.1), 0, sz * (d * 0.5 - 0.1))
			mb.box("solid", _xf(p.x, 0.1, p.z), Vector3(0.34, 0.2, 0.34), Brand.STONE, 0.04)
			mb.box("solid", _xf(p.x, h * 0.5, p.z), Vector3(0.16, h, 0.16), Brand.TIMBER, 0.025)
			mb.collider(_xf(p.x, h * 0.5, p.z), Vector3(0.2, h, 0.2))
	for sz in [-1.0, 1.0]:
		mb.box("solid", _xf(0, h + 0.09, sz * (d * 0.5 - 0.1)), Vector3(w + 0.5, 0.2, 0.14), TIMBER_D, 0.025)
	var n := int(w / 0.5) + 1
	for i in n:
		var x := (float(i) / (n - 1) - 0.5) * (w - 0.1)
		mb.box("solid", _xf(x, h + 0.27, 0), Vector3(0.08, 0.16, d + 0.5), Brand.TIMBER, 0.015)
	# vines: leaf clusters on the rafters, trailing down two posts
	mb.sway = 0.35
	var count := int(w * d * vines * 2.2)
	for i in count:
		var p := Vector3(r.randf_range(-w * 0.55, w * 0.55), h + 0.38 + r.randf_range(-0.05, 0.12), r.randf_range(-d * 0.55, d * 0.55))
		var s := r.randf_range(0.2, 0.34)
		mb.sphere("leaf", _xf(p.x, p.y, p.z, Vector3(0, r.randf() * 90, 0), Vector3(1.2, 0.6, 1.0)), s, _leaf(r), 5, 3)
		if flowers and r.randf() < 0.45:
			mb.sphere("leaf", _xf(p.x + r.randf_range(-0.1, 0.1), p.y + s * 0.5, p.z + r.randf_range(-0.1, 0.1)), 0.06, FLOWERS[[0, 2, 5][r.randi() % 3]], 4, 3)
	for sx in [-1.0, 1.0]:
		if vines < 0.4 and sx > 0:
			continue
		var px: float = sx * (w * 0.5 - 0.1)
		var pz := d * 0.5 - 0.1
		var y := 0.3
		while y < h:
			mb.sphere("leaf", _xf(px + r.randf_range(-0.12, 0.12), y, pz + r.randf_range(-0.12, 0.12), Vector3.ZERO, Vector3(1, 1.3, 1)), r.randf_range(0.14, 0.22), _leaf(r), 5, 3)
			y += r.randf_range(0.32, 0.5)
		# a drape hanging from the front beam
		for k in 3:
			mb.sphere("leaf", _xf(px - sx * (0.3 + k * 0.35), h - 0.15 - r.randf() * 0.3, pz + 0.05, Vector3.ZERO, Vector3(0.8, 1.5, 0.8)), 0.16, _leaf(r), 5, 3)
	mb.sway = 0.0


# =====================================================================================
# Market hall
# =====================================================================================
## Open timber hall: a row of bays each with its own slate gable facing +Z.
## cfg: seed, bays, bay_width, depth, post_height, roof_pitch, stalls (bool), sign (bool),
## awning_styles (Array of "teal"/"coral"/"gold")
static func market_hall(cfg := {}) -> Node3D:
	var r := _rng(cfg)
	var mb := MeshUtil.new()
	var bays: int = cfg.get("bays", 3)
	var bw: float = cfg.get("bay_width", 4.4)
	var d: float = cfg.get("depth", 6.0)
	var ph: float = cfg.get("post_height", 3.1)
	var pitch: float = cfg.get("roof_pitch", 40.0)
	var stalls: bool = cfg.get("stalls", true)
	var styles: Array = cfg.get("awning_styles", ["teal", "coral", "teal", "gold"])
	var W := bays * bw
	var floor_h := 0.15
	mb.box("solid", _xf(0, floor_h * 0.5, 0), Vector3(W + 0.8, floor_h, d + 0.8), STONE_L, 0.05)
	mb.collider(_xf(0, floor_h * 0.5, 0), Vector3(W + 0.8, floor_h, d + 0.8))
	var top := floor_h + ph
	for i in bays + 1:
		var x := -W * 0.5 + i * bw
		for sz in [-1.0, 1.0]:
			var z: float = sz * (d * 0.5 - 0.15)
			mb.box("solid", _xf(x, floor_h + 0.15, z), Vector3(0.44, 0.3, 0.44), Brand.STONE, 0.05)
			mb.box("solid", _xf(x, floor_h + ph * 0.5, z), Vector3(0.26, ph, 0.26), TIMBER_D, 0.04)
			mb.collider(_xf(x, floor_h + ph * 0.5, z), Vector3(0.3, ph, 0.3))
			for s in [-1.0, 1.0]:
				if (i == 0 and s < 0) or (i == bays and s > 0):
					continue
				mb.segment("solid", Vector3(x, top - 0.85, z), Vector3(x + s * 0.75, top - 0.15, z), 0.06, TIMBER_D)
		mb.box("solid", _xf(x, top - 0.12, 0), Vector3(0.22, 0.24, d), TIMBER_D, 0.03)
	for sz in [-1.0, 1.0]:
		mb.box("solid", _xf(0, top - 0.14, sz * (d * 0.5 - 0.15)), Vector3(W + 0.4, 0.28, 0.28), TIMBER_D, 0.04)
	for b in bays:
		var cx := -W * 0.5 + (b + 0.5) * bw
		var bt := _xf(cx, 0, 0)
		var rise := _gable_roof(mb, bt, bw, d, pitch, top, 0.12, Brand.SLATE, TIMBER_D, r, 0.55)
		# timber gable infill with vertical boards (front + back)
		for sz in [-1.0, 1.0]:
			var gz: float = sz * (d * 0.5 - 0.1)
			mb.prism("solid", bt * _xf(0, top, gz), bw, rise, 0.1, TIMBER_L)
			var nb := int(bw / 0.36)
			for k in range(1, nb):
				var x := (float(k) / nb - 0.5) * bw
				var hh := rise * (1.0 - absf(x) / (bw * 0.5)) - 0.06
				if hh > 0.1:
					mb.box("solid", bt * _xf(x, top + hh * 0.5, gz + sz * 0.06), Vector3(0.04, hh, 0.03), Brand.TIMBER.darkened(0.2))
			# round vent + little bunting of lights under the eave
			mb.cyl("solid", bt * _xf(0, top + rise * 0.45, gz + sz * 0.05, Vector3(90, 0, 0)), 0.2, 0.2, 0.05, 8, TIMBER_D)
		if stalls:
			var st := styles[b % styles.size()] as String
			_with(mb, _xf(cx, floor_h, d * 0.5 - 1.25), func(m): _stall(m, {"seed": int(cfg.get("seed", 0)) * 13 + b, "width": bw - 1.0, "awning_style": st, "awning_posts": false, "awning_height": top - 0.45 - floor_h, "awning_back": 1.1, "awning_depth": 1.5}))
			# back counter with sacks + crates
			_with(mb, _xf(cx, floor_h, -d * 0.5 + 0.9, Vector3(0, 180, 0)), func(m): _stall(m, {"seed": int(cfg.get("seed", 0)) * 31 + b, "width": bw - 1.2, "awning": false}))
	if cfg.get("sign", true):
		_with(mb, _xf(-W * 0.5 + 0.9, floor_h, d * 0.5 + 0.9, Vector3(0, -15, 0)), func(m): _chalkboard(m, {"seed": cfg.get("seed", 0)}))
	return mb.to_node("MarketHall")


# =====================================================================================
# Produce stall, crates, chalkboard
# =====================================================================================
## cfg: seed, width, depth, goods (Array of "tomato","orange","apple","aubergine",
## "greens","bread","lemon","carrot"), awning (bool), awning_style, awning_posts,
## awning_height, awning_depth, awning_back (z of awning back edge), sign (bool)
static func produce_stall(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	_stall(mb, cfg)
	return mb.to_node("ProduceStall")


const GOODS := ["tomato", "orange", "apple", "aubergine", "greens", "bread", "lemon", "carrot"]


static func _stall(mb: MeshUtil, cfg: Dictionary) -> void:
	var r := _rng(cfg)
	var w: float = cfg.get("width", 2.4)
	var d: float = cfg.get("depth", 1.0)
	var goods: Array = cfg.get("goods", GOODS)
	var th := 0.82
	mb.box("solid", _xf(0, th - 0.04, 0), Vector3(w, 0.08, d), Brand.TIMBER, 0.02)
	mb.box("solid", _xf(0, th - 0.2, d * 0.5 - 0.03), Vector3(w - 0.05, 0.24, 0.05), TIMBER_D, 0.015)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box("solid", _xf(sx * (w * 0.5 - 0.06), (th - 0.08) * 0.5, sz * (d * 0.5 - 0.06)), Vector3(0.08, th - 0.08, 0.08), TIMBER_D)
	mb.box("solid", _xf(0, 0.22, 0), Vector3(w - 0.1, 0.05, d - 0.1), TIMBER_D)
	mb.collider(_xf(0, th * 0.5, 0), Vector3(w, th, d))
	# riser at the back for a second tier
	mb.box("solid", _xf(0, th + 0.13, -d * 0.25), Vector3(w - 0.1, 0.26, d * 0.42), TIMBER_L, 0.02)
	var n := maxi(2, int(w / 0.52))
	var cw := (w - 0.1) / n
	for row in 2:
		for i in n:
			var x := (i + 0.5) * cw - (w - 0.1) * 0.5
			var y := th + 0.11 + (0.26 if row == 1 else 0.0)
			var z := d * 0.22 if row == 0 else -d * 0.25
			_crate(mb, _xf(x, y, z, Vector3(14 if row == 0 else 8, 0, 0)), Vector3(cw - 0.05, 0.2, d * 0.4), goods[r.randi() % goods.size()], r)
	# a couple of crates on the ground beside the table
	_crate(mb, _xf(w * 0.5 + 0.3, 0.13, d * 0.2, Vector3(0, r.randf_range(-15, 15), 0)), Vector3(0.48, 0.26, 0.38), goods[r.randi() % goods.size()], r)
	mb.box("solid", _xf(w * 0.5 + 0.3, 0.13, -d * 0.25), Vector3(0.46, 0.26, 0.36), TIMBER_L, 0.02)
	_crate(mb, _xf(w * 0.5 + 0.3, 0.39, -d * 0.25, Vector3(0, 8, 0)), Vector3(0.44, 0.24, 0.34), goods[r.randi() % goods.size()], r)
	# sacks of grain
	mb.sphere("solid", _xf(-w * 0.5 - 0.28, 0.24, d * 0.15, Vector3.ZERO, Vector3(1, 1.25, 1)), 0.22, Color("d8c39a"), 6, 4)
	if cfg.get("awning", true):
		var ah: float = cfg.get("awning_height", 2.25)
		var ad: float = cfg.get("awning_depth", 1.5)
		var ab: float = cfg.get("awning_back", -d * 0.5 - 0.1)
		_with(mb, _xf(0, 0, ab), func(m): _awning(m, {"seed": cfg.get("seed", 0), "width": w + 0.3, "depth": ad, "height": ah, "style": cfg.get("awning_style", "teal"), "posts": cfg.get("awning_posts", true)}))
	if cfg.get("sign", false):
		_with(mb, _xf(-w * 0.5 - 0.4, 0, d * 0.5 + 0.5, Vector3(0, 20, 0)), func(m): _chalkboard(m, cfg))


## cfg: seed, size (Vector3), good (String)
static func crate(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var size: Vector3 = cfg.get("size", Vector3(0.5, 0.26, 0.38))
	_crate(mb, _xf(0, size.y * 0.5, 0), size, cfg.get("good", GOODS[r.randi() % GOODS.size()]), r)
	mb.collider(_xf(0, size.y * 0.5, 0), size)
	return mb.to_node("Crate")


static func _crate(mb: MeshUtil, t: Transform3D, s: Vector3, good: String, r: RandomNumberGenerator) -> void:
	mb.box("solid", t, s, _jit(TIMBER_L, r, 0.04), 0.02)
	mb.box("solid", t * _xf(0, -s.y * 0.12, s.z * 0.5 + 0.005), Vector3(s.x - 0.06, 0.035, 0.02), TIMBER_D)
	mb.box("solid", t * _xf(0, s.y * 0.2, s.z * 0.5 + 0.005), Vector3(s.x - 0.06, 0.035, 0.02), TIMBER_D)
	var col: Color
	var rad := 0.06
	var scl := Vector3.ONE
	match good:
		"tomato": col = Color("e0412f"); rad = 0.055
		"orange": col = Color("f28c28"); rad = 0.065
		"apple": col = Color("c8352c"); rad = 0.06
		"lemon": col = Color("f4d03f"); rad = 0.055; scl = Vector3(1.25, 1, 1)
		"aubergine": col = Color("5b2c6f"); rad = 0.05; scl = Vector3(1, 1, 2.0)
		"greens": col = Color("6db345"); rad = 0.1; scl = Vector3(1, 0.75, 1)
		"bread": col = Color("d29a55"); rad = 0.075; scl = Vector3(1.6, 0.8, 1)
		"carrot": col = Color("ee7a22"); rad = 0.035; scl = Vector3(1, 1, 3.2)
		_: col = Brand.CORAL
	var nx := clampi(int(s.x / (rad * 2.0 * scl.x)), 1, 5)
	var nz := clampi(int(s.z / (rad * 2.0 * scl.z)), 1, 4)
	for i in nx:
		for k in nz:
			var p := Vector3((i + 0.5) / nx * s.x - s.x * 0.5, s.y * 0.5 + rad * 0.45, (k + 0.5) / nz * s.z - s.z * 0.5)
			p += Vector3(r.randf_range(-0.01, 0.01), r.randf_range(0, 0.03), r.randf_range(-0.01, 0.01))
			var c := _jit(col, r, 0.05)
			if good == "apple" and r.randf() < 0.3:
				c = Color("8cbf3f")
			mb.sphere("solid", t * MeshUtil.xf(p, Vector3(0, r.randf() * 40, 0), scl), rad, c, 5, 3)


## A-frame chalkboard sign. cfg: seed, height
static func chalkboard(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	_chalkboard(mb, cfg)
	mb.collider(_xf(0, 0.45, 0), Vector3(0.65, 0.9, 0.5))
	return mb.to_node("Chalkboard")


static func _chalkboard(mb: MeshUtil, cfg: Dictionary) -> void:
	var r := _rng(cfg)
	var h: float = cfg.get("height", 0.95)
	for s in [-1.0, 1.0]:
		var bt := MeshUtil.xf(Vector3(0, h * 0.5, s * 0.1), Vector3(s * 12.0, 0, 0))
		mb.box("solid", bt, Vector3(0.62, h, 0.05), Brand.TIMBER, 0.015)
		mb.box("solid", bt * _xf(0, 0.02, s * 0.03), Vector3(0.5, h - 0.18, 0.02), CHALK)
		for k in 4:
			var lw := r.randf_range(0.18, 0.38)
			var c: Color = [Color("f2efe6"), Brand.GOLD, Color("f2efe6"), Brand.CORAL][k]
			mb.box("solid", bt * _xf(r.randf_range(-0.06, 0.06), h * 0.25 - k * 0.15, s * 0.045), Vector3(lw, 0.045 if k == 0 else 0.03, 0.01), c)


# =====================================================================================
# Awning (striped canvas, sways)
# =====================================================================================
## Back edge at z=0 / y=height, slopes down towards +Z.
## cfg: seed, width, depth, height, slope (deg), style ("teal","coral","gold"), stripe, posts (bool), valance (bool)
static func awning(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	_awning(mb, cfg)
	return mb.to_node("Awning")


static func _awning(mb: MeshUtil, cfg: Dictionary) -> void:
	var w: float = cfg.get("width", 2.6)
	var d: float = cfg.get("depth", 1.5)
	var h: float = cfg.get("height", 2.3)
	var slope: float = cfg.get("slope", 20.0)
	var sw: float = cfg.get("stripe", 0.3)
	var style: String = cfg.get("style", "teal")
	var c1: Color = {"teal": Brand.TEAL, "coral": Brand.CORAL, "gold": Brand.GOLD, "cream": Color("f1e9d6")}.get(style, Brand.TEAL)
	var cols := [c1, CANVAS]
	var a := deg_to_rad(slope)
	var drop := sin(a) * d
	var reach := cos(a) * d
	var n := maxi(2, int(round(w / sw)))
	var s := w / n
	mb.sway_fn = func(p: Vector3) -> float: return p.z / reach
	for i in n:
		var x := (i + 0.5) * s - w * 0.5
		var c: Color = cols[i % 2]
		mb.box("cloth", _xf(x, h - drop * 0.5, reach * 0.5, Vector3(slope, 0, 0)), Vector3(s + 0.002, 0.04, d), c)
		if cfg.get("valance", true):
			mb.box("cloth", _xf(x, h - drop - 0.11, reach + 0.02), Vector3(s, 0.2, 0.03), c)
			mb.prism("cloth", _xf(x, h - drop - 0.21, reach + 0.02, Vector3(0, 0, 180)), s, 0.1, 0.03, c)
	mb.sway_fn = Callable()
	mb.segment("solid", Vector3(-w * 0.5 - 0.05, h - drop, reach), Vector3(w * 0.5 + 0.05, h - drop, reach), 0.03, TIMBER_D, 6)
	mb.segment("solid", Vector3(-w * 0.5 - 0.05, h, 0), Vector3(w * 0.5 + 0.05, h, 0), 0.04, TIMBER_D, 6)
	if cfg.get("posts", true):
		for sx in [-1.0, 1.0]:
			mb.cyl("solid", _xf(sx * w * 0.5, 0, 0), 0.05, 0.045, h, 6, Brand.TIMBER)
			mb.cyl("solid", _xf(sx * w * 0.5, 0, reach), 0.045, 0.04, h - drop, 6, Brand.TIMBER)


# =====================================================================================
# Street furniture
# =====================================================================================
## Black iron street lamp. cfg: height, light (bool -> adds an OmniLight3D)
static func lamp(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var h: float = cfg.get("height", 3.0)
	mb.cyl("solid", _xf(0, 0, 0), 0.2, 0.15, 0.12, 8, IRON, true, true)
	mb.cyl("solid", _xf(0, 0.12, 0), 0.13, 0.07, 0.42, 8, IRON, true, true)
	mb.cyl("solid", _xf(0, 0.5, 0), 0.055, 0.045, h - 1.0, 6, IRON, false)
	mb.cyl("solid", _xf(0, h - 0.62, 0), 0.08, 0.1, 0.12, 8, IRON, true, true)
	var ly := h - 0.5
	mb.box("solid", _xf(0, ly, 0), Vector3(0.3, 0.05, 0.3), IRON)
	mb.box("glow", _xf(0, ly + 0.2, 0), Vector3(0.21, 0.32, 0.21), Color("ffd98a"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.box("solid", _xf(sx * 0.12, ly + 0.2, sz * 0.12), Vector3(0.035, 0.38, 0.035), IRON)
	mb.cyl("solid", _xf(0, ly + 0.38, 0, Vector3(0, 45, 0)), 0.27, 0.05, 0.2, 4, IRON, true, true)
	mb.sphere("solid", _xf(0, ly + 0.62, 0), 0.05, IRON, 5, 3)
	mb.collider(_xf(0, h * 0.5, 0), Vector3(0.3, h, 0.3))
	var node := mb.to_node("Lamp")
	if cfg.get("light", false):
		var l := OmniLight3D.new()
		l.position = Vector3(0, ly + 0.2, 0)
		l.light_color = Color("ffd59a")
		l.omni_range = 6.0
		l.light_energy = 1.2
		node.add_child(l)
	return node


## Slatted timber bench with iron ends. cfg: length, seed
static func bench(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var L: float = cfg.get("length", 1.8)
	for sx in [-1.0, 1.0]:
		var x: float = sx * (L * 0.5 - 0.12)
		mb.box("solid", _xf(x, 0.22, 0.17), Vector3(0.06, 0.44, 0.06), IRON, 0.01)
		mb.box("solid", _xf(x, 0.42, -0.16, Vector3(-12, 0, 0)), Vector3(0.06, 0.86, 0.06), IRON, 0.01)
		mb.box("solid", _xf(x, 0.43, 0.0), Vector3(0.05, 0.05, 0.46), IRON)
		mb.box("solid", _xf(x, 0.66, 0.02), Vector3(0.08, 0.05, 0.48), TIMBER_D, 0.015)
		mb.box("solid", _xf(x, 0.55, 0.19), Vector3(0.04, 0.2, 0.04), IRON)
	for i in 4:
		mb.box("solid", _xf(0, 0.47, 0.17 - i * 0.105), Vector3(L, 0.045, 0.09), _jit(Brand.TIMBER, r, 0.04), 0.015)
	for i in 3:
		var y := 0.6 + i * 0.12
		mb.box("solid", _xf(0, y, -0.2 - (y - 0.5) * 0.21, Vector3(-12, 0, 0)), Vector3(L, 0.09, 0.04), _jit(Brand.TIMBER, r, 0.04), 0.015)
	mb.collider(_xf(0, 0.45, 0), Vector3(L, 0.9, 0.5))
	return mb.to_node("Bench")


## Round café table with chairs and an optional striped parasol.
## cfg: seed, chairs (int), parasol (bool), parasol_style ("teal","coral","gold"), parasol_radius
static func cafe_table(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var chairs: int = cfg.get("chairs", r.randi_range(2, 4))
	mb.cyl("solid", _xf(0, 0, 0), 0.26, 0.2, 0.05, 10, IRON, true, true)
	mb.cyl("solid", _xf(0, 0.05, 0), 0.04, 0.04, 0.68, 6, IRON, false)
	mb.cyl("solid", _xf(0, 0.72, 0), 0.42, 0.42, 0.05, 14, TIMBER_D, true)
	mb.collider(_xf(0, 0.38, 0), Vector3(0.8, 0.76, 0.8))
	var a0 := r.randf() * TAU
	for i in chairs:
		var a := a0 + TAU * i / chairs + r.randf_range(-0.2, 0.2)
		var p := Vector3(sin(a), 0, cos(a)) * 0.68
		var t := Transform3D(Basis(Vector3.UP, atan2(-p.x, -p.z)), p)
		mb.box("solid", t * _xf(0, 0.46, 0), Vector3(0.42, 0.05, 0.42), Brand.TIMBER, 0.015)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				mb.box("solid", t * _xf(sx * 0.17, 0.22, sz * 0.17), Vector3(0.035, 0.44, 0.035), IRON)
			mb.box("solid", t * _xf(sx * 0.17, 0.7, -0.2, Vector3(-6, 0, 0)), Vector3(0.035, 0.5, 0.035), IRON)
		for k in 2:
			mb.box("solid", t * _xf(0, 0.68 + k * 0.17, -0.21 - k * 0.015, Vector3(-6, 0, 0)), Vector3(0.4, 0.08, 0.03), Brand.TIMBER, 0.01)
		mb.collider(t * _xf(0, 0.45, 0), Vector3(0.45, 0.9, 0.45))
	if cfg.get("parasol", true):
		var style: String = cfg.get("parasol_style", ["teal", "coral"][r.randi() % 2])
		var c1: Color = {"teal": Brand.TEAL, "coral": Brand.CORAL, "gold": Brand.GOLD, "cream": Color("f1e9d6")}.get(style, Brand.TEAL)
		var R: float = cfg.get("parasol_radius", 1.2)
		mb.cyl("solid", _xf(0, 0.77, 0), 0.025, 0.025, 1.65, 6, CANVAS.darkened(0.1), false)
		var y0 := 2.05
		var y1 := 2.45
		var segs := 8
		mb.sway_fn = func(p: Vector3) -> float: return Vector2(p.x, p.z).length() / R
		for i in segs:
			var u0 := TAU * i / segs
			var u1 := TAU * (i + 1) / segs
			var c: Color = c1 if i % 2 == 0 else CANVAS
			var e0 := Vector3(cos(u0) * R, y0, sin(u0) * R)
			var e1 := Vector3(cos(u1) * R, y0, sin(u1) * R)
			var apex := Vector3(0, y1, 0)
			var mid := (e0 + e1) * 0.5
			var nt := (e1 - e0).cross(apex - e0).normalized()
			if nt.y < 0: nt = -nt
			mb.face("cloth", Transform3D.IDENTITY, [apex, e0, e1], nt, c)
			var dn := Vector3(0, -0.05, 0)
			mb.face("cloth", Transform3D.IDENTITY, [apex + dn, e0 + dn, e1 + dn], -nt, c.darkened(0.1))
			mb.face("cloth", Transform3D.IDENTITY, [e0, e1, e1 + dn, e0 + dn], Vector3(mid.x, 0, mid.z).normalized(), c)
			# scalloped valance flap
			var fl := Vector3(0, -0.16, 0)
			var o := Vector3(mid.x, 0, mid.z).normalized() * 0.01
			mb.face("cloth", Transform3D.IDENTITY, [e0 + o, e1 + o, e1 + o + fl, mid + o + fl * 1.5, e0 + o + fl], Vector3(mid.x, 0, mid.z).normalized(), c)
			mb.face("cloth", Transform3D.IDENTITY, [e0 - o, e1 - o, e1 - o + fl, mid - o + fl * 1.5, e0 - o + fl], -Vector3(mid.x, 0, mid.z).normalized(), c.darkened(0.15))
		mb.sway_fn = Callable()
		mb.sphere("solid", _xf(0, y1 + 0.03, 0), 0.05, TIMBER_D, 5, 3)
	return mb.to_node("CafeTable")


## Stone planter box with flowers. cfg: seed, length, width, height, flowers (Array of Color), density
static func planter(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var L: float = cfg.get("length", 1.6)
	var W: float = cfg.get("width", 0.75)
	var H: float = cfg.get("height", 0.55)
	var pal: Array = cfg.get("flowers", [FLOWERS[r.randi() % 6], FLOWERS[r.randi() % 6], FLOWERS[3]])
	var dens: float = cfg.get("density", 1.0)
	mb.box("solid", _xf(0, (H - 0.08) * 0.5, 0), Vector3(L, H - 0.08, W), Brand.STONE, 0.05)
	mb.box("solid", _xf(0, H - 0.05, 0), Vector3(L + 0.1, 0.1, W + 0.1), STONE_L, 0.03)
	mb.box("solid", _xf(0, H - 0.04, 0), Vector3(L - 0.16, 0.06, W - 0.16), Brand.SOIL)
	var n := clampi(int(L * W * 16.0 * dens), 3, 22)
	mb.sway = 0.25
	for i in n:
		var p := Vector3(r.randf_range(-L * 0.42, L * 0.42), H + 0.05, r.randf_range(-W * 0.38, W * 0.38))
		var s := r.randf_range(0.13, 0.2)
		mb.sphere("leaf", _xf(p.x, p.y + s * 0.4, p.z, Vector3(0, r.randf() * 90, 0), Vector3(1, 0.8, 1)), s, _leaf(r), 5, 3)
		for k in r.randi_range(1, 3):
			mb.sphere("leaf", _xf(p.x + r.randf_range(-s, s) * 0.7, p.y + s * 0.95, p.z + r.randf_range(-s, s) * 0.7), r.randf_range(0.04, 0.06), pal[r.randi() % pal.size()], 4, 3)
	mb.sway = 0.0
	mb.collider(_xf(0, H * 0.5, 0), Vector3(L + 0.1, H, W + 0.1))
	return mb.to_node("Planter")


# =====================================================================================
# Stairs, walls, fences
# =====================================================================================
## Stone stair climbing towards -Z (bottom step at +Z). Footprint depth = steps*run.
## cfg: seed, steps, width, rise, run, cheeks (bool), railing ("timber","iron","none")
static func stair(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var n: int = cfg.get("steps", 6)
	var w: float = cfg.get("width", 2.0)
	var rise: float = cfg.get("rise", 0.18)
	var run: float = cfg.get("run", 0.32)
	var cheeks: bool = cfg.get("cheeks", true)
	var rail: String = cfg.get("railing", "timber")
	var L := n * run
	var H := n * rise
	var cw := 0.32
	for i in n:
		var z := L * 0.5 - (i + 0.5) * run
		var hh := (i + 1) * rise
		mb.box("solid", _xf(0, hh * 0.5, z), Vector3(w, hh, run + 0.02), _jit(STONE_L, r, 0.04), 0.03)
		if cheeks:
			for s in [-1.0, 1.0]:
				mb.box("solid", _xf(s * (w * 0.5 + cw * 0.5), (hh + 0.22) * 0.5, z), Vector3(cw, hh + 0.22, run + 0.02), _jit(Brand.STONE, r, 0.05), 0.04)
	var ang := atan2(H, L)
	var slen := sqrt(L * L + H * H)
	mb.collider(Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0, H * 0.5, 0) + Vector3(0, -cos(ang), -sin(ang)) * 0.1), Vector3(w, 0.2, slen))
	if cheeks:
		for s in [-1.0, 1.0]:
			mb.collider(_xf(s * (w * 0.5 + cw * 0.5), (H + 0.22) * 0.5, 0), Vector3(cw, H + 0.22, L))
	if rail != "none":
		var col := IRON if rail == "iron" else TIMBER_D
		for s in [-1.0, 1.0]:
			var x: float = s * (w * 0.5 + (cw * 0.5 if cheeks else -0.08))
			var base_off := 0.22 if cheeks else 0.0
			var pts := []
			var np := maxi(2, int(L / 1.2) + 1)
			for k in np:
				var f := float(k) / (np - 1)
				var z := L * 0.5 - 0.15 - f * (L - 0.3)
				var i := clampi(int((L * 0.5 - z) / run), 0, n - 1)
				var y := (i + 1) * rise + base_off
				var pr := 0.06 if rail == "timber" else 0.03
				mb.box("solid", _xf(x, y + 0.45, z), Vector3(pr * 2, 0.9, pr * 2), col, 0.015 if rail == "timber" else 0.0)
				pts.append(Vector3(x, y + 0.92, z))
			mb.segment("solid", pts[0], pts[-1], 0.04 if rail == "timber" else 0.025, col, 6)
			if rail == "iron":
				for i in n:
					var z := L * 0.5 - (i + 0.5) * run
					var f := clampf((L * 0.5 - 0.15 - z) / (L - 0.3), 0, 1)
					var top: Vector3 = (pts[0] as Vector3).lerp(pts[-1], f)
					mb.box("solid", _xf(x, ((i + 1) * rise + base_off + top.y) * 0.5, z), Vector3(0.025, top.y - (i + 1) * rise - base_off, 0.025), IRON)
	return mb.to_node("Stair")


## Dry-stone retaining wall along a polyline (points y = wall base). Front face is to
## the right-hand side of travel (+Z when walking towards +X).
## cfg: seed, thickness, cap (bool), course (approx course height)
static func retaining_wall(points: PackedVector3Array, height: float, cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var th: float = cfg.get("thickness", 0.55)
	var cap: bool = cfg.get("cap", true)
	var courses := maxi(1, int(round(height / cfg.get("course", 0.42))))
	var ch := height / courses
	for si in points.size() - 1:
		var a := points[si]
		var b := points[si + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		var slen := dir.length()
		if slen < 0.01:
			continue
		dir /= slen
		var t := Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), a)
		var x0 := -th * 0.5 if si == 0 else th * 0.5
		var x1 := slen + th * 0.5
		mb.box("solid", t * _xf((x0 + x1) * 0.5, height * 0.5, -0.04), Vector3(x1 - x0, height, th - 0.1), STONE_D.darkened(0.25))
		for c in courses:
			var x := x0 - r.randf_range(0.0, 0.5)
			while x < x1:
				var bl := r.randf_range(0.55, 1.05)
				var xa := maxf(x, x0)
				var xb := minf(x + bl, x1)
				if xb - xa > 0.12:
					var bh := ch - 0.04 + r.randf_range(-0.03, 0.02)
					var col := _jit(Brand.STONE, r, 0.07)
					col = col.lerp(Color("b5ad9c") if r.randf() < 0.5 else Color("98a3a6"), r.randf() * 0.4)
					mb.box("solid", t * _xf((xa + xb) * 0.5, c * ch + ch * 0.5, r.randf_range(-0.03, 0.03)), Vector3(xb - xa - 0.04, bh, th + r.randf_range(-0.04, 0.04)), col, 0.07)
				x += bl
		if cap:
			var x := x0
			while x < x1:
				var bl := minf(r.randf_range(0.8, 1.2), x1 - x)
				if bl > 0.1:
					mb.box("solid", t * _xf(x + bl * 0.5, height + 0.06, 0.02), Vector3(bl - 0.03, 0.13, th + 0.12), _jit(STONE_L, r, 0.04), 0.04)
				x += bl
		mb.collider(t * _xf(slen * 0.5, height * 0.5, 0), Vector3(slen + th, height + 0.12, th))
	return mb.to_node("RetainingWall")


## Fence along a polyline. style: "rope" (thick posts + sagging rope), "timber"
## (posts + two rails), "iron" (posts, rails, balusters). cfg: seed, height, spacing
static func fence(points: PackedVector3Array, style := "rope", cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	_fence(mb, points, style, cfg)
	return mb.to_node("Fence")


static func _fence(mb: MeshUtil, points: PackedVector3Array, style: String, cfg: Dictionary) -> void:
	var r := _rng(cfg)
	var h: float = cfg.get("height", {"rope": 0.95, "timber": 1.0, "iron": 1.0}.get(style, 1.0))
	var spacing: float = cfg.get("spacing", {"rope": 2.0, "timber": 1.8, "iron": 1.6}.get(style, 1.8))
	var posts := []
	for si in points.size() - 1:
		var a := points[si]
		var b := points[si + 1]
		var n := maxi(1, int(round(a.distance_to(b) / spacing)))
		for k in n:
			posts.append(a.lerp(b, float(k) / n))
		mb.collider(Transform3D(Basis(Vector3.UP, atan2(b.x - a.x, b.z - a.z)), (a + b) * 0.5 + Vector3(0, h * 0.5, 0)), Vector3(0.15, h, a.distance_to(b)))
	posts.append(points[points.size() - 1])
	for i in posts.size():
		var p: Vector3 = posts[i]
		match style:
			"rope":
				mb.cyl("solid", _xf(p.x, p.y, p.z), 0.1, 0.09, h, 8, _jit(Color("5e4430"), r, 0.04))
				mb.sphere("solid", _xf(p.x, p.y + h, p.z, Vector3.ZERO, Vector3(1, 0.5, 1)), 0.095, Color("4e3828"), 6, 3)
				mb.cyl("solid", _xf(p.x, p.y + h - 0.2, p.z), 0.11, 0.11, 0.06, 8, ROPE, false)
			"timber":
				mb.box("solid", _xf(p.x, p.y + h * 0.5, p.z), Vector3(0.12, h, 0.12), TIMBER_D, 0.02)
			_:
				mb.box("solid", _xf(p.x, p.y + h * 0.5, p.z), Vector3(0.06, h, 0.06), IRON)
				mb.sphere("solid", _xf(p.x, p.y + h + 0.02, p.z), 0.045, IRON, 5, 3)
		if i == 0:
			continue
		var q: Vector3 = posts[i - 1]
		match style:
			"rope":
				var segs := 6
				var prev := q + Vector3(0, h - 0.2, 0)
				for k in range(1, segs + 1):
					var f := float(k) / segs
					var cur := q.lerp(p, f) + Vector3(0, h - 0.2 - sin(f * PI) * 0.22, 0)
					mb.segment("solid", prev, cur, 0.028, ROPE, 4)
					prev = cur
			"timber":
				for y in [h * 0.4, h * 0.82]:
					mb.segment("solid", q + Vector3(0, y, 0), p + Vector3(0, y, 0), 0.045, Brand.TIMBER, 4)
			_:
				for y in [0.12, h - 0.06]:
					mb.segment("solid", q + Vector3(0, y, 0), p + Vector3(0, y, 0), 0.025, IRON, 4)
				var nb := int(q.distance_to(p) / 0.16)
				for k in range(1, nb):
					var m := q.lerp(p, float(k) / nb)
					mb.box("solid", _xf(m.x, m.y + h * 0.5, m.z), Vector3(0.022, h - 0.12, 0.022), IRON)


# =====================================================================================
# Waterfront
# =====================================================================================
## Timber dock on posts, running along Z. Origin = water level at footprint centre;
## deck sits at deck_height. cfg: seed, length, width, deck_height, water_depth, rope (bool), ladder (bool)
static func dock(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var L: float = cfg.get("length", 6.0)
	var W: float = cfg.get("width", 2.6)
	var dh: float = cfg.get("deck_height", 0.6)
	var depth: float = cfg.get("water_depth", 1.4)
	var pw := 0.22
	var n := int(L / pw)
	for i in n:
		var z := (i + 0.5) * (L / n) - L * 0.5
		mb.box("solid", _xf(r.randf_range(-0.02, 0.02), dh - 0.04 + r.randf_range(-0.008, 0.008), z), Vector3(W + r.randf_range(-0.04, 0.04), 0.07, L / n - 0.025), _jit(WEATHERED, r, 0.06), 0.012)
	for s in [-1.0, 0.0, 1.0]:
		mb.box("solid", _xf(s * (W * 0.5 - 0.15), dh - 0.16, 0), Vector3(0.12, 0.18, L), TIMBER_D)
	var np := maxi(2, int(L / 2.0) + 1)
	var tops := [[], []]
	for k in np:
		var z := (float(k) / (np - 1) - 0.5) * (L - 0.2)
		mb.box("solid", _xf(0, dh - 0.25, z), Vector3(W + 0.1, 0.16, 0.14), TIMBER_D)
		for si in 2:
			var x := (W * 0.5 + 0.08) * (1.0 if si == 1 else -1.0)
			var top := dh + (0.85 if cfg.get("rope", true) else 0.1)
			mb.cyl("solid", _xf(x, -depth, z), 0.13, 0.12, top + depth, 8, _jit(Color("5e4430"), r, 0.04))
			mb.sphere("solid", _xf(x, top, z, Vector3.ZERO, Vector3(1, 0.45, 1)), 0.12, Color("4e3828"), 6, 3)
			tops[si].append(Vector3(x, top - 0.18, z))
			mb.collider(_xf(x, top * 0.5, z), Vector3(0.26, top, 0.26))
	if cfg.get("rope", true):
		for si in 2:
			for k in range(1, np):
				var a: Vector3 = tops[si][k - 1]
				var b: Vector3 = tops[si][k]
				var prev := a
				for j in range(1, 7):
					var f := j / 6.0
					var cur := a.lerp(b, f) + Vector3(0, -sin(f * PI) * 0.25, 0)
					mb.segment("solid", prev, cur, 0.03, ROPE, 4)
					prev = cur
	if cfg.get("ladder", true):
		var lz := L * 0.5 + 0.06
		for s in [-1.0, 1.0]:
			mb.box("solid", _xf(s * 0.25, dh - 0.6, lz), Vector3(0.06, 1.3, 0.06), TIMBER_D)
		for k in 4:
			mb.box("solid", _xf(0, dh - 0.2 - k * 0.3, lz), Vector3(0.5, 0.05, 0.05), TIMBER_D)
	mb.collider(_xf(0, dh - 0.1, 0), Vector3(W, 0.2, L))
	return mb.to_node("Dock")


## Lofted wooden rowboat, bow at +Z. Origin = waterline centre.
## cfg: seed, length, beam, paint (Color), oars (bool)
static func rowboat(cfg := {}) -> Node3D:
	var mb := MeshUtil.new()
	var r := _rng(cfg)
	var L: float = cfg.get("length", 3.0)
	var B: float = cfg.get("beam", 1.15)
	var paint: Color = cfg.get("paint", [Brand.TEAL, Color("3e6f8e"), Color("4f7b5a"), TIMBER_D, Brand.CORAL][r.randi() % 5])
	var N := 10
	var M := 3
	var thick := 0.06
	var outer := []
	var inner := []
	for i in N + 1:
		var u := float(i) / N
		var z := (u - 0.5) * L
		var hb := maxf(B * 0.5 * pow(maxf(sin(PI * (0.2 + 0.8 * u)), 0.0), 0.65), 0.012)
		var kb := -0.2 + 0.2 * pow(u, 4) + 0.05 * pow(1.0 - u, 2)
		var sh := 0.26 + 0.14 * pow(u, 3) + 0.05 * pow(1.0 - u, 2)
		var ro := []
		var ri := []
		for j in range(-M, M + 1):
			var a := absf(j) / float(M) * PI * 0.5
			var sgn := 1.0 if j >= 0 else -1.0
			var x := sgn * hb * pow(cos(a), 0.55)
			var y := sh - (sh - kb) * sin(a)
			ro.append(Vector3(x, y, z))
			var hbi := maxf(hb - thick, 0.004)
			ri.append(Vector3(sgn * hbi * pow(cos(a), 0.55), sh - (sh - kb - thick) * sin(a), z + (thick if i == 0 else 0.0)))
		# reverse so the ring runs left gunwale -> keel -> right gunwale
		ro.reverse()
		ri.reverse()
		outer.append(ro)
		inner.append(ri)
	var I := Transform3D.IDENTITY
	for i in N:
		for k in 2 * M:
			var q := [outer[i][k], outer[i][k + 1], outer[i + 1][k + 1], outer[i + 1][k]]
			var c: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
			var nrm := ((q[1] - q[0]) as Vector3).cross(q[3] - q[0]).normalized()
			if nrm.dot(Vector3(c.x, c.y - 0.1, 0)) < 0: nrm = -nrm
			var band := mini(k, 2 * M - 1 - k)
			var col := TIMBER_D if band == 0 else (paint if band < M - 1 else paint.darkened(0.25))
			mb.face("solid", I, q, nrm, col)
			var qi := [inner[i][k], inner[i][k + 1], inner[i + 1][k + 1], inner[i + 1][k]]
			var ni := ((qi[1] - qi[0]) as Vector3).cross(qi[3] - qi[0]).normalized()
			if ni.dot(Vector3(c.x, c.y - 0.1, 0)) > 0: ni = -ni
			mb.face("solid", I, qi, ni, TIMBER_L if band % 2 == 0 else Brand.TIMBER)
		for e in [0, 2 * M]:
			mb.face("solid", I, [outer[i][e], outer[i + 1][e], inner[i + 1][e], inner[i][e]], Vector3.UP, TIMBER_D)
	# transom
	mb.face("solid", I, outer[0], Vector3.FORWARD, paint.darkened(0.1))
	mb.face("solid", I, inner[0], Vector3.BACK, Brand.TIMBER)
	mb.face("solid", I, [outer[0][0], outer[0][2 * M], inner[0][2 * M], inner[0][0]], Vector3.UP, TIMBER_D)
	# thwarts + oars
	for u in [0.3, 0.62]:
		var i := int(u * N)
		var hw: float = (inner[i][0] as Vector3).x
		var y: float = (inner[i][0] as Vector3).y - 0.14
		mb.box("solid", _xf(0, y, (u - 0.5) * L), Vector3(absf(hw) * 2.0, 0.05, 0.24), TIMBER_L, 0.012)
	if cfg.get("oars", true):
		for s in [-1.0, 1.0]:
			var a := Vector3(s * 0.25, 0.2, -L * 0.3)
			var b := Vector3(s * 0.12, 0.22, L * 0.28)
			mb.segment("solid", a, b, 0.025, TIMBER_L, 5)
			mb.box("solid", Transform3D(Basis.looking_at(b - a), b), Vector3(0.14, 0.02, 0.45), TIMBER_L, 0.008)
	mb.collider(_xf(0, 0.05, 0), Vector3(B, 0.5, L))
	return mb.to_node("Rowboat")
