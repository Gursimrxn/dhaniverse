class_name RiverKit
## River dressing kit: stylized boulders, stepped waterfalls, foam, mist, fish, ripple rings.
## Everything is procedural (no imported assets) and cached per variant, so dressing a
## whole river costs a handful of meshes + materials. Compatibility/WebGL2 safe.

const ROCK_SHADER := preload("res://shaders/rock.gdshader")
const FALL_SHADER := preload("res://shaders/waterfall.gdshader")
const FOAM_SHADER := preload("res://shaders/foam.gdshader")
const FISH_SHADER := preload("res://shaders/fish.gdshader")

## Variant shapes: [scale xyz, noise amp, noise freq, superellipse power (1 = round)]
const VARIANTS := [
	[Vector3(1.0, 0.8, 0.92), 0.1, 0.8, 1.0],     # 0 round boulder
	[Vector3(1.2, 0.52, 1.0), 0.08, 0.9, 0.8],    # 1 flat slab
	[Vector3(0.88, 1.05, 0.82), 0.11, 0.8, 0.9],  # 2 tall boulder
	[Vector3(1.0, 0.7, 1.05), 0.16, 1.1, 1.0],    # 3 lumpy
	[Vector3(1.3, 0.62, 0.95), 0.06, 0.9, 0.55],  # 4 ledge block (rounded box)
]
const VARIANT_COUNT := 5

static var _meshes := {}
static var _hulls := {}
static var _mats := {}

# --- rocks ---------------------------------------------------------------------------

static func rock_mesh(variant: int) -> ArrayMesh:
	variant = posmod(variant, VARIANT_COUNT)
	if _meshes.has(variant): return _meshes[variant]
	var v: Array = VARIANTS[variant]
	var sc: Vector3 = v[0]
	var noise := FastNoiseLite.new()
	noise.seed = variant * 17 + 3
	noise.frequency = v[2]
	noise.fractal_octaves = 2
	var sphere := SphereMesh.new()
	sphere.radial_segments = 30
	sphere.rings = 16
	var src: PackedVector3Array = sphere.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = sphere.get_mesh_arrays()[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var d: Vector3 = src[i].normalized()
		if v[3] != 1.0:   # rounded box: push the sphere towards its bounding cube
			d = Vector3(signf(d.x) * pow(absf(d.x), v[3]), signf(d.y) * pow(absf(d.y), v[3]), signf(d.z) * pow(absf(d.z), v[3]))
		var p: Vector3 = d * (1.0 + noise.get_noise_3dv(src[i].normalized()) * v[1] * 2.0) * sc
		p.y = maxf(p.y, -sc.y * 0.55)   # flat-ish base so rocks sit
		st.add_vertex(p.snappedf(0.0001))
	st.index()   # merges UV-seam / pole duplicates -> smooth normals everywhere
	st.generate_normals()
	var m := st.commit()
	_meshes[variant] = m
	_hulls[variant] = (m.create_convex_shape(true, true) as ConvexPolygonShape3D).points
	return m

static func rock_material(water_level: float, moss := 0.5) -> ShaderMaterial:
	var key := Vector2(water_level, moss)
	if _mats.has(key): return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("water_level", water_level)
	m.set_shader_parameter("moss_amount", moss)
	_mats[key] = m
	return m

## Random-but-deterministic orientation + squash for one rock of `size` metres radius.
static func _rock_basis(size: float, seed: int, tilt := 0.18) -> Basis:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var b := Basis(Vector3.UP, r.randf() * TAU)
	b = Basis(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized(), r.randf_range(-tilt, tilt)) * b
	return b * Basis.from_scale(Vector3(r.randf_range(0.85, 1.15), r.randf_range(0.85, 1.12), r.randf_range(0.85, 1.15)) * size)

static func _hull(variant: int, b: Basis) -> ConvexPolygonShape3D:
	rock_mesh(variant)
	var pts := PackedVector3Array()
	for p in _hulls[posmod(variant, VARIANT_COUNT)]: pts.append(b * p)
	var s := ConvexPolygonShape3D.new()
	s.points = pts
	return s

## One boulder with convex collision. `scale` ~ radius in metres. Position it yourself.
static func rock(variant: int, scale: float, seed: int, water_level := 0.0, moss := 0.5) -> Node3D:
	var b := _rock_basis(scale, seed)
	var body := StaticBody3D.new()
	body.name = "Rock"
	var mi := MeshInstance3D.new()
	mi.mesh = rock_mesh(variant)
	mi.material_override = rock_material(water_level, moss)
	mi.transform = Transform3D(b, Vector3.ZERO)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _hull(variant, b)
	body.add_child(cs)
	return body

## Scatter many rocks with one MultiMesh per variant + one static body.
## points_and_sizes: [[Vector3 centre, float size(, int variant)], ...]
## Rocks that cross `water_level` also get a foam ripple ring (one MultiMesh).
static func scatter_rocks(parent: Node, points_and_sizes: Array, water_level: float, moss := 0.5) -> Node3D:
	var root := Node3D.new()
	root.name = "Rocks"
	var body := StaticBody3D.new()
	root.add_child(body)
	var groups := {}
	var rings: Array = []
	for i in points_and_sizes.size():
		var e: Array = points_and_sizes[i]
		var pos: Vector3 = e[0]
		var size: float = e[1]
		var variant: int = e[2] if e.size() > 2 and e[2] >= 0 else int(hash(pos.snappedf(0.1))) % 4
		var wl: float = e[3] if e.size() > 3 else water_level   # per-rock level on sloping rivers
		var b := _rock_basis(size, int(hash(pos)) + i)
		groups.get_or_add(variant, []).append(Transform3D(b, pos))
		var cs := CollisionShape3D.new()
		cs.shape = _hull(variant, b)
		cs.position = pos
		body.add_child(cs)
		# water-line cross-section of the (squashed) rock -> ripple ring
		var sc: Vector3 = VARIANTS[variant][0]
		var hy := size * sc.y
		var dy := wl - pos.y
		if dy > -hy * 0.8 and dy < hy * 0.7:
			var rr := size * maxf(sc.x, sc.z) * sqrt(maxf(0.15, 1.0 - pow(dy / hy, 2.0)))
			rings.append(Transform3D(Basis.from_scale(Vector3.ONE * rr / 0.45), Vector3(pos.x, wl + 0.03, pos.z)))
	for variant in groups:
		root.add_child(_multi(rock_mesh(variant), groups[variant], rock_material(water_level, moss), true))
	if not rings.is_empty():
		root.add_child(_multi(_disc(), rings, foam_material(0.45, 0.0, 0.9, 0.85), false))
	parent.add_child(root)
	return root

static func _multi(mesh: Mesh, xforms: Array, mat: Material, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size(): mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

# --- foam / ripples --------------------------------------------------------------------

static func _disc() -> PlaneMesh:
	if _meshes.has("disc"): return _meshes["disc"]
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	_meshes["disc"] = pm
	return pm

static func foam_material(inner: float, churn: float, rings: float, opacity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOAM_SHADER
	m.set_shader_parameter("inner", inner)
	m.set_shader_parameter("churn", churn)
	m.set_shader_parameter("rings", rings)
	m.set_shader_parameter("opacity", opacity)
	m.render_priority = 2
	return m

## Foam ring hugging something of `radius` metres that pokes through the water at `pos`.
static func ripple_ring(pos: Vector3, radius := 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _disc()
	mi.material_override = foam_material(0.45, 0.0, 0.9, 0.85)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.03, 0)
	mi.scale = Vector3.ONE * radius / 0.45
	return mi

# --- waterfall -----------------------------------------------------------------------

## cfg: {top: Vector3 (lip centre), bottom: Vector3 (pool surface below), width: float,
##       steps: int, seed: int, water_level (opt, defaults bottom.y)}
static func waterfall(cfg: Dictionary) -> Node3D:
	var top: Vector3 = cfg.top
	var bottom: Vector3 = cfg.bottom
	var width: float = cfg.get("width", 3.0)
	var steps: int = maxi(1, cfg.get("steps", 3))
	var seed: int = cfg.get("seed", 1)
	var wl: float = cfg.get("water_level", bottom.y)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var root := Node3D.new()
	root.name = "Waterfall"
	var fwd := Vector3(bottom.x - top.x, 0, bottom.z - top.z)
	var run := fwd.length() / steps
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := Vector3.UP.cross(fwd).normalized()
	var drop := (top.y - bottom.y) / steps

	for i in steps:
		var lip := top + fwd * run * i - Vector3.UP * drop * i
		var land_y := lip.y - drop
		var w := width * (1.0 + 0.12 * i)
		# ledge: rounded blocks whose front face is the lip, tops flush with the water
		var n := maxi(2, ceili(w / 1.6) + 1)
		for k in n:
			var s := r.randf_range(0.85, 1.05) * clampf(drop * 0.75, 0.55, 1.2)
			var sc: Vector3 = VARIANTS[4][0]
			var t := (float(k) / (n - 1) - 0.5) * (w + 0.6)
			var rk := rock(4, s, seed * 31 + i * 7 + k, lip.y, 0.35)
			rk.position = lip + side * t - fwd * (sc.z * s * 0.9) - Vector3.UP * (sc.y * s * 0.8 + 0.06)
			root.add_child(rk)
			# fill below so the face reads as one cliff down to the next ledge
			var low := rock(4, s * 1.05, seed * 53 + i * 11 + k, land_y, 0.2)
			low.position = rk.position - Vector3.UP * drop * 0.75 + fwd * 0.08
			root.add_child(low)
		# chunky mossy boulders framing each step
		for sgn in [-1.0, 1.0]:
			var s2 := r.randf_range(0.9, 1.3) * maxf(1.0, drop * 0.8)
			var bk := rock([0, 2, 3][r.randi() % 3], s2, seed * 97 + i * 13 + int(sgn), wl, 0.75)
			bk.position = lip + side * sgn * (w * 0.5 + s2 * 0.75) + fwd * run * 0.35 - Vector3.UP * drop * 0.2
			root.add_child(bk)
		# two layered ribbons: back sheet + lighter front veil
		var throw := clampf(run * 0.45, 0.3, 1.2)
		root.add_child(_ribbon(lip + fwd * 0.05, fwd, side, w, throw, drop, float(seed + i), 1.6, 1.0))
		root.add_child(_ribbon(lip + fwd * 0.12 + Vector3.UP * 0.02, fwd, side, w * 0.8, throw * 1.15, drop, float(seed + i) + 7.3, 2.1, 0.75))
		# shallow sheet sliding across this ledge from the landing above to the lip
		if i > 0:
			root.add_child(_ribbon(lip - fwd * run * 0.95 + Vector3.UP * 0.03, fwd, side, w * 0.96, run * 0.95, -0.15, float(seed + i) + 3.7, 1.2, 1.0))
		# impact foam + splash at the landing
		var land := lip + fwd * throw * 1.1
		land.y = land_y + 0.06
		var big := i == steps - 1
		var foam := MeshInstance3D.new()
		foam.mesh = _disc()
		foam.material_override = foam_material(0.0, 1.0, 0.7 if big else 0.2, 0.95)
		foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if big:
			foam.transform = Transform3D(Basis(side * w * 0.95, Vector3.UP, fwd * w * 0.8), land + fwd * w * 0.2)
		else:
			foam.transform = Transform3D(Basis(side * w * 0.55, Vector3.UP, fwd * run * 0.5), land)
		root.add_child(foam)
		root.add_child(_spray(land, side, w, 40 if big else 18))
		if big: root.add_child(_mist(land + fwd * 0.4, side, w))
	return root

## Falling sheet: parabola from lip, throw metres forward, drop metres down
## (drop = -0.15 gives a flat sheet, used for water sliding across a ledge).
static func _ribbon(lip: Vector3, fwd: Vector3, side: Vector3, w: float, throw: float, drop: float, seed: float, speed: float, alpha: float) -> MeshInstance3D:
	const NU := 10
	const NV := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.0
	var prev := lip
	for j in NV + 1:
		var v := float(j) / NV
		var c := lip + fwd * throw * sqrt(v) - Vector3.UP * (drop + 0.15) * v * v * 0.6 - Vector3.UP * (drop + 0.15) * v * 0.4
		length += c.distance_to(prev)
		prev = c
	for j in NV + 1:
		var v := float(j) / NV
		var c := lip + fwd * throw * sqrt(v) - Vector3.UP * (drop + 0.15) * v * v * 0.6 - Vector3.UP * (drop + 0.15) * v * 0.4
		var ww := w * (1.0 + v * 0.18)
		for k in NU + 1:
			var u := float(k) / NU
			st.set_uv(Vector2(u, v))
			st.set_uv2(Vector2(length, 0))
			st.set_normal(fwd)
			st.add_vertex(c + side * (u - 0.5) * ww + fwd * sin(u * PI) * 0.06)
	for j in NV:
		for k in NU:
			var a := j * (NU + 1) + k
			st.add_index(a); st.add_index(a + 1); st.add_index(a + NU + 1)
			st.add_index(a + 1); st.add_index(a + NU + 2); st.add_index(a + NU + 1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = FALL_SHADER
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("speed", speed)
	m.render_priority = 1 if alpha >= 1.0 else 3
	mi.material_override = m
	m.set_shader_parameter("opacity", alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _soft_mat() -> StandardMaterial3D:
	if _mats.has("soft"): return _mats["soft"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = gt
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = 4
	_mats["soft"] = m
	return m

static func _fade(peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, peak))
	g.add_point(0.6, Color(1, 1, 1, peak * 0.7))
	return g

static func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _soft_mat()
	return q

static func _spray(pos: Vector3, side: Vector3, w: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _quad(0.45)
	p.amount = amount
	p.lifetime = 0.9
	p.position = pos
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = (side.abs() * w * 0.45) + Vector3(0.15, 0.05, 0.15)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0, -6.5, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.color_ramp = _fade(0.85)
	p.preprocess = 1.0
	return p

static func _mist(pos: Vector3, side: Vector3, w: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _quad(1.5)
	p.amount = 16
	p.lifetime = 4.0
	p.position = pos + Vector3.UP * 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = side.abs() * w * 0.5 + Vector3(0.4, 0.2, 0.4)
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0, 0.08, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.color_ramp = _fade(0.2)
	p.preprocess = 4.0
	return p

# --- fish ------------------------------------------------------------------------------

static func _fish_mesh() -> ArrayMesh:
	if _meshes.has("fish"): return _meshes["fish"]
	# spindle body along +X (nose at +0.5), 6-sided cross-section, plus a forked tail fin
	const NX := 7
	const NR := 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := func(i: int) -> Array:
		var t := float(i) / NX
		var x := 0.5 - t
		var prof := sin(PI * pow(t, 0.75)) if i < NX else 0.12
		var pts := []
		for k in NR:
			var a := TAU * k / NR
			pts.append(Vector3(x, sin(a) * 0.13 * prof, cos(a) * 0.075 * prof))
		return pts
	for i in NX:
		var r0: Array = ring.call(i)
		var r1: Array = ring.call(i + 1)
		for k in NR:
			var k2 := (k + 1) % NR
			st.add_vertex(r0[k]); st.add_vertex(r1[k]); st.add_vertex(r0[k2])
			st.add_vertex(r0[k2]); st.add_vertex(r1[k]); st.add_vertex(r1[k2])
	# tail fin (double sided via both windings)
	var tr := Vector3(-0.48, 0, 0)
	for f in [[tr, Vector3(-0.78, 0.17, 0), Vector3(-0.68, 0, 0)], [tr, Vector3(-0.68, 0, 0), Vector3(-0.78, -0.15, 0)]]:
		st.add_vertex(f[0]); st.add_vertex(f[1]); st.add_vertex(f[2])
		st.add_vertex(f[0]); st.add_vertex(f[2]); st.add_vertex(f[1])
	st.index()
	st.generate_normals()
	_meshes["fish"] = st.commit()
	return _meshes["fish"]

## School of fish wandering inside `radius` around centre, swimming below `water_level`.
## Animation is entirely in the vertex shader (no per-frame script cost).
static func fish_school(center: Vector3, radius: float, count: int, water_level: float, seed := 7) -> Node3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _fish_mesh()
	mm.instance_count = count
	var dir := 1.0 if r.randf() < 0.5 else -1.0
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		# mostly one shared direction (a loose school) with a few strays
		var d := dir if r.randf() < 0.75 else -dir
		mm.set_instance_custom_data(i, Color(r.randf_range(0.35, 1.0), d * r.randf_range(0.18, 0.4), r.randf() * TAU, r.randf_range(0.12, 0.3)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fish"
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = FISH_SHADER
	m.set_shader_parameter("radius", radius)
	m.render_priority = 1   # after the water plane: silhouettes read through it
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-radius * 1.6, -1.0, -radius * 1.6), Vector3(radius * 3.2, 1.2, radius * 3.2))
	mmi.position = Vector3(center.x, water_level, center.z)
	return mmi
