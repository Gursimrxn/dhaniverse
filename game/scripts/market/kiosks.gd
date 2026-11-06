class_name Kiosks
extends Node3D
## The market's kiosks: six on the landing's lawn and six at the back of the Market Hall, shuttered unless `named` opens one (the
## exchange on the landing, the Spice Merchant's in the hall, which Tallyport staffs), and the hall's four that are always open, each with
## its keeper's name over it. Model: tools/blender/build_landing.py.

const KIOSK := preload("res://assets/market/kiosk.glb")
const SIGN_AT := Vector3(0.0, 2.06, 1.285)
const ON_HALL_FLOOR := 0.31
# x, z, yaw; the first six on the landing's lawn around a lane up from the jetty, the rest in the hall
const SHUT := [[-97.0, 44.0, 0.0], [-92.5, 44.0, 0.0], [-88.0, 44.0, 0.0], [-97.0, 54.5, PI], [-92.5, 54.5, PI], [-88.0, 54.5, PI],
	[-33.0, -35.5, 0.0], [-27.0, -35.5, 0.0], [-21.0, -35.5, 0.0], [-11.0, -35.5, 0.0], [-5.0, -35.5, 0.0], [-5.0, -22.0, -PI * 0.5]]
const IN_HALL_FROM := 6            # the index where the hall's begin
# the market's own, always open: x, z, yaw, the name over it
const OPEN := [[-26.5, -31.0, PI * 0.5, "Meena's Fruit"], [-9.5, -31.0, -PI * 0.5, "Bo's Orchard"], [-33.0, -26.5, 0.0, "Ingrid's Greens"], [-6.0, -25.5, 0.0, "Dario's Produce"]]
const OPEN_Y := 1.05               # the shutter, rolled up
const OPEN_SCALE := 0.08
const SEEN_TO := 65.0              # m

var world: Node3D
var paint := Callable()
var named := {}                    # index in SHUT -> the name over it: those are open for business
var placed := {}                   # index in SHUT -> its Transform3D, for whoever staffs it

func setup() -> void:
	for i in SHUT.size():
		var a: Array = SHUT[i]
		var node := _kiosk(a[2])
		node.global_position = Vector3(a[0], ON_HALL_FLOOR if i >= IN_HALL_FROM else world.height_at(a[0], a[1]), a[1])
		placed[i] = node.global_transform
		if named.has(i):
			_open_up(node, str(named[i]))
			continue
		(node.find_child("KioskGoods", true, false) as Node3D).visible = false
		for level in range(1, 4): (node.find_child("KioskLevel%d" % level, true, false) as Node3D).visible = false
	for m in OPEN:
		var node := _kiosk(m[2])
		node.global_position = Vector3(m[0], ON_HALL_FLOOR, m[1])
		_open_up(node, m[3])

## Shutter rolled up, the first level of goods out, and its name over it.
func _open_up(node: Node3D, title: String) -> void:
	var shutter: Node3D = node.find_child("KioskShutter", true, false)
	shutter.position.y = OPEN_Y
	shutter.scale.y = OPEN_SCALE
	(node.find_child("KioskLevel1", true, false) as Node3D).visible = true
	(node.find_child("KioskLevel2", true, false) as Node3D).visible = false
	(node.find_child("KioskLevel3", true, false) as Node3D).visible = false
	var name_board := Label3D.new()
	name_board.font = Brand.FONT_EDITORIAL
	name_board.font_size = 96
	name_board.pixel_size = 0.0028
	name_board.modulate = Brand.CREAM
	name_board.position = SIGN_AT
	name_board.text = title
	name_board.visibility_range_end = 45.0
	node.add_child(name_board)

## One kiosk in the town's materials, drawn only when near enough to see.
func _kiosk(yaw: float) -> Node3D:
	var node: Node3D = KIOSK.instantiate()
	add_child(node)
	paint.call(node)
	node.rotation.y = yaw
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = SEEN_TO
	return node
