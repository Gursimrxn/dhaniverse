extends TestCase
## The player camera's three views, as the base version had them (founder, 2026-10-29: "port the character
## view ports to our work, i want to see and move like i moved in base version"): C cycles top-down, third
## person and first person; each keeps its own zoom and pitch range.

const Rig := preload("res://scripts/player/camera_rig.gd")

func _rig() -> Node3D:
	var t := CharacterBody3D.new()
	tree.root.add_child(t)
	var r := Rig.new()
	r.target = t
	tree.root.add_child(r)
	r.set_mode("top", true)
	return r

func _free(r: Node3D) -> void:
	r.target.queue_free()
	r.queue_free()

func test_c_cycles_top_third_first() -> void:
	var r := _rig()
	var seen: Array = [r.mode]
	for i in 3:
		r.cycle_mode()
		seen.append(r.mode)
	eq(seen, ["top", "third", "first", "top"], "views in turn")
	_free(r)

func test_each_view_keeps_its_zoom_range() -> void:
	var r := _rig()
	for i in 60: r._zoom(0.9)
	near(r.distance, 7.0, 0.01, "top-down nearest")
	for i in 60: r._zoom(1.1)
	near(r.distance, 30.0, 0.01, "top-down farthest")
	r.set_mode("third", true)
	for i in 60: r._zoom(1.1)
	near(r.distance, 9.0, 0.01, "third person farthest")
	_free(r)

func test_first_person_looks_from_the_eyes() -> void:
	var r := _rig()
	r.set_mode("first", true)
	near(float(r.VIEWS.first.dist.y), 0.0, 0.001, "no distance behind the eyes")
	check(float(r.VIEWS.first.height) < 1.4, "eyes below the top of a 1.4 m body: %.2f" % float(r.VIEWS.first.height))
	_free(r)

func test_pitch_stays_in_each_views_range() -> void:
	var r := _rig()
	near(rad_to_deg(r._clamp_pitch(deg_to_rad(-89.0))), -72.0, 0.01, "top-down steepest")
	near(rad_to_deg(r._clamp_pitch(deg_to_rad(10.0))), -25.0, 0.01, "top-down shallowest")
	_free(r)
