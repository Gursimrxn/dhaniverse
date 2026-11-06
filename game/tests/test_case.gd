class_name TestCase
extends RefCounted
## Base for res://tests/test_*.gd (run by tests/run_tests.gd): record failures, never stop at the first.
## Every check counts: a test that made none failed (a script error aborts a test before its checks, and
## GDScript has no exceptions to report it otherwise).

var failures: Array[String] = []
var checks := 0
var tree: SceneTree

func fail(msg: String) -> void:
	failures.append(msg)

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fail(msg)

func eq(got, want, what := "") -> void:
	check(got == want, "%s: got %s, want %s" % [what, got, want])

func near(got: float, want: float, tol: float, what := "") -> void:
	check(absf(got - want) <= tol, "%s: got %.4f, want %.4f ± %.4f" % [what, got, want, tol])
