extends TestCase
## Buildings lining a curving lane face any direction: their collider must be their own footprint turned with
## them, not the box around the turned footprint.

const Site := preload("res://scripts/world/site.gd")

func _site(face: Vector2) -> Node3D:
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(10, 4, 6)          # 10 m across the front (+Z), 6 m deep
	mi.mesh = bm
	mi.position.y = 2
	model.add_child(mi)
	var site := Site.new()
	tree.root.add_child(site)
	site.setup({"id": "t", "node": model, "pos": Vector2(5, -3), "face": face}, {})
	site.settle(1.0)
	return site

func test_turned_collider_is_the_footprint() -> void:
	var f := Vector2(0.6, 0.8)
	var site := _site(f)
	var cs: CollisionShape3D = site.outer_body.get_child(0)
	var box: BoxShape3D = cs.shape
	near(box.size.x, 10.0 - 0.6, 0.01, "collider across")
	near(box.size.z, 6.0 - 0.6, 0.01, "collider deep")
	# its local +Z (the front) points along the site's facing
	var front: Vector3 = (site.transform * site.outer_body.transform * cs.transform).basis.z.normalized()
	near(front.x, f.x, 0.01, "front x")
	near(front.z, f.y, 0.01, "front z")
	site.queue_free()

func test_turned_door_stands_in_front() -> void:
	var f := Vector2(0.6, 0.8)
	var site := _site(f)
	# the door is 1.6 m out from the 3 m half-depth along the facing, from the centre
	var d := Vector2(site.door.x - 5.0, site.door.z + 3.0)
	near(d.dot(f), 3.0 + 1.6, 0.05, "door distance along the facing")
	near(absf(d.dot(Vector2(-f.y, f.x))), 0.0, 0.05, "door centred")
	site.queue_free()

func test_axis_site_is_unchanged() -> void:
	var site := _site(Vector2(0, 1))
	near(site.half2.x, 5.0, 0.01, "half x")
	near(site.half2.y, 3.0, 0.01, "half z")
	site.queue_free()
