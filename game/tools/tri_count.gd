extends SceneTree
# Dev: print triangle counts of foliage meshes and their thinned far versions.
#   godot --headless --script res://tools/tri_count.gd
func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t
func _init() -> void:
	for k in ["oak_a", "oak_b"]:
		var p := OrigTrees.parts(k)
		var a: Array = (p.leaves as Mesh).surface_get_arrays(0)
		print(k, " trunk=", _tris(p.trunk), " leaves=", _tris(p.leaves), " surfaces=", p.leaves.get_surface_count(), " indexed=", a[Mesh.ARRAY_INDEX] != null, " verts=", a[Mesh.ARRAY_VERTEX].size())
		print("  thin=", _tris(TreeBuilder.thin_cards(p.leaves, 3)))
	for sp in ["pine", "willow", "bush"]:
		var b := TreeBuilder.build(sp, 7)
		print(sp, " leaves=", _tris(b.leaves), " thin=", _tris(TreeBuilder.thin_cards(b.leaves, 3)))
	quit()
