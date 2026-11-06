extends SceneTree
# Dev: build every reference species and report triangles + build time.
func _tris(m: Mesh) -> int:
	return 0 if m.get_surface_count() == 0 else (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
func _init() -> void:
	for sp in VHTrees.SPECIES:
		var t0 := Time.get_ticks_usec()
		var t: Dictionary = VHTrees.build(sp, 1000 + sp.length() * 131)
		print("%-10s %5.1fms  high trunk=%5d leaves=%5d | low trunk=%5d leaves=%5d | h=%.1f crown=%.1f" % [sp, (Time.get_ticks_usec() - t0) / 1000.0,
			_tris(t.high.trunk), _tris(t.high.leaves), _tris(t.low.trunk), _tris(t.low.leaves), t.height, t.crown_radius])
	print("fern ", _tris(VHTrees.build_fern(11)))
	print("rng check ", VHNoise.rng(17).next(), " ", VHNoise.simplex(4242).noise2(0.3, 0.7))
	quit()
