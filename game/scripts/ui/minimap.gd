extends Control
## The minimap, as on the design board: a round dark plate with a cream rim showing ~90 m round the player. The map is
## painted once from the world's own data (lawn, woods, paving, water, every building's footprint) and kept north up, so the
## N badge on the top rim is always true; the player is the blue arrow in the middle, turning as they face. The place the
## next goal suggests is a gold marker, pinned to the rim when it's further than the map shows.

const SIZE := 153.0              # the map itself (the board's 17.2rem)
const PAD := 7.0                 # plate showing round it
const PLATE := SIZE + PAD * 2.0
const EDGE := 21.0               # px from the screen's top and right
const VIEW := 90.0               # metres across the map
const RIM := 79.0                # px from the middle: where a far goal sits, on the plate's rim
const GOLD := Color("F0C33A")
const PING := 2.0                # s between the far goal's pings
const COLS := {"lawn": Color("CFE6C2"), "wood": Color("a9d38f"), "path": Color("FFF8E3"), "water": Color("BFE3F0"),
	"house": Color("337E43"), "edge": Color("262727")}

var world: Node
var goal := Vector2.INF          # world x, z of the place the next goal suggests; INF for none
var _tex: ImageTexture
var _origin := Vector2.ZERO      # world x, z of the image's corner
var _msize := Vector2.ONE        # metres the image covers
var _rect: ColorRect
var _mat: ShaderMaterial
var _back: Control                # the plate and its shadow, under the map
var _front: Control               # N, the goal and the player, over it

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -PLATE - EDGE
	offset_right = -EDGE
	offset_top = EDGE
	offset_bottom = EDGE + PLATE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = Control.new()
	_back.size = Vector2(PLATE, PLATE)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.draw.connect(func():
		var mid := Vector2(PLATE, PLATE) * 0.5
		for i in 6:
			_back.draw_circle(mid + Vector2(0, 9), PLATE * 0.5 + i * 2.0, Color(0, 0, 0, 0.05))
		_back.draw_circle(mid, PLATE * 0.5 + 3.0, Brand.CREAM)
		_back.draw_circle(mid, PLATE * 0.5, Brand.PLATE))
	add_child(_back)
	_paint()
	_rect = ColorRect.new()
	_rect.position = Vector2(PAD, PAD)
	_rect.size = Vector2(SIZE, SIZE)
	_rect.custom_minimum_size = Vector2(SIZE, SIZE)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform vec2 centre;      // world x, z at the middle
uniform vec2 origin;      // world x, z of the map image's corner
uniform vec2 msize;       // metres the image covers
uniform float view = 90.0;
uniform vec4 line : source_color = vec4(0.149, 0.153, 0.153, 1.0);
uniform sampler2D map_tex : filter_linear, repeat_disable;
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	if (r > 0.5) discard;
	vec4 c = texture(map_tex, (centre + d * view - origin) / msize);
	COLOR = mix(c, line, smoothstep(0.5 - 2.0 / 153.0, 0.5, r));
}"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("origin", _origin)
	_mat.set_shader_parameter("msize", _msize)
	_mat.set_shader_parameter("view", VIEW)
	_mat.set_shader_parameter("map_tex", _tex)
	_rect.material = _mat
	add_child(_rect)
	_front = Control.new()
	_front.size = Vector2(PLATE, PLATE)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)

## The map image, 1 px a metre: ground cover, paving and water from the baked layers, then the buildings.
func _paint() -> void:
	var d = world.data
	var w := int(d.w)
	var h := int(d.dep)
	_origin = Vector2(d.x0, d.z0)
	_msize = Vector2(w, h)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for z in h:
		for x in w:
			var p := Vector2(d.x0 + x + 0.5, d.z0 + z + 0.5)
			var c: Color = COLS.lawn
			if d.water_sd(p) < 0.0: c = COLS.water
			elif d.pave_dist(p) < 0.4: c = COLS.path
			elif d.cover_at(3, p) > 0.25: c = COLS.wood
			img.set_pixel(x, z, c)
	for site in world.sites:
		var fr: Vector2 = site.frame
		var f: Vector2 = site.face
		var pr := Vector2(-f.y, f.x)
		var c2: Vector2 = site.center2
		var r := int(ceil(fr.length())) + 1
		for z in range(int(c2.y - r), int(c2.y + r) + 1):
			for x in range(int(c2.x - r), int(c2.x + r) + 1):
				var q := Vector2(x + 0.5, z + 0.5) - c2
				var a := absf(q.dot(pr))
				var b := absf(q.dot(f))
				if a > fr.x or b > fr.y: continue
				var px := x - int(d.x0)
				var pz := z - int(d.z0)
				if px < 0 or pz < 0 or px >= w or pz >= h: continue
				var edge := a > fr.x - 1.0 or b > fr.y - 1.0
				img.set_pixel(px, pz, COLS.edge if edge else COLS.house)
	# the town's buildings as placed (the sites above only exist with the old game layer on)
	for r: Rect2 in world.town_rects:
		for z in range(int(r.position.y), int(r.end.y)):
			for x in range(int(r.position.x), int(r.end.x)):
				var px := x - int(d.x0)
				var pz := z - int(d.z0)
				if px < 0 or pz < 0 or px >= w or pz >= h: continue
				var edge := x == int(r.position.x) or z == int(r.position.y) or x == int(r.end.x) - 1 or z == int(r.end.y) - 1
				img.set_pixel(px, pz, COLS.edge if edge else COLS.house)
	_tex = ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	if world == null or world.player == null: return
	var pp: Vector3 = world.player.global_position
	_mat.set_shader_parameter("centre", Vector2(pp.x, pp.z))
	_front.queue_redraw()

## world x, z -> map pixels, from the middle
func _to_map(w: Vector2) -> Vector2:
	var pp: Vector3 = world.player.global_position
	return (w - Vector2(pp.x, pp.z)) / VIEW * SIZE

func _draw_front() -> void:
	if world == null or world.player == null: return
	var c := _front
	var mid := Vector2(PLATE, PLATE) * 0.5
	# the goal: where it is, or on the rim the way it lies
	if goal != Vector2.INF:
		var g := _to_map(goal)
		var off := g.length() >= SIZE * 0.5 - 7.0
		var at := mid + (g.normalized() * RIM if off else g)
		if off and HudMotion.on:
			# off the map, it pings a ring every PING s; this plate is redrawn every frame anyway, so the clock is enough
			var e := 1.0 - pow(1.0 - fmod(Time.get_ticks_msec() / 1000.0, PING) / PING, 2.0)
			# from just outside the marker's cream edge, so the ring reads while it is still bright
			c.draw_arc(at, lerpf(13.5, 30.0, e), 0.0, TAU, 40, Color(GOLD, 0.9 * (1.0 - e)), lerpf(3.0, 1.2, e), true)
		c.draw_circle(at, 12.0, Brand.CREAM)
		c.draw_circle(at, 10.0, Brand.PLATE)
		c.draw_circle(at, 7.0, GOLD)
	# N, fixed on the top rim: the map is north up
	var n := Vector2(mid.x, 2.0)
	var font: Font = Brand.FONT_DISPLAY
	c.draw_circle(n, 12.5, Brand.CREAM)
	c.draw_string(font, n + Vector2(-font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, (font.get_ascent(13) - font.get_descent(13)) * 0.5),
		"N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Brand.PLATE)
	# the player: the board's blue arrow, white edged, the way they face
	var fy: float = world.player._vis.rotation.y
	var dir := Vector2(sin(fy), cos(fy))
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([mid + dir * 8.5, mid - dir * 10.2 + side * 7.65, mid - dir * 6.0, mid - dir * 10.2 - side * 7.65])
	c.draw_colored_polygon(pts, Brand.BLUE)
	pts.append(pts[0])
	c.draw_polyline(pts, Color.WHITE, 2.1, true)
