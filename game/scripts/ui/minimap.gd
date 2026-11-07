extends Control
## The minimap, as on the design board (ux02): a round plate in a cream ring showing ~90 m round the player, turned with the camera
## so up on the map is the way the camera looks. The map is painted once from the world's own data in the board's colours (the
## ground, the paving the ground is drawn with, the river, every building's footprint); over it the N badge riding the rim, the
## gold route along the paving to the next step and its gold diamond (on the rim when it's further than the map shows), you as the
## cream arrow in the middle, and the place you're at in a pill at the bottom.

const SIZE := 156.0              # the board's 176 px plate, on the 1280x720 canvas
const EDGE := 21.0               # px from the screen's top and right
const VIEW := 90.0               # metres across the map
const RIM := SIZE * 0.5 - 12.0   # px from the middle: where a far goal sits
const GOLD := Color("F0C33A")
const COLS := {"ground": Color("3f4a3a"), "road": Color("8c8471"), "water": Color("3b5560"), "house": Color("59604f")}
const PLACE_PX := 10             # the place's words, Satoshi Medium
const FONT_PLACE := preload("res://assets/fonts/Satoshi-Medium.woff2")
const CELL := 2                  # m a route cell
const ROUTE_EVERY := 0.4         # s between new routes
const OFF_PAVING := 4.0          # how much dearer a metre of grass is than a metre of paving

var world: Node
var goal := Vector2.INF          # world x, z of the place the next goal suggests; INF for none
var place := "":                 # the name in the pill at the bottom
	set(v):
		if v == place: return
		place = v
		if _front: _front.queue_redraw()
var _tex: ImageTexture
var _origin := Vector2.ZERO      # world x, z of the image's corner
var _msize := Vector2.ONE        # metres the image covers
var _mat: ShaderMaterial
var _front: Control               # N, the route, the goal, you and the place, over the map
var _turn := 0.0                 # radians the map is turned: the camera's heading
var _grid := AStarGrid2D.new()   # the town in CELL m cells: paving cheap, grass dear, buildings and the river closed
var _route := PackedVector2Array()   # world x, z from you to the goal
var _route_in := 0.0

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -SIZE - EDGE
	offset_right = -EDGE
	offset_top = EDGE
	offset_bottom = EDGE + SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Control.new()        # the cream ring and its soft shadow, under the map
	back.size = Vector2(SIZE, SIZE)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.draw.connect(func():
		var mid := Vector2(SIZE, SIZE) * 0.5
		for i in 6: back.draw_circle(mid + Vector2(0, 9), SIZE * 0.5 + i * 2.0, Color(0, 0, 0, 0.05))
		back.draw_circle(mid, SIZE * 0.5 + 3.0, Brand.CREAM))
	add_child(back)
	_paint()
	var map := ColorRect.new()
	map.size = Vector2(SIZE, SIZE)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 centre;      // world x, z at the middle
uniform vec2 origin;      // world x, z of the map image's corner
uniform vec2 msize;       // metres the image covers
uniform float view = 90.0;
uniform float px = 156.0;
uniform float turn;       // the camera's heading: the map turns the other way
uniform vec4 ground : source_color;
uniform sampler2D map_tex : filter_linear, repeat_disable;
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	vec2 w = vec2(d.x * cos(turn) + d.y * sin(turn), -d.x * sin(turn) + d.y * cos(turn));
	vec2 uv = (centre + w * view - origin) / msize;
	vec4 c = (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) ? ground : texture(map_tex, uv);
	COLOR = vec4(c.rgb, 1.0 - smoothstep(0.5 - 1.0 / px, 0.5, r));
}"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("origin", _origin)
	_mat.set_shader_parameter("msize", _msize)
	_mat.set_shader_parameter("view", VIEW)
	_mat.set_shader_parameter("px", SIZE)
	_mat.set_shader_parameter("ground", COLS.ground)
	_mat.set_shader_parameter("map_tex", _tex)
	map.material = _mat
	add_child(map)
	_front = Control.new()
	_front.size = Vector2(SIZE, SIZE)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)

## The map image, 1 px a metre over the town's walkable rect (and a margin the view can show past its edge): the ground, the
## river, the paving the ground itself is drawn with (the square and plazas as well as the paths), then every building.
func _paint() -> void:
	var d = world.data
	var area: Rect2 = world.MAP.grow(VIEW * 0.5)
	var w := int(area.size.x)
	var h := int(area.size.y)
	_origin = area.position
	_msize = Vector2(w, h)
	var paved: Image = d.paved_tex.get_image()
	var pr: Vector4 = d.paved_rect
	var pn := Vector2(paved.get_width(), paved.get_height())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for z in h:
		for x in w:
			var p := _origin + Vector2(x + 0.5, z + 0.5)
			var c: Color = COLS.ground
			var u := Vector2i(((p - Vector2(pr.x, pr.y)) / Vector2(pr.z, pr.w) * pn).floor())
			if d.water_sd(p) < 0.0: c = COLS.water
			elif u.x >= 0 and u.y >= 0 and u.x < pn.x and u.y < pn.y and paved.get_pixel(u.x, u.y).r > 0.5: c = COLS.road
			img.set_pixel(x, z, c)
	for r: Rect2 in world.town_rects:     # the town's buildings, as placed
		var cut := r.intersection(area)
		for z in range(int(cut.position.y), int(ceil(cut.end.y))):
			for x in range(int(cut.position.x), int(ceil(cut.end.x))):
				var px := x - int(_origin.x)
				var pz := z - int(_origin.y)
				if px >= 0 and pz >= 0 and px < w and pz < h: img.set_pixel(px, pz, COLS.house)
	_tex = ImageTexture.create_from_image(img)
	_build_grid(img)

## The route finder's cells, from the painted map: paving is cheap, grass dear, and a cell mostly building or river is closed.
func _build_grid(img: Image) -> void:
	var n := Vector2i(img.get_width() / CELL, img.get_height() / CELL)
	_grid.region = Rect2i(Vector2i.ZERO, n)
	_grid.cell_size = Vector2.ONE
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for y in n.y:
		for x in n.x:
			var paved := 0
			var shut := 0
			for k in CELL * CELL:
				var c := img.get_pixel(x * CELL + k % CELL, y * CELL + k / CELL)
				if c == COLS.road: paved += 1
				elif c == COLS.house or c == COLS.water: shut += 1
			if shut * 2 > CELL * CELL and paved == 0: _grid.set_point_solid(Vector2i(x, y))
			else: _grid.set_point_weight_scale(Vector2i(x, y), 1.0 if paved * 2 >= CELL * CELL else OFF_PAVING)

func _cell(w: Vector2) -> Vector2i:
	return Vector2i(((w - _origin) / CELL).floor()).clamp(Vector2i.ZERO, _grid.region.size - Vector2i.ONE)

## The way to the goal from where you stand: the cheapest cells, back in world metres.
func _find_route() -> void:
	_route.clear()
	if goal == Vector2.INF: return
	var pp: Vector3 = world.player.global_position
	for c in _grid.get_id_path(_cell(Vector2(pp.x, pp.z)), _cell(goal), true):
		_route.append(_origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL)

func _process(delta: float) -> void:
	if world == null or world.player == null: return
	var pp: Vector3 = world.player.global_position
	var cam := get_viewport().get_camera_3d()
	if cam:
		var f := -cam.global_basis.z
		if Vector2(f.x, f.z).length() > 0.05: _turn = atan2(-f.x, -f.z)     # looking straight down keeps the last heading
	_mat.set_shader_parameter("centre", Vector2(pp.x, pp.z))
	_mat.set_shader_parameter("turn", _turn)
	_route_in -= delta
	if _route_in <= 0.0:
		_route_in = ROUTE_EVERY
		_find_route()
	_front.queue_redraw()

## world x, z -> map pixels, from the middle, turned with the camera
func _to_map(w: Vector2) -> Vector2:
	var pp: Vector3 = world.player.global_position
	return (w - Vector2(pp.x, pp.z)).rotated(_turn) / VIEW * SIZE

func _draw_front() -> void:
	if world == null or world.player == null: return
	var c := _front
	var mid := Vector2(SIZE, SIZE) * 0.5
	# the way there, along the paving, as far as the map shows
	if _route.size() > 1:
		var line := PackedVector2Array([mid])
		for q in _route.slice(1):
			var at := _to_map(q)
			if at.length() > SIZE * 0.5 - 4.0: break
			line.append(mid + at)
		if line.size() > 1:
			c.draw_polyline(line, Brand.PLATE, 5.0, true)
			c.draw_polyline(line, GOLD, 2.6, true)
	# the next step: a gold diamond where it is, or on the rim the way it lies
	if goal != Vector2.INF:
		var g := _to_map(goal)
		var at := mid + (g.normalized() * RIM if g.length() > RIM else g)
		var k := 6.2
		var diamond := PackedVector2Array([at + Vector2(0, -k), at + Vector2(k, 0), at + Vector2(0, k), at + Vector2(-k, 0)])
		c.draw_colored_polygon(diamond, GOLD)
		diamond.append(diamond[0])
		c.draw_polyline(diamond, Brand.PLATE, 1.4, true)
	# N, on the rim where north is
	var n := mid + Vector2(0.0, -1.0).rotated(_turn) * (SIZE * 0.5 - 12.5)
	c.draw_circle(n, 8.0, Brand.PLATE)
	_centred(c, Brand.FONT_DISPLAY, 10, "N", n)
	# you: the board's cream arrow, the way you face
	var fy: float = world.player._vis.rotation.y
	var dir := Vector2(sin(fy), cos(fy)).rotated(_turn)
	var side := Vector2(-dir.y, dir.x)
	c.draw_colored_polygon(PackedVector2Array([mid + dir * 5.3, mid - dir * 8.9 + side * 6.2, mid - dir * 5.3, mid - dir * 8.9 - side * 6.2]), Brand.CREAM)
	# where you are, in a pill at the bottom
	if place != "":
		var w := FONT_PLACE.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, PLACE_PX).x + 22.0
		var pill := Rect2(mid.x - w * 0.5, 124.5, w, 19.5)
		var round := StyleBoxFlat.new()
		round.bg_color = Brand.PLATE
		round.set_corner_radius_all(10)
		c.draw_style_box(round, pill)
		_centred(c, FONT_PLACE, PLACE_PX, place, pill.get_center())

## A word drawn with its middle at a point.
func _centred(c: Control, font: Font, px: int, text: String, at: Vector2) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(font, at + Vector2(-w * 0.5, (font.get_ascent(px) - font.get_descent(px)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Brand.CREAM)
