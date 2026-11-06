class_name OrigTrees
extends RefCounted
## The original Godot trees (tree.glb / tree3.glb) with their original shaders,
## split into trunk + leaf meshes so thousands can be instanced cheaply.

const MODELS := {
	"oak_a": "res://original/models/tree.glb",
	"oak_b": "res://original/models/tree3.glb",
}

static var _cache := {}

## Returns {trunk: Mesh, trunk_xf: Transform3D, leaves: Mesh, leaves_xf: Transform3D}
static func parts(key: String) -> Dictionary:
	if _cache.has(key): return _cache[key]
	var root: Node = (load(MODELS[key]) as PackedScene).instantiate()
	var out := {}
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	_cache[key] = out
	return out

static func _collect(n: Node, xf: Transform3D, out: Dictionary) -> void:
	var t := xf
	if n is Node3D: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var which := "trunk" if String(n.name).begins_with("trunk") else "leaves"
		out[which] = (n as MeshInstance3D).mesh
		out[which + "_xf"] = t
	for c in n.get_children(): _collect(c, t, out)

static func leaf_material(color: Color, scale := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://original/shaders/tree_leaves.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("alpha", load("res://original/textures/leaf_alpha.png"))
	m.set_shader_parameter("leaves_scale", scale)
	m.set_shader_parameter("leaf_bend_amount", 0.7)
	m.set_shader_parameter("light_steps", 5.0)
	return m

static func trunk_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://original/shaders/trunk_shader.gdshader")
	m.set_shader_parameter("color_texture", load("res://original/textures/tree_bark.png"))
	m.set_shader_parameter("uv_scale", Vector2(1, 1))
	m.set_shader_parameter("outline_mask", 1.0)
	m.set_shader_parameter("light_steps", 3.0)
	return m
