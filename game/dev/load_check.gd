extends SceneTree
## Dev: loads every script under res://scripts and fails loudly on any that won't compile. A plain `--quit` never loads the
## game's scripts, so it can't catch a parse error; this does.
##   tools/godot_d.sh --path game --headless -s res://dev/load_check.gd

func _initialize() -> void:
	var bad := 0
	var count := 0
	for path in _scripts("res://scripts"):
		count += 1
		var s = load(path)
		if s == null or (s is GDScript and not s.can_instantiate() and not _abstract(path)):
			bad += 1
			print("FAILED ", path)
	print("load_check: %d scripts, %d failed" % [count, bad])
	quit(1 if bad > 0 else 0)

func _abstract(path: String) -> bool:
	return FileAccess.get_file_as_string(path).contains("@abstract")

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"): out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir): out.append_array(_scripts(dir.path_join(d)))
	return out
