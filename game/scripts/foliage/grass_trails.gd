class_name GrassTrails
extends Node
## Where characters have walked, for the grass to part round them and spring back (shaders/foliage/grass*).
## Every node in the group "grass_actors" leaves a point each STEP metres it moves; a point pushes the grass
## away from it, less as it ages, until the grass has stood back up after LIFE seconds. Where each actor stands
## now pushes hardest. The points reach the shaders as a SLOTS x 1 float texture (global fol_trails), each
## texel (x, y, z, age / LIFE); unused ones sit far below the ground.

const SLOTS := 32
const STEP := 0.3
const LIFE := 3.5

var img := Image.create(SLOTS, 1, false, Image.FORMAT_RGBAF)
var tex: ImageTexture
var points: Array = []          # [position, time left behind]
var last := {}                  # actor -> where it last left a point

func _ready() -> void:
	img.fill(Color(0, -1000, 0, 1))
	tex = ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("fol_trails", tex)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	points = points.filter(func(q): return now - q[1] < LIFE)
	var actors := get_tree().get_nodes_in_group("grass_actors")
	for a in actors:
		var p: Vector3 = a.global_position
		if not last.has(a) or (last[a] as Vector3).distance_to(p) > STEP:
			last[a] = p
			points.append([p, now])
	while points.size() > SLOTS - actors.size(): points.pop_front()
	var i := 0
	for a in actors:
		var p: Vector3 = a.global_position
		img.set_pixel(i, 0, Color(p.x, p.y, p.z, 0.0))
		i += 1
	for q in points:
		img.set_pixel(i, 0, Color(q[0].x, q[0].y, q[0].z, (now - q[1]) / LIFE))
		i += 1
	for k in range(i, SLOTS): img.set_pixel(k, 0, Color(0, -1000, 0, 1))
	tex.update(img)
	for a in last.keys():
		if not is_instance_valid(a): last.erase(a)
