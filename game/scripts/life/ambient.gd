class_name Ambient
extends Node3D
## Cheap atmospheric life: butterflies over flowers, dragonflies over water, a loose
## flock of birds now and then, sunlit pollen motes, leaves tumbling from trees.
## Butterflies/dragonflies = one MultiMesh of wing quads, birds = one MultiMesh,
## pollen + leaves = CPUParticles3D. Transforms update in place (no per-frame allocs).
##
## Ambient.build(parent, {flower_spots: Array[Vector3], tree_spots: Array[Vector3],
##     water_center: Vector3 (optional), bounds: AABB (top = bird altitude),
##     canopy_height: float = 4.0, butterflies: int = 10})

const FLUTTER_COLS := ["ffd36b", "fff6e0", "f59a5b", "8fc7f2", "f4a6bd", "ffe9a8"]

var flowers: Array[Vector3] = []
var trees: Array[Vector3] = []
var water := Vector3.INF
var bounds := AABB(Vector3(-20, 0, -20), Vector3(40, 14, 40))

var _wings: MultiMesh            # 2 instances per butterfly, 5 per dragonfly
var _flies: Array = []           # [home_a, home_b, blend, timer, phase, yaw, pos, scale]
var _darts: Array = []           # [pos, goal, timer, phase, yaw]
var _birds: MultiMesh
var _flock_t := -1.0
var _flock_wait := 2.0
var _flock_start := Vector3.ZERO
var _flock_dir := Vector3.FORWARD
var _flock_len := 1.0
var _bird_off: Array[Vector3] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()

const WING_SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled;
varying vec4 col;
void vertex() { col = COLOR; }
void fragment() {
	vec2 uv = UV;
	vec3 c = col.rgb;
	if (col.a > 0.75) {          // butterfly: fore + hind lobes, dark rim, pale eye spot
		float fore = length((uv - vec2(0.42, 0.34)) / vec2(0.56, 0.34));
		float hind = length((uv - vec2(0.3, 0.74)) / vec2(0.32, 0.26));
		float m = min(fore, hind);
		if (m > 1.0) discard;
		c = mix(c, vec3(0.16, 0.12, 0.15), smoothstep(0.72, 0.9, m));
		c = mix(vec3(1.0, 0.98, 0.9), c, step(1.0, length((uv - vec2(0.66, 0.3)) / vec2(0.1, 0.08))));
		c *= 0.8 + 0.25 * uv.x;
	} else if (col.a > 0.25) {   // dragonfly wing: slender, glassy
		if (length((uv - vec2(0.5, 0.5)) / vec2(0.5, 0.2)) > 1.0) discard;
		c = mix(c, vec3(0.95, 1.0, 1.0), 0.45 + 0.3 * uv.x);
	} else {                     // dragonfly body
		if (abs(uv.y - 0.5) > 0.09 + 0.06 * (1.0 - uv.x)) discard;
	}
	ALBEDO = c;
}
"""

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
void vertex() {
	float s = fract(float(INSTANCE_ID) * 0.618034 + 0.13);
	float a = TIME * (1.6 + s * 2.4) + s * 6.28;
	float b = TIME * (0.9 + s * 1.5) + s * 3.1;
	mat3 rx = mat3(vec3(1, 0, 0), vec3(0, cos(a), sin(a)), vec3(0, -sin(a), cos(a)));
	mat3 rz = mat3(vec3(cos(b), sin(b), 0), vec3(-sin(b), cos(b), 0), vec3(0, 0, 1));
	VERTEX = rz * rx * VERTEX;
	NORMAL = rz * rx * NORMAL;
	// lazy side-to-side drift of a falling leaf
	VERTEX += vec3(sin(TIME * 1.3 + s * 9.0), 0.0, cos(TIME * 1.1 + s * 7.0)) * 0.35;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (abs(p.x) > (1.0 - p.y * p.y) * 0.6) discard;
	ALBEDO = COLOR.rgb * (0.8 + 0.25 * UV.y) * (1.0 - 0.25 * step(abs(p.x), 0.05));
	ROUGHNESS = 1.0;
}
"""

static func build(parent: Node, cfg: Dictionary) -> Ambient:
	var a := Ambient.new()
	a.name = "Ambient"
	for p in cfg.get("flower_spots", []): a.flowers.append(p)
	for p in cfg.get("tree_spots", []): a.trees.append(p)
	a.water = cfg.get("water_center", Vector3.INF)
	a.bounds = cfg.get("bounds", a.bounds)
	parent.add_child(a)
	a._setup(cfg)
	return a

func _setup(cfg: Dictionary) -> void:
	_rng.seed = cfg.get("seed", 11)
	_build_wings(int(cfg.get("butterflies", 10)))
	_build_birds()
	_build_pollen()
	_build_leaves(float(cfg.get("canopy_height", 4.0)))

# --- butterflies & dragonflies ------------------------------------------------------
func _build_wings(count: int) -> void:
	if flowers.is_empty(): count = 0
	var nd := 2 if water != Vector3.INF else 0
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE
	q.center_offset = Vector3(0.5, 0, 0)    # hinge on the body axis
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = WING_SHADER
	_wings = MultiMesh.new()
	_wings.transform_format = MultiMesh.TRANSFORM_3D
	_wings.use_colors = true
	_wings.mesh = q
	_wings.instance_count = count * 2 + nd * 5
	for i in count:
		var h := _rng.randi() % flowers.size()
		var c := Color(FLUTTER_COLS[_rng.randi() % FLUTTER_COLS.size()])
		_wings.set_instance_color(i * 2, c)
		_wings.set_instance_color(i * 2 + 1, c)
		_flies.append([h, h, 1.0, _rng.randf_range(4, 12), _rng.randf() * 50.0, 0.0, flowers[h], _rng.randf_range(0.8, 1.2)])
	for d in nd:
		var base := count * 2 + d * 5
		for k in 4: _wings.set_instance_color(base + k, Color(0.55, 0.85, 0.95, 0.5))
		_wings.set_instance_color(base + 4, Color(0.1, 0.45, 0.75, 0.0))
		_darts.append([water + Vector3(0, 0.5, 0), water, 0.0, _rng.randf() * 10.0, 0.0])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _wings
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = bounds.grow(4.0)
	add_child(mmi)

func _wing_xf(pos: Vector3, yaw: float, flap: float, side: float, span: float, length: float) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, side * flap) * Basis.from_scale(Vector3(side * span, 1.0, length))
	return Transform3D(b, pos)

func _update_flies(delta: float) -> void:
	for i in _flies.size():
		var f: Array = _flies[i]
		f[3] -= delta
		if f[3] <= 0.0:   # wander to another flower patch
			f[0] = f[1]
			f[1] = _rng.randi() % flowers.size()
			f[2] = 0.0
			f[3] = _rng.randf_range(7, 16)
		f[2] = minf(f[2] + delta / 5.0, 1.0)
		var ph: float = f[4] + _t
		var home: Vector3 = flowers[f[0]].lerp(flowers[f[1]], smoothstep(0.0, 1.0, f[2]))
		var p := home + Vector3(sin(ph * 0.71) * 1.1 + sin(ph * 1.9) * 0.35, 0.55 + sin(ph * 0.9) * 0.3 + absf(sin(ph * 3.3)) * 0.12,
			cos(ph * 0.63) * 1.1 + cos(ph * 2.3) * 0.3)
		var prev: Vector3 = f[6]
		var mv := p - prev
		if mv.length_squared() > 0.000001:
			f[5] = lerp_angle(f[5], atan2(mv.x, mv.z), 1.0 - exp(-8.0 * delta))
		f[6] = p
		var glide := smoothstep(0.6, 0.9, sin(ph * 0.5))
		var flap := lerpf(sin(ph * 22.0) * 0.95 + 0.25, 0.35, glide)
		var s: float = f[7]
		_wings.set_instance_transform(i * 2, _wing_xf(p, f[5], flap, 1.0, 0.1 * s, 0.12 * s))
		_wings.set_instance_transform(i * 2 + 1, _wing_xf(p, f[5], flap, -1.0, 0.1 * s, 0.12 * s))
	var base := _flies.size() * 2
	for d in _darts.size():
		var f: Array = _darts[d]
		f[2] -= delta
		if f[2] <= 0.0:   # dart to a new hover point, then hang there
			f[1] = water + Vector3(_rng.randf_range(-3, 3), _rng.randf_range(0.3, 0.9), _rng.randf_range(-3, 3))
			f[2] = _rng.randf_range(0.8, 2.5)
		var p: Vector3 = f[0]
		var mv: Vector3 = f[1] - p
		p += mv * (1.0 - exp(-4.5 * delta))
		p.y += sin(_t * 9.0 + f[3]) * 0.003
		f[0] = p
		if mv.length_squared() > 0.01:
			f[4] = lerp_angle(f[4], atan2(mv.x, mv.z), 1.0 - exp(-10.0 * delta))
		var flap := sin(_t * 60.0 + f[3]) * 0.3
		var b0 := base + d * 5
		var fwd := Vector3(sin(f[4]), 0, cos(f[4]))
		_wings.set_instance_transform(b0, _wing_xf(p + fwd * 0.03, f[4], flap, 1.0, 0.16, 0.05))
		_wings.set_instance_transform(b0 + 1, _wing_xf(p + fwd * 0.03, f[4], flap, -1.0, 0.16, 0.05))
		_wings.set_instance_transform(b0 + 2, _wing_xf(p - fwd * 0.02, f[4], -flap, 1.0, 0.14, 0.045))
		_wings.set_instance_transform(b0 + 3, _wing_xf(p - fwd * 0.02, f[4], -flap, -1.0, 0.14, 0.045))
		var body := Basis(Vector3.UP, f[4]) * Basis(Vector3.UP, -PI * 0.5) * Basis.from_scale(Vector3(0.2, 1, 0.12))
		_wings.set_instance_transform(b0 + 4, Transform3D(body, p - fwd * 0.12))

# --- birds -------------------------------------------------------------------------
func _build_birds() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for v in [Vector3(0, 0, 0.16), Vector3(0.6, 0, -0.1), Vector3(0, 0, -0.14),
			Vector3(0, 0, 0.16), Vector3(0.3, 0, 0.1), Vector3(0.6, 0, -0.1)]:
		st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("3a4452")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_birds = MultiMesh.new()
	_birds.transform_format = MultiMesh.TRANSFORM_3D
	_birds.mesh = st.commit()
	_birds.instance_count = 7 * 2
	_birds.visible_instance_count = 0
	for i in 7:
		_bird_off.append(Vector3(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-0.8, 0.8), -absf(i - 3) * 1.4 + _rng.randf_range(-0.5, 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _birds
	mmi.material_override = m
	mmi.custom_aabb = bounds.grow(40.0)
	add_child(mmi)

func _update_birds(delta: float) -> void:
	if _flock_t < 0.0:
		_flock_wait -= delta
		if _flock_wait > 0.0: return
		var ang := _rng.randf() * TAU
		_flock_dir = Vector3(cos(ang), 0, sin(ang))
		var r := bounds.size.length() * 0.5 + 15.0
		var c := bounds.get_center()
		_flock_start = Vector3(c.x, bounds.end.y, c.z) - _flock_dir * r + Vector3(-_flock_dir.z, 0, _flock_dir.x) * _rng.randf_range(-r, r) * 0.3
		_flock_len = r * 2.0
		_flock_t = 0.0
		_birds.visible_instance_count = _rng.randi_range(4, 7) * 2
	_flock_t += delta
	var travel := _flock_t * 7.5
	if travel > _flock_len:
		_flock_t = -1.0
		_flock_wait = _rng.randf_range(12.0, 25.0)
		_birds.visible_instance_count = 0
		return
	var yaw := atan2(_flock_dir.x, _flock_dir.z)
	var side := Vector3(-_flock_dir.z, 0, _flock_dir.x)
	var n := _birds.visible_instance_count / 2
	for i in n:
		var o := _bird_off[i]
		var ph := _t * 1.3 + i * 1.7
		var p := _flock_start + _flock_dir * (travel + o.z) + side * (o.x + sin(ph * 0.5) * 0.6) + Vector3(0, o.y + sin(ph) * 0.4, 0)
		var cyc := fmod(_t + i * 0.37, 2.2)
		var flap := 0.12 + (sin(_t * 15.0 + i) * 0.75 if cyc < 1.0 else 0.0)
		var bank := sin(ph * 0.5) * 0.2
		_birds.set_instance_transform(i * 2, _wing_xf(p, yaw, flap + bank, 1.0, 1.0, 1.0))
		_birds.set_instance_transform(i * 2 + 1, _wing_xf(p, yaw, flap - bank, -1.0, 1.0, 1.0))

# --- pollen & leaves ---------------------------------------------------------------
func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32; t.height = 32
	return t

func _build_pollen() -> void:
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(bounds.size.x * 0.5, 1.6, bounds.size.z * 0.5)
	p.position = bounds.get_center() * Vector3(1, 0, 1) + Vector3(0, bounds.position.y + 2.0, 0)
	p.direction = Vector3(1, 0.3, 0.4)
	p.spread = 180.0
	p.initial_velocity_min = 0.04
	p.initial_velocity_max = 0.18
	p.gravity = Vector3(0.05, 0.015, 0.02)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.95, 0.75, 0.0))
	ramp.set_color(1, Color(1, 0.95, 0.75, 0.0))
	ramp.add_point(0.25, Color(1, 0.96, 0.78, 0.6))
	ramp.add_point(0.75, Color(1, 0.96, 0.78, 0.6))
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

func _build_leaves(canopy: float) -> void:
	if trees.is_empty(): return
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = LEAF_SHADER
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.16)
	q.material = sm
	var cols := Gradient.new()
	cols.set_color(0, Color("8fbf4a"))
	cols.set_color(1, Color("d9a640"))
	cols.add_point(0.5, Color("b9cf55"))
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 0.2))
	shrink.add_point(Vector2(0.08, 1))
	shrink.add_point(Vector2(0.9, 1))
	shrink.add_point(Vector2(1, 0))
	for t in trees:
		var p := CPUParticles3D.new()
		p.amount = 5
		p.lifetime = 7.0
		p.preprocess = 7.0 * _rng.randf()
		p.randomness = 0.6
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 1.8
		p.position = t + Vector3(0, canopy, 0)
		p.direction = Vector3(1, 0, 0.3)
		p.spread = 60.0
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.35
		p.gravity = Vector3(0.08, -0.8, 0.03)
		p.damping_min = 0.5
		p.damping_max = 0.9
		p.color_initial_ramp = cols
		p.scale_amount_curve = shrink
		p.mesh = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)

func _process(delta: float) -> void:
	_t += delta
	if _wings.instance_count > 0: _update_flies(delta)
	_update_birds(delta)
