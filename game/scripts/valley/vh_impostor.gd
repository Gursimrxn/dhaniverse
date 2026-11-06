class_name ValleyImpostor
extends RefCounted
## Octahedral tree impostors, baked at load from the trees' own high-detail meshes. Each species gets an
## albedo and a normal atlas of FRAMES x FRAMES views over the upper hemisphere (frame (i, j) looks from
## the direction the hemi-octahedral map puts at (i, j) / (FRAMES - 1)). All views of a tree are drawn in
## one frame: under an orthographic camera turning the tree is the same as moving the camera round it, so
## the viewport holds FRAMES^2 copies, each turned to show its view. Atlases come out premultiplied by
## coverage (cleared to transparent black, 4x MSAA on the edges), so filtering and mips need no dilation.
## The big trees get bigger frames; normals (lighting, low frequency) are kept at half the albedo's size.
## shaders/vh/impostor.gdshader draws them; leaf / bark shaders hand over to them (vh_tree_lod).

const FRAMES := 8
const FRAME_PX := 128
const BIG := {"broadleaf": 192, "oak": 192, "spruce": 192}

## Albedo frame size (px) for a species.
static func frame_px(species: String) -> int: return BIG.get(species, FRAME_PX)
const BAKE_SHADER := "res://shaders/vh/impostor_bake.gdshader"

## The direction (tree space, y up) a frame at atlas grid position g (0..1 each way) is seen from.
static func frame_dir(g: Vector2) -> Vector3:
	var e := g * 2.0 - Vector2.ONE
	var a := Vector2(e.x + e.y, e.x - e.y) * 0.5
	return Vector3(a.x, maxf(1.0 - absf(a.x) - absf(a.y), 0.0), a.y).normalized()

## Turns the tree so that `d` points at the camera (+Z) with the world's up as upright as it can be.
static func view_basis(d: Vector3) -> Basis:
	var right := Vector3.UP.cross(d)
	right = right.normalized() if right.length() > 1e-4 else Vector3.RIGHT
	var up := d.cross(right)
	return Basis(right, up, d).transposed()

## Bounding sphere about the trunk axis: [centre height, radius].
static func bounds(meshes: Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for m in meshes:
		for s in (m as Mesh).get_surface_count():
			for p in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
	var cy := (lo + hi) * 0.5
	var r := 0.0
	for m in meshes:
		for s in (m as Mesh).get_surface_count():
			for p in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				r = maxf(r, Vector3(p.x, p.y - cy, p.z).length())
	return Vector2(cy, r * 1.04)

static func _bake_mat(src: ShaderMaterial, leaf: bool, pass_i: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(BAKE_SHADER)
	m.set_shader_parameter("pass", pass_i)
	m.set_shader_parameter("is_leaf", leaf)
	if leaf:
		m.set_shader_parameter("tex", src.get_shader_parameter("leaf_tex"))
		var n = src.get_shader_parameter("leaf_n")
		m.set_shader_parameter("ntex", n)
		m.set_shader_parameter("normal_k", float(src.get_shader_parameter("normal_k")) if n else 0.0)
	else:
		m.set_shader_parameter("tex", src.get_shader_parameter("bark_tex"))
		m.set_shader_parameter("ntex", src.get_shader_parameter("bark_n"))
		m.set_shader_parameter("relief", src.get_shader_parameter("relief"))
	return m

static func _copies(root: Node3D, mesh: Mesh, mat: Material, xfs: Array) -> void:
	if mesh.get_surface_count() == 0: return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)

## items: key -> {trunk: Mesh, leaves: Mesh, bark_mat: ShaderMaterial, leaf_mat: ShaderMaterial, frame_px: int}.
## Returns key -> {albedo: ImageTexture, normal: ImageTexture, center_y, radius, frame_px}. A coroutine (await
## it): the viewports render on the next frame.
static func bake(host: Node, items: Dictionary) -> Dictionary:
	var jobs: Array = []
	for key in items:
		var it: Dictionary = items[key]
		var fpx: int = it.get("frame_px", FRAME_PX)
		var size := FRAMES * fpx
		var b := bounds([it.trunk, it.leaves])
		var R := b.y
		var xfs: Array = []
		for j in FRAMES:
			for i in FRAMES:
				var basis := view_basis(frame_dir(Vector2(i, j) / (FRAMES - 1.0)))
				var cell := Vector3((i + 0.5 - FRAMES * 0.5) * 2.0 * R, (FRAMES * 0.5 - j - 0.5) * 2.0 * R, 0.0)
				xfs.append(Transform3D(basis, cell - basis * Vector3(0.0, b.x, 0.0)))
		var vps: Array = []
		for pass_i in 2:
			var vp := SubViewport.new()
			vp.size = Vector2i(size, size) / (1 + pass_i)
			vp.own_world_3d = true
			vp.transparent_bg = true
			vp.use_hdr_2d = true
			vp.msaa_3d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			var root := Node3D.new()
			vp.add_child(root)
			_copies(root, it.trunk, _bake_mat(it.bark_mat, false, pass_i), xfs)
			_copies(root, it.leaves, _bake_mat(it.leaf_mat, true, pass_i), xfs)
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = FRAMES * 2.0 * R
			cam.near = 1.0
			cam.far = 4.0 * FRAMES * R + 100.0
			cam.position = Vector3(0.0, 0.0, 2.0 * FRAMES * R + 50.0)
			vp.add_child(cam)
			cam.current = true
			host.add_child(vp)
			vps.append(vp)
		jobs.append([key, b, vps, fpx])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := {}
	for job in jobs:
		var tex: Array = []
		for vp in job[2]:
			var img: Image = (vp as SubViewport).get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			tex.append(ImageTexture.create_from_image(img))
			vp.queue_free()
		out[job[0]] = {"albedo": tex[0], "normal": tex[1], "center_y": job[1].x, "radius": job[1].y, "frame_px": job[3]}
	return out
