@tool
extends EditorScenePostImport
# Godot 4.7.2's glTF importer keeps COLOR_0 but leaves vertex_color_use_as_albedo off, so the
# Blender vertex-colour paint renders grey. Set this as the GLB's Import > Import Script.
func _post_import(scene: Node) -> Object:
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var cols = mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
			var mat := mesh.surface_get_material(i) as BaseMaterial3D
			if mat and cols != null and cols.size() > 0:
				mat.vertex_color_use_as_albedo = true   # glTF COLOR_0 is linear: leave vertex_color_is_srgb off
	return scene
