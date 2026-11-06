extends SceneTree
## Headless test runner: every res://tests/test_*.gd is instantiated and each of its test_* methods called.
## A test fails by calling fail(msg) on itself (see TestCase). Exits 1 if anything failed, so a CI step or a
## shell `&&` can gate on it.
##   godot --headless --path game -s res://tests/run_tests.gd [-- --only=test_camera_rig]

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.trim_prefix("--only=")
	await process_frame                   # the root is in the tree from here: nodes added get their _ready
	var total := 0
	var failed := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not (f.begins_with("test_") and f.ends_with(".gd")): continue
		if only != "" and f.get_basename() != only: continue
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			total += 1
			failed += 1
			print("  FAIL %s: the script does not load (parse error?)" % f.get_basename())
			continue
		for m in script.get_script_method_list():
			if not str(m.name).begins_with("test_"): continue
			var t: TestCase = script.new()
			t.tree = self
			await t.call(m.name)
			total += 1
			if t.checks == 0: t.fail("made no checks (did it stop on a script error?)")
			if t.failures.is_empty():
				print("  ok   %s.%s" % [f.get_basename(), m.name])
			else:
				failed += 1
				print("  FAIL %s.%s: %s" % [f.get_basename(), m.name, "; ".join(t.failures)])
	print("%d/%d passed" % [total - failed, total])
	quit(1 if failed > 0 or total == 0 else 0)
