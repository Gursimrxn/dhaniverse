extends Node3D
## Builds the Dhani Valley from world/valley/world.json (tools/compose_valley.py: valley.json + the
## baked v3 town) with the Verdant Horizon look ported from the three.js reference: procedural sky as
## environment light, ACES, aerial perspective, PBR terrain, water with traced reflections and refraction,
## generated broadleaf/oak/spruce trees, translucent grass, fractured rocks, LED bollards,
## the slender skybridge and the ring-tower city on the horizon. Edit valley.json, not this file.
## Three times of day (SkyModes: day, evening, night), switched with T or the HUD and blended over a
## couple of seconds: sky, sun or moon, atmosphere and grade change together; at night the street
## lamps, bollards and doorways light the town (vh_lamps), windows, signs and the far city glow.

signal time_mode_changed(mode: String)

const SiteScript := preload("res://scripts/world/site.gd")
const PlayerScript := preload("res://scripts/player/player.gd")
const CameraRig := preload("res://scripts/player/camera_rig.gd")
const TestPanel := preload("res://scripts/ui/test_panel.gd")
const WeatherScript := preload("res://scripts/world/weather.gd")
const LifeDirectorScript := preload("res://scripts/life/life_director.gd")
const SpotScript := preload("res://scripts/world/spot.gd")
const PersonScript := preload("res://scripts/life/person.gd")
const CastScript := preload("res://scripts/life/cast.gd")
## The Old Quarter by default; `-- --world=valley` loads the earlier valley (the fallback).
const WORLDS := {"quarter": "res://world/quarter/world.json", "valley": "res://world/valley/world.json"}
const TILE := 64.0             # terrain tile (m)
const TILE_LOD := 230.0        # near/far terrain switch distance
const CHUNK := 64.0            # culling chunk for the falling leaves and sun shafts (m)
const TREE_CHUNK := 32.0       # culling chunk for the mesh trees (m)
const TREE_LOD := Vector2(20.0, 60.0)   # mesh trees hand over to their impostors within this range (m) ...
const TREE_MAG := 1.3          # ... where an impostor texel would cover this many screen pixels
const TREE_TWIG := 18.0        # past this the mesh trees keep their crowns but drop to the plain trunk
const SHRUB_FAR := 190.0       # shrub impostors end here; tree impostors go on to the horizon
const BCELL := 8.0
const LAYER_FIELDS := 2        # grass, flowers, ferns, leaves, motes, shafts
const LAYER_WATER := 4
const LAYER_POST := 128          # full-screen passes in the scene (ambient occlusion): main camera only
const SETTINGS_FILE := "user://settings.cfg"
const MODE_BLEND := 2.5        # seconds to change the time of day
const LAMP_SLOTS := 12         # lamps lit at once around the player (vh.gdshaderinc has room for 16)
# lamp kinds: linear colour, intensity, range (m)
const LAMP_STREET := [Color(1.0, 0.584, 0.254), 14.0, 13.0]     # #ffc98a lanterns
const LAMP_BOLLARD := [Color(1.0, 0.665, 0.361), 3.5, 6.0]      # #ffd5a2 trail bollards
const LAMP_DOOR := [Color(1.0, 0.644, 0.353), 5.0, 8.0]         # #ffd2a0 light over a doorway

var data: WorldData
var sites: Array = []
var bgrid := {}
var trees := {}                # template key -> {tpl, xf: []}
var fields: Array = []         # [field node (GrassBuilder), snap spacing]
var player: CharacterBody3D
var rig: Node3D
var sun: DirectionalLight3D
var env: Environment
var post: ColorRect
var kit = null
var river_kit = null
var preset: Dictionary
var rng := RandomNumberGenerator.new()
var mirror_y := 0.0
var mats := {}
# time of day
var mode := ""
var look: Dictionary           # the look on screen (a blend while changing)
var looks := {}                # mode -> look with sun placement and sky SH filled in
var _look_from: Dictionary
var _look_to: Dictionary
var _blend := 1.0
var lamps: Array = []          # [position, linear colour, intensity, range]
var lamp_w := PackedFloat32Array()   # each lamp's eased weight
var lamp_heads: Array = []     # street lamp heads, for their halos and ground glow
var city_mat: ShaderMaterial
var shafts: Node3D
var fireflies: MultiMeshInstance3D
var halos: MultiMeshInstance3D
var weather: Node3D               # seasons and weather (scripts/world/weather.gd)
var _upstream: Array = []        # [far source, the river's first point] when the river flows in from the far country
var _capturing := false         # dev screenshots: leave the player's saved choices alone

func _ready() -> void:
	var world := "quarter"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="): world = a.trim_prefix("--world=")
	data = WorldData.load_file(WORLDS.get(world, WORLDS.quarter))
	rng.seed = int(data.d.seed)
	kit = _try_load("res://scripts/kit/kit.gd")
	river_kit = _try_load("res://scripts/river/river_kit.gd")
	for r in data.d.river.reaches:
		if r.get("mirror", false): mirror_y = float(r.points[0][3])
	_lighting(_start_mode())
	_terrain()
	_water()
	_sites()
	_props()
	_crossings()
	_landmarks()
	_life()
	_trails()
	_lamp_glows()
	_rocks()
	_trees()
	_shafts()
	_fields()
	_falling_leaves()
	_motes()
	_fireflies()
	_butterflies()
	_horizon()
	await _impostors()   # bakes the tree impostors: a coroutine, the viewports render on the next frame
	_player()
	weather = WeatherScript.new()
	weather.world = self
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--season="): weather.season_override = a.trim_prefix("--season=")
		if a.begins_with("--weather="): weather.weather_override = a.trim_prefix("--weather=")
	add_child(weather)
	_ssao()
	_post()
	_apply_look(look)
	var tp := TestPanel.new()
	tp.world = self
	add_child(tp)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shots="):
			_capture(a.trim_prefix("--shots="))
			return
	for a in args:
		if a.begins_with("--snap="):      # dev: exactly what a player sees after 10 s, then quit
			_snap(a.trim_prefix("--snap="))
			return
	if not args.has("--no-intro") and not data.d.get("intro", []).is_empty() and not _setting("seen_quarter_intro", false): _intro()

func _try_load(path: String):
	if not ResourceLoader.exists(path): return null
	var s = load(path)
	return s if s is Script and s.can_instantiate() else null

func _mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m

func height_at(x: float, z: float) -> float:
	return data.height(Vector2(x, z))

## MeshStandardMaterial-style prop material (shaders/vh/pbr.gdshader), cached by its settings.
func _pbr(color: Color, rough: float, metal := 0.0, vcol := false, tri := "", tri_scale := 0.0, tri_ns := 1.0, flat := false) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s|%s|%s|%s" % [color.to_html(), rough, metal, vcol, tri, tri_scale, tri_ns, flat]
	if mats.has(key): return mats[key]
	var m := _mat("res://shaders/vh/pbr.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("use_vcol", vcol)
	m.set_shader_parameter("flat_shade", flat)
	if tri != "":
		m.set_shader_parameter("tri_tex", VHTex.get_tex(tri + "_map"))
		m.set_shader_parameter("tri_n", VHTex.get_tex(tri + "_normal"))
		m.set_shader_parameter("tri_scale", tri_scale)
		m.set_shader_parameter("tri_ns", tri_ns)
	mats[key] = m
	return m

func _led(color: Color, energy: float) -> ShaderMaterial:
	var m := _mat("res://shaders/vh/led.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	return m

func _mesh(mesh: Mesh, mat: Material, shadows := true, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = layers
	add_child(mi)
	return mi

# --- keep-out shapes ------------------------------------------------------------------------------
func block(p: Vector2, r: float, half := Vector2.ZERO) -> void:
	var b := [p, half if half != Vector2.ZERO else Vector2(r, r), half == Vector2.ZERO]
	var e: Vector2 = b[1] + Vector2(4.0, 4.0)
	for cz in range(floori((p.y - e.y) / BCELL), floori((p.y + e.y) / BCELL) + 1):
		for cx in range(floori((p.x - e.x) / BCELL), floori((p.x + e.x) / BCELL) + 1):
			bgrid.get_or_add(Vector2i(cx, cz), []).append(b)

func blocked(p: Vector2, pad := 0.0) -> bool:
	for b in bgrid.get(Vector2i(floori(p.x / BCELL), floori(p.y / BCELL)), []):
		if b[2]:
			if p.distance_to(b[0]) < b[1].x + pad: return true
		else:
			var q: Vector2 = (p - b[0]).abs()
			if q.x < b[1].x + pad and q.y < b[1].y + pad: return true
	return false

# --- light & atmosphere (Game.ts: sun #ffc591 x 3.1, sky environment x 0.9, ACES, bloom) --------------------
static func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

func _lighting(pname: String) -> void:
	mode = pname
	look = _look(pname)
	preset = data.d.lighting[pname]
	RenderingServer.global_shader_parameter_set("vh_wind", Vector2(0.82, 0.38))
	RenderingServer.global_shader_parameter_set("vh_water_y", mirror_y)
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	var sky := Sky.new()
	sky.sky_material = _mat("res://shaders/vh/sky.gdshader")
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED   # sky light is evaluated in the shaders (VHSky SH)
	env.ambient_light_energy = float(preset.ambient_intensity)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED   # sky specular is computed in the shaders (vh_ibl_spec)
	# Compatibility does no sRGB conversion: render linear HDR (project hdr_2d) and let the grade pass
	# apply three.js ACES + sRGB exactly.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false   # the reference's bloom runs in shaders/vh/grade.gdshader
	env.glow_intensity = 0.32
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7: env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# --- time of day (SkyModes) -------------------------------------------------------------------------------
## The player's choices (time of day, camera view), kept between sessions.
func _setting(key: String, fallback):
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	return cfg.get_value("graphics", key, fallback)

func _save_setting(key: String, value) -> void:
	if _capturing: return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	cfg.set_value("graphics", key, value)
	cfg.save(SETTINGS_FILE)

## Command line (-- --mode=night) wins, then the player's last choice, then world.json's default.
func _start_mode() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode=") and SkyModes.LOOKS.has(a.trim_prefix("--mode=")): return a.trim_prefix("--mode=")
	# the sky follows the player's own day (T and the test panel change it for the session)
	var h: int = Time.get_datetime_dict_from_system().hour
	return "day" if h >= 6 and h < 17 else ("evening" if h >= 17 and h < 20 else "night")

## A mode's full look: SkyModes' atmosphere + world.json's sun placement, colour and intensity + the SH of
## that sky, computed once per mode.
func _look(m: String) -> Dictionary:
	if looks.has(m): return looks[m]
	var lk: Dictionary = SkyModes.LOOKS[m].duplicate(true)
	var w: Dictionary = data.d.lighting[m]
	lk.to_sun = _dir(w.sun_az, w.sun_el)
	lk.to_light = _dir(w.get("light_az", w.sun_az), w.get("light_el", w.sun_el))
	lk.sun_color = Color(str(w.sun_color))      # sRGB: Godot linearises light colours itself
	lk.intensity = float(w.intensity)            # LIGHT_COLOR = linear colour x energy x PI = colour x intensity, as in three.js
	lk.grade.exposure = float(w.get("exposure", lk.grade.exposure))
	lk.sh = VHSky.project(lk.to_sun, lk)
	looks[m] = lk
	return lk

## Push a look to the shaders, the sun / moon, the grade and the city; hide what it switches off.
func _apply_look(lk: Dictionary) -> void:
	look = lk
	for k in lk:
		if k.begins_with("vh_"): RenderingServer.global_shader_parameter_set(k, lk[k])
	var to_sun: Vector3 = lk.to_sun.normalized()
	var to_light: Vector3 = lk.to_light.normalized()
	RenderingServer.global_shader_parameter_set("vh_sun", to_sun)
	RenderingServer.global_shader_parameter_set("sun_dir", to_sun)
	RenderingServer.global_shader_parameter_set("vh_light", to_light)
	VHSky.set_coeffs(lk.sh)
	if sun:
		sun.look_at_from_position(Vector3.ZERO, -to_light, Vector3.UP if absf(to_light.y) < 0.999 else Vector3.FORWARD)
		sun.light_color = lk.sun_color
		sun.light_energy = lk.intensity / PI
	var sc: Color = (lk.sun_color as Color).srgb_to_linear() * float(lk.intensity)
	RenderingServer.global_shader_parameter_set("vh_sun_light", Vector3(sc.r, sc.g, sc.b))
	_foliage_light(to_light, Vector3(sc.r, sc.g, sc.b))
	if post:
		for g in lk.grade: post.material.set_shader_parameter(g, lk.grade[g])
	if city_mat:
		city_mat.set_shader_parameter("body", lk.city_body)
		city_mat.set_shader_parameter("sun_tint", lk.city_sun)
	if shafts: shafts.visible = (lk.vh_shafts as Vector4).x > 0.002
	if fireflies: fireflies.visible = lk.vh_night > 0.02
	if halos: halos.visible = (lk.vh_glow as Vector4).w > 0.02

## The cel-shaded foliage's lights (shaders/foliage): the world's sun, and the reference's sky-over-ground fill
## (#bfd8ff over #6b5a45) dimmed with the sun, so evening and night darken the trees with everything else.
const FOL_SKY := Vector3(0.522, 0.686, 1.0)
const FOL_GROUND := Vector3(0.147, 0.102, 0.063)
const FOL_SHADOW := Vector4(0.027, 0.044, 0.107, 0.75)    # #2e3b5c at 0.75
func _foliage_light(to_light: Vector3, sun_lin: Vector3) -> void:
	var k := clampf(sun_lin.dot(Vector3(0.2126, 0.7152, 0.0722)) / 4.5, 0.08, 1.0)
	RenderingServer.global_shader_parameter_set("fol_sun", sun_lin)
	RenderingServer.global_shader_parameter_set("fol_sun_dir", to_light)
	RenderingServer.global_shader_parameter_set("fol_sky", FOL_SKY * k)
	RenderingServer.global_shader_parameter_set("fol_ground", FOL_GROUND * k)
	RenderingServer.global_shader_parameter_set("fol_shadow", FOL_SHADOW)

## Change the time of day, blending from what is on screen; the choice is remembered for next time.
func set_time_mode(m: String, instant := false) -> void:
	if not SkyModes.LOOKS.has(m): return
	var target := _look(m)
	mode = m
	if instant:
		_blend = 1.0
		_apply_look(target)
	else:
		_look_from = look
		_look_to = target
		_blend = 0.0
	_save_setting("time_of_day", m)
	time_mode_changed.emit(m)

## Test panel: the next season, the next weather.
func cycle_season() -> void:
	if weather: weather.cycle_season()

func cycle_weather() -> void:
	if weather: weather.cycle_weather()

func cycle_time_mode() -> void:
	set_time_mode(SkyModes.ORDER[(SkyModes.ORDER.find(mode) + 1) % SkyModes.ORDER.size()])

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("time_of_day"): cycle_time_mode()

func _update_time_of_day(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(_blend + delta / MODE_BLEND, 1.0)
		_apply_look(SkyModes.mix(_look_from, _look_to, smoothstep(0.0, 1.0, _blend)))
	RenderingServer.global_shader_parameter_set("vh_time", Time.get_ticks_msec() * 0.001)
	_update_lamps(delta)
	_update_sun_on_screen()

## Light the lamps around the player (the camera rig's focus) whose light can reach the view, faded out
## towards vh_lamp_fade.y (further out the ground glow decals carry their light) and eased in and out so
## a lamp never pops as it gains or loses one of the LAMP_SLOTS.
func _update_lamps(delta: float) -> void:
	var k: float = look.get("lamps", 0.0)
	var focus: Vector3 = rig.global_position if rig else Vector3.ZERO
	RenderingServer.global_shader_parameter_set("vh_focus", focus)
	var fade: Vector4 = look.vh_lamp_fade
	if lamp_w.size() != lamps.size(): lamp_w.resize(lamps.size())
	var cam := get_viewport().get_camera_3d()
	var planes: Array = cam.get_frustum() if cam else []
	var live: Array = []
	for i in lamps.size():
		var p: Vector3 = lamps[i][0]
		var target := 0.0
		if k > 0.001:
			target = 1.0 - smoothstep(fade.x, fade.y, Vector2(p.x - focus.x, p.z - focus.z).length())
			if target > 0.0:
				for pl in planes:
					if (pl as Plane).distance_to(p) > float(lamps[i][3]) + 4.0:
						target = 0.0
						break
		lamp_w[i] = move_toward(lamp_w[i], target, delta * 5.0)
		if lamp_w[i] > 0.002: live.append(i)
	live.sort_custom(func(a, b): return lamp_w[a] > lamp_w[b])
	var n := mini(live.size(), LAMP_SLOTS)
	for j in n:
		var l: Array = lamps[live[j]]
		var c: Color = l[1] * (float(l[2]) * k * lamp_w[live[j]])
		RenderingServer.global_shader_parameter_set("vh_lamp_p%d" % j, Vector4(l[0].x, l[0].y, l[0].z, l[3]))
		RenderingServer.global_shader_parameter_set("vh_lamp_c%d" % j, Vector4(c.r, c.g, c.b, 0.0))
	RenderingServer.global_shader_parameter_set("vh_lamp_n", n)

func _add_lamp(kind: Array, at: Vector3) -> void:
	lamps.append([at, kind[0], kind[1], kind[2]])

## Where the sun is on screen, for the grade's god rays.
func _update_sun_on_screen() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or post == null: return
	var to_sun: Vector3 = look.to_sun.normalized()
	var p := cam.global_position + to_sun * 1000.0
	var uv := Vector2(0.5, -1.0)
	var vis := 0.0
	if to_sun.y > -0.02 and not cam.is_position_behind(p):
		uv = cam.unproject_position(p) / get_viewport().get_visible_rect().size
		vis = clampf(1.0 - (maxf(absf(uv.x - 0.5), absf(uv.y - 0.5)) - 0.5) / 0.35, 0.0, 1.0)
	post.material.set_shader_parameter("sun_uv", uv)
	post.material.set_shader_parameter("sun_vis", vis)

# --- terrain: GPU-displaced tiles, two LODs, one heightmap collider ------------------------------------
func _grid_mesh(n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := n + 3
	for j in m:
		for i in m:
			var skirt := 1.0 if i == 0 or j == 0 or i == m - 1 or j == m - 1 else 0.0
			st.set_uv2(Vector2(0.0, skirt))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(clampi(i - 1, 0, n) * TILE / n, 0.0, clampi(j - 1, 0, n) * TILE / n))
	for j in m - 1:
		for i in m - 1:
			var a := j * m + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + m)
			st.add_index(a + 1); st.add_index(a + m + 1); st.add_index(a + m)
	var mesh := st.commit()
	mesh.custom_aabb = AABB(Vector3(-2, -30, -2), Vector3(TILE + 4, 90, TILE + 4))
	return mesh

func _terrain() -> void:
	var mat := _mat("res://shaders/foliage/ground.gdshader")
	mat.set_shader_parameter("field_tex", data.field_tex)
	mat.set_shader_parameter("paved_tex", data.paved_tex)
	mat.set_shader_parameter("map_rect", data.field_rect)
	mat.set_shader_parameter("paved_rect", data.paved_rect)
	mat.set_shader_parameter("texel", Vector2(1.0 / data.nx, 1.0 / data.nz))
	mat.set_shader_parameter("cell", data.res)
	var near := _grid_mesh(int(TILE / data.res))
	var far := _grid_mesh(8)
	for tz in int(ceil(data.dep / TILE)):
		for tx in int(ceil(data.w / TILE)):
			for lod in [[near, 0.0, TILE_LOD, true], [far, TILE_LOD, 0.0, false]]:
				var mi := _mesh(lod[0], mat, lod[3])
				mi.position = Vector3(data.x0 + tx * TILE, 0.0, data.z0 + tz * TILE)
				mi.visibility_range_begin = lod[1]
				mi.visibility_range_end = lod[2]
	var hs := PackedFloat32Array()
	hs.resize(data.nx * data.nz)
	for i in hs.size(): hs[i] = data.field[i * 4] / data.res
	var shape := HeightMapShape3D.new()
	shape.map_width = data.nx
	shape.map_depth = data.nz
	shape.map_data = hs
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3.ONE * data.res
	body.add_child(col)
	body.position = Vector3(data.x0 + (data.nx - 1) * data.res * 0.5, 0.0, data.z0 + (data.nz - 1) * data.res * 0.5)
	add_child(body)

# --- water (water.ts): ribbons per reach (reflections traced in the shader), falls sheet + mist ---------------------
func _water() -> void:
	var falls: Dictionary = data.d.river.get("falls", {})
	var foam := Vector2(falls.bottom[0], falls.bottom[2]) if falls else Vector2(0, -1e5)
	for r in data.d.river.reaches:
		_water_ribbon(r.points, 3.5, 0.42 if r.id == "upper" else 0.32, foam)
	if falls: _waterfall(falls)

func _water_ribbon(pts: Array, margin: float, speed: float, foam: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across := 6
	var prev: Array = []
	for i in pts.size():
		var p := Vector2(pts[i][0], pts[i][1])
		var a := Vector2(pts[maxi(i - 1, 0)][0], pts[maxi(i - 1, 0)][1])
		var b := Vector2(pts[mini(i + 1, pts.size() - 1)][0], pts[mini(i + 1, pts.size() - 1)][1])
		var t := (b - a).normalized()
		var n := t.orthogonal() * (float(pts[i][2]) + margin)
		var row: Array = []
		for k in across + 1:
			var q := p - n + n * 2.0 * k / across
			row.append([Vector3(q.x, float(pts[i][3]), q.y), t * speed])
		if not prev.is_empty():
			for k in across:
				for v in [prev[k], row[k + 1], prev[k + 1], prev[k], row[k], row[k + 1]]:
					st.set_uv2(v[1])
					st.set_normal(Vector3.UP)
					st.add_vertex(v[0])
		prev = row
	var mat := _mat("res://shaders/foliage/water.gdshader")
	mat.set_shader_parameter("field_tex", data.field_tex)
	mat.set_shader_parameter("map_rect", data.field_rect)
	mat.set_shader_parameter("t_normal", VHTex.get_tex("water_normal"))
	mat.set_shader_parameter("foam_center", foam)
	var mi := _mesh(st.commit(), mat, false, LAYER_WATER)
	mi.sorting_offset = 2.0

## The falls sheet (curved drop with a forward bulge) and its rising spray mist.
func _waterfall(f: Dictionary) -> void:
	var top := WorldData.v3(f.top)
	var bot := WorldData.v3(f.bottom)
	var fwd := Vector3(bot.x - top.x, 0, bot.z - top.z).normalized()
	var across := Vector3(-fwd.z, 0, fwd.x)
	var W: float = f.width
	var drop := top.y - bot.y
	var run := Vector2(bot.x - top.x, bot.z - top.z).length()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var su := 18
	var sv := 20
	var grid: Array = []
	for v in sv + 1:
		var row: Array = []
		for u in su + 1:
			var fu := float(u) / su
			var fv := float(v) / sv
			var bulge := -0.35 * (1.0 - pow(2.0 * fu - 1.0, 2.0)) * (drop / 2.6)
			row.append([top + across * (fu - 0.5) * W + fwd * (run * fv + bulge * (1.0 - fv * 0.5)) + Vector3(0, 0.03 - drop * fv * fv, 0), Vector2(fu, fv)])
		grid.append(row)
	for v in sv:
		for u in su:
			for c in [grid[v][u], grid[v + 1][u], grid[v][u + 1], grid[v][u + 1], grid[v + 1][u], grid[v + 1][u + 1]]:
				st.set_uv(c[1])
				st.add_vertex(c[0])
	st.generate_normals()
	var sheet := _mesh(st.commit(), _mat("res://shaders/vh/waterfall.gdshader"), false, LAYER_WATER)
	sheet.sorting_offset = 3.0
	var q := QuadMesh.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = 12
	for i in 12:
		mm.set_instance_transform(i, Transform3D())
		var p := bot + across * rng.randf_range(-W * 0.45, W * 0.45) + fwd * rng.randf_range(0.5, 3.5)
		mm.set_instance_custom_data(i, Color(p.x, bot.y + 0.2, p.z, float(i) / 12.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mist := _mat("res://shaders/vh/mist.gdshader")
	mist.set_shader_parameter("t_glow", VHTex.get_tex("glow"))
	mmi.material_override = mist
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(bot - Vector3(30, 10, 30), Vector3(60, 40, 60))
	mmi.layers = LAYER_WATER
	add_child(mmi)

# --- buildings ------------------------------------------------------------------------------------------------
func _sites() -> void:
	var manifest := {}
	# the kept masters and the quarter's generated buildings, keyed by file name
	for mp in ["res://assets/buildings/manifest.json", "res://assets/quarter/manifest.json"]:
		if not FileAccess.file_exists(mp): continue
		var m = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if m is Dictionary: manifest.get_or_add("buildings", {}).merge(m.get("buildings", {}))
	for raw in data.d.sites:
		if raw.get("role", "") == "plot":
			_plot(raw)
			continue
		var def: Dictionary = raw.duplicate()
		def.pos = WorldData.v2(raw.pos)
		def.face = WorldData.v2(raw.get("face", [0, 1]))
		var site := SiteScript.new()
		site.setup(def, manifest)
		add_child(site)
		site.settle(float(raw.y) if raw.has("y") else height_at(def.pos.x, def.pos.y))
		sites.append(site)
		block(def.pos, 0.0, site.half2 + Vector2(1.0, 1.0))
		# a light over the entrance, just off the facade
		_add_lamp(LAMP_DOOR, site.door - Vector3(site.face.x, 0.0, site.face.y) * 1.3 + Vector3(0, 2.9, 0))
		if Strings.SIGNS.has(str(raw.id)):
			_sign(Strings.SIGNS[str(raw.id)], site.door - Vector3(site.face.x, 0.0, site.face.y) * 1.45 + Vector3(0, 3.35, 0), site.face)

## Lettering on a facade: the shop's word over its door, facing out along `face`.
func _sign(text: String, at: Vector3, face: Vector2) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/Nunito.ttf")
	l.font_size = 72
	l.pixel_size = 0.0055
	l.modulate = Color("3a3d40")
	l.outline_modulate = Color("f6efe2")
	l.outline_size = 14
	l.shaded = false
	l.double_sided = false
	add_child(l)
	l.position = at
	l.rotation.y = atan2(face.x, face.y)

## An open plot waiting for a town project or a player's business: its lot is left clear, with a board at the
## front saying what it is for.
func _plot(raw: Dictionary) -> void:
	var p := WorldData.v2(raw.pos)
	var f := WorldData.v2(raw.get("face", [0, 1])).normalized()
	var fr := WorldData.v2(raw.get("frame", [3, 4]))
	block(p, 0.0, WorldData.v2(raw.get("half", [3, 4])))
	var front := p + f * (fr.y - 0.6)
	var path := "res://assets/props/covered_jobs_and_town_noticeboard.glb"
	if ResourceLoader.exists(path):
		var n: Node3D = (load(path) as PackedScene).instantiate()
		_faithful(n)
		_place(n, front, f)
	_sign(Strings.PLOT.get(str(raw.get("status", "lease")), Strings.PLOT.lease), Vector3(front.x, height_at(front.x, front.y) + 2.75, front.y) + Vector3(f.x, 0, f.y) * 0.25, f)

# --- landmarks (docs/superpowers/specs/2026-10-29-tallyport-level-design.md) -------------------------------------
var bakery: Node3D
var cast_people := {}            # cast id -> Person

func _kit_prop(kind: String, p: Vector2, face: Vector2, cfg := {}) -> Node3D:
	if kit == null or not kit.has_method(kind): return null
	var n: Node3D = kit.call(kind, cfg)
	_vh_kit(n)
	_place(n, p, face)
	block(p, 0.9)
	return n

func _landmarks() -> void:
	var L: Dictionary = data.d.get("landmarks", {})
	if L.has("old_fig"):
		var fp := WorldData.v2(L.old_fig.pos)
		_plant("fig", fp, 0.9)
		var r := float(L.old_fig.get("bench_radius", 5.0))
		for i in 6:
			var a := TAU * i / 6.0 + 0.26
			_kit_prop("bench", fp + Vector2(sin(a), cos(a)) * r, Vector2(sin(a), cos(a)), {"length": 2.2, "seed": i})
	if L.has("jetty") and kit:
		var a := WorldData.v2(L.jetty.from)
		var b := WorldData.v2(L.jetty.to)
		var f := (b - a).normalized()
		var wl := data.water_z(b)
		var j: Node3D = kit.dock({"length": a.distance_to(b) + 2.0, "width": 3.0, "deck_height": maxf(height_at(a.x, a.y) - wl + 0.1, 1.0), "water_depth": 3.0, "ladder": true, "seed": 3})
		_vh_kit(j)
		_place(j, (a + b) * 0.5, f, wl)
		var boat: Node3D = kit.rowboat({"length": 3.6, "paint": Color("2f6f6a"), "seed": 4})
		_vh_kit(boat)
		_place(boat, b - f * 2.5 + f.orthogonal() * 2.8, f, wl + 0.05)
		_kit_prop("lamp", WorldData.v2(L.jetty.bell), -f, {"height": 3.2})
	if L.has("fountain"): _fountain(WorldData.v2(L.fountain.pos))
	if L.has("bakery_stall"):
		bakery = Node3D.new()
		add_child(bakery)
		_shut_bakery()
		var bp := WorldData.v2(L.bakery_stall.pos)
		var spot := SpotScript.new()
		add_child(spot)
		spot.setup({"id": "bakery_stall", "name": "the bakery stall", "role": "bakery", "verb": "Visit"}, Vector3(bp.x, height_at(bp.x, bp.y), bp.y))
	if L.has("tally_steps") and kit:
		var top := WorldData.v2(L.tally_steps.top)
		var foot := WorldData.v2(L.tally_steps.foot)
		var h_top := height_at(top.x, top.y)
		var h_foot := -0.4
		var n := maxi(4, int(round((h_top - h_foot) / 0.185)))
		var st: Node3D = kit.stair({"steps": n, "width": float(L.tally_steps.width), "rise": (h_top - h_foot) / n,
			"run": top.distance_to(foot) / n, "cheeks": true, "railing": "none", "seed": 5})
		_vh_kit(st)
		add_child(st)
		st.position = Vector3((top.x + foot.x) * 0.5, h_foot, (top.y + foot.y) * 0.5)
		st.rotation.y = atan2(top.x - foot.x, top.y - foot.y) + PI    # the top step towards the square
	if L.has("terrace_wall") and kit:
		var pts := PackedVector3Array()
		var low := INF
		for q in L.terrace_wall.points: low = minf(low, height_at(q[0], q[1]))
		for q in L.terrace_wall.points: pts.append(Vector3(q[0], low - 0.3, q[1]))
		var tw: Node3D = kit.retaining_wall(pts, float(L.terrace_wall.top) - low + 0.3, {"seed": 8, "thickness": 0.7})
		_vh_kit(tw)
		add_child(tw)
	if L.has("ledger_wall"):
		_ledger_wall(WorldData.v2(L.ledger_wall.from), WorldData.v2(L.ledger_wall.to))
		var a := WorldData.v2(L.ledger_wall.from)
		var spot := SpotScript.new()
		add_child(spot)
		spot.setup({"id": "ledger", "name": "the Ledger Wall", "role": "ledger", "verb": "Carve on"}, Vector3(a.x + 1.2, height_at(a.x + 1.2, a.y - 1.5), a.y - 1.5))
	_cast()

## The Ledger Wall: a low stone wall along the top of the Tally Steps, carved with the town's firsts.
const LEDGER_TOWN := ["B. & L. Okafor · the ferry paid off", "M. Adeyemi · first rent", "The Lund bakery · opened",
	"Kofi M. · first wage", "Ada & Tomás · first stall opened", "Elias B. · the timetables kept"]
var _ledger_labels: Node3D

func _ledger_wall(a: Vector2, b: Vector2) -> void:
	var len := minf(a.distance_to(b), 15.0)
	var dir := (b - a).normalized()
	var b2 := a + dir * len
	var base := height_at(a.x, a.y)
	if kit:
		var w: Node3D = kit.retaining_wall(PackedVector3Array([Vector3(a.x, base - 0.1, a.y), Vector3(b2.x, base - 0.1, b2.y)]), 1.5, {"seed": 17, "thickness": 0.5})
		_vh_kit(w)
		add_child(w)
	_ledger_labels = Node3D.new()
	add_child(_ledger_labels)
	_ledger_carvings(a, dir, len, base)

func _ledger_carvings(a: Vector2, dir: Vector2, len: float, base: float) -> void:
	var lines: Array = []
	for t in LEDGER_TOWN: lines.append([t, Color("4a4237")])
	var right := Vector2(-dir.y, dir.x)          # the face towards the steps
	var font := load("res://assets/fonts/Nunito.ttf")
	for i in lines.size():
		var along := 1.2 + (i % 5) * (len - 2.4) / 4.0
		var row := i / 5
		var p := a + dir * along + right * 0.28
		var l := Label3D.new()
		l.text = lines[i][0]
		l.font = font
		l.font_size = 40
		l.pixel_size = 0.0045
		l.modulate = lines[i][1]
		l.outline_size = 0
		l.width = 260.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.shaded = false
		_ledger_labels.add_child(l)
		l.position = Vector3(p.x, base + 1.15 - row * 0.45, p.y)
		l.rotation.y = atan2(right.x, right.y)

## Ingrid's bakery stall, shut: a crate and a chalkboard.
func _shut_bakery() -> void:
	var L: Dictionary = data.d.landmarks.bakery_stall
	var p := WorldData.v2(L.pos)
	var f := WorldData.v2(L.face)
	var y := height_at(p.x, p.y)
	if kit:
		var n: Node3D = kit.crate({"seed": 12})
		_vh_kit(n)
		bakery.add_child(n)
		n.position = Vector3(p.x, y, p.y)
		n.rotation.y = -Vector2(0, 1).angle_to(f)
		var board: Node3D = kit.chalkboard({"seed": 13})
		_vh_kit(board)
		bakery.add_child(board)
		board.position = Vector3(p.x, y, p.y) + Vector3(f.x, 0, f.y) * 1.4
		board.rotation.y = -Vector2(0, 1).angle_to(f)
	var l := Label3D.new()
	l.text = "Bakery · reopening soon"
	l.font = load("res://assets/fonts/Nunito.ttf")
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = Color("3a3d40")
	l.outline_modulate = Color("f6efe2")
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	bakery.add_child(l)
	l.position = Vector3(p.x, y + 2.6, p.y)

func _fountain(p: Vector2) -> void:
	var mb := MeshUtil.new()
	var stone := Color("d9d0bf")
	var water := Color("6fa8c4")
	var t := MeshUtil.xf(Vector3.ZERO)
	mb.cyl("solid", t, 2.3, 2.3, 0.55, 18, stone)
	mb.cyl("solid", MeshUtil.xf(Vector3(0, 0.5, 0)), 2.05, 2.05, 0.04, 18, water, true, true)
	mb.cyl("solid", t, 0.32, 0.26, 1.5, 10, stone)
	mb.cyl("solid", MeshUtil.xf(Vector3(0, 1.45, 0)), 1.0, 0.7, 0.22, 14, stone)
	mb.cyl("solid", MeshUtil.xf(Vector3(0, 1.62, 0)), 0.85, 0.85, 0.03, 14, water, true, true)
	mb.sphere("solid", MeshUtil.xf(Vector3(0, 1.85, 0)), 0.22, stone)
	var n := mb.to_node("Fountain")
	_vh_kit(n)
	add_child(n)
	n.position = Vector3(p.x, height_at(p.x, p.y), p.y)
	block(p, 2.6)

## The named townsfolk (scripts/life/cast.gd) at their posts: beside the door of the place they keep, or at their
## landmark; each turns to the player nearby and can be talked to.
func _cast() -> void:
	var L: Dictionary = data.d.get("landmarks", {})
	var outfits := {"harbourmaster": ["Suit_Female", {"top": "2f7c7a"}], "kofi": ["Worker_Male", {"top": "e07a3a", "top2": "f2c14e"}],
		"mei": ["Chef_Female", {"hair": "8a8a8a"}], "elias": ["OldClassy_Male", {"top": "7a6a4f", "hair": "d8d8d8"}],
		"priya": ["Worker_Female", {"top": "3f5f8f"}], "arthur": ["Suit_Male", {"top": "eaf0f4"}],
		"bo": ["Cowboy_Male", {"top": "2f4a5c", "hat": "3b3f45", "hair": "e0e0e0"}], "sam": ["Casual2_Male", {"top": "e9b23c"}],
		"dario": ["Suit_Male", {"top": "f4ead8"}], "yusuf": ["Chef_Male", {"top": "6b4a32"}],
		"ingrid": ["Chef_Hat", {"hair": "d9c08a"}]}
	var by_role := {}
	for site in sites: by_role[site.def.get("role", "")] = site
	var skins := PersonScript.SKINS
	var i := 0
	for id in CastScript.PEOPLE:
		var post: String = CastScript.PEOPLE[id].post
		var at := Vector3.INF
		var face := Vector2(0, 1)
		if by_role.has(post):
			var site: Node3D = by_role[post]
			var side := Vector2(-site.face.y, site.face.x)
			var q: Vector2 = Vector2(site.door.x, site.door.z) + side * 2.2
			at = Vector3(q.x, height_at(q.x, q.y), q.y)
			face = site.face
		elif post == "jetty" and L.has("jetty"):
			var q := WorldData.v2(L.jetty.bell) + Vector2(1.0, 0.6)
			at = Vector3(q.x, height_at(q.x, q.y), q.y)
			face = Vector2(0, 1)
		elif post in ["fig", "square"] and L.has("old_fig"):
			var a := 1.3 if post == "fig" else 3.6
			var q := WorldData.v2(L.old_fig.pos) + Vector2(sin(a), cos(a)) * (float(L.old_fig.bench_radius) + 1.6)
			at = Vector3(q.x, height_at(q.x, q.y), q.y)
			face = Vector2(sin(a), cos(a))
		elif post == "bakery" and L.has("bakery_stall"):
			var q := WorldData.v2(L.bakery_stall.pos) + WorldData.v2(L.bakery_stall.face) * -1.2
			at = Vector3(q.x, height_at(q.x, q.y), q.y)
			face = WorldData.v2(L.bakery_stall.face)
		if at == Vector3.INF: continue
		var o: Array = outfits.get(id, ["Casual_Male", {}])
		var look: Dictionary = (o[1] as Dictionary).duplicate()
		look.merge({"skin": skins[(i * 3 + 1) % skins.size()], "hair": PersonScript.HAIRS[i % 5]}, false)
		var person: Node3D = PersonScript.new()
		add_child(person)
		person.setup(o[0], look)
		person.position = at
		person.rotation.y = atan2(face.x, face.y)
		cast_people[id] = person
		var spot := SpotScript.new()
		add_child(spot)
		spot.setup({"id": id, "name": CastScript.PEOPLE[id].name, "role": "talk", "verb": "Talk to"}, at)
		spot.set_meta("person", person)
		block(Vector2(at.x, at.z), 0.6)
		i += 1

func _update_cast(delta: float) -> void:
	if player == null: return
	for id in cast_people:
		var person: Node3D = cast_people[id]
		var to := player.global_position - person.position
		var near := to.length() < 7.0
		var yaw := wrapf(atan2(to.x, to.z) - person.rotation.y, -PI, PI)
		person.look_target = Vector2(clampf(yaw, -1.1, 1.1), 0.0) if near else Vector2.ZERO
		person.step(0.0, delta)

# --- townsfolk: the life director walking villagers on the paving's own graph ------------------------------------
var life: Node3D

## Waypoints every 9 m on the paving, linked where the straight walk between them stays on paving and clear of
## buildings; the biggest connected web is kept. Points of interest: benches to sit on, doors to browse at,
## open paving to chat on, the river's edge to look out from.
func _life() -> void:
	var c := Vector2(data.x0 + data.w * 0.5, data.z0 + data.dep * 0.5)
	var reach := float(data.d.get("life", {}).get("radius", 140.0))
	var pts: Array[Vector3] = []
	var step := 4.5
	var z := data.z0 + 4.0
	while z < data.z0 + data.dep - 4.0:
		var x := data.x0 + 4.0
		while x < data.x0 + data.w - 4.0:
			var p := Vector2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0))
			x += step
			if p.distance_to(c) > reach or data.pave_dist(p) > 0.2 or data.water_sd(p) < 1.0 or blocked(p, 0.6): continue
			pts.append(Vector3(p.x, height_at(p.x, p.y), p.y))
		z += step
	var clear := func(a: Vector3, b: Vector3) -> bool:
		for k in range(1, 6):
			var q := Vector2(lerpf(a.x, b.x, k / 6.0), lerpf(a.z, b.z, k / 6.0))
			if data.pave_dist(q) > 0.8 or blocked(q, 0.4): return false
		return true
	var edges: Array = []
	var nb: Array = []
	nb.resize(pts.size())
	for i in pts.size(): nb[i] = []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d := pts[i].distance_to(pts[j])
			if d < 7.0 and clear.call(pts[i], pts[j]):
				edges.append(Vector2i(i, j))
				nb[i].append(j)
				nb[j].append(i)
	# keep the largest connected web
	var comp := PackedInt32Array()
	comp.resize(pts.size())
	comp.fill(-1)
	var best := -1
	var best_n := 0
	for i in pts.size():
		if comp[i] >= 0: continue
		var stack := [i]
		comp[i] = i
		var n := 0
		while stack:
			var k: int = stack.pop_back()
			n += 1
			for m in nb[k]:
				if comp[m] < 0:
					comp[m] = i
					stack.append(m)
		if n > best_n:
			best_n = n
			best = i
	if best_n < 4: return
	var keep: Array[Vector3] = []
	var remap := {}
	for i in pts.size():
		if comp[i] == best:
			remap[i] = keep.size()
			keep.append(pts[i])
	var kept_edges: Array = []
	for e in edges:
		if remap.has(e.x) and remap.has(e.y): kept_edges.append(Vector2i(remap[e.x], remap[e.y]))
	var pois: Array = []
	for pr in data.d.props:
		var name_: String = str(pr.get("glb", pr.get("kit", "")))
		if "bench" in name_:
			var bp := WorldData.v2(pr.pos)
			var f := WorldData.v2(pr.get("face", [0, 1]))
			pois.append({"kind": "sit", "pos": Vector3(bp.x, height_at(bp.x, bp.y), bp.y) + Vector3(f.x, 0, f.y) * 0.45, "facing": atan2(f.x, f.y), "slots": 2, "spacing": 0.7})
	for site in sites:
		var dp: Vector3 = site.door + Vector3(site.face.x, 0, site.face.y) * 0.6
		pois.append({"kind": "shop", "pos": dp, "facing": atan2(-site.face.x, -site.face.y), "slots": 2, "spacing": 0.9})
	for i in mini(6, keep.size()):
		var q: Vector3 = keep[rng.randi() % keep.size()]
		pois.append({"kind": "chat", "pos": q, "facing": rng.randf() * TAU, "slots": 3, "spacing": 1.1})
	for i in 4:
		var q: Vector3 = keep[rng.randi() % keep.size()]
		var w := Vector2(data.water_sd(Vector2(q.x + 1, q.z)) - data.water_sd(Vector2(q.x - 1, q.z)), data.water_sd(Vector2(q.x, q.z + 1)) - data.water_sd(Vector2(q.x, q.z - 1)))
		if data.water_sd(Vector2(q.x, q.z)) < 25.0: pois.append({"kind": "look", "pos": q, "facing": atan2(-w.x, -w.y), "slots": 1})
	life = LifeDirectorScript.new()
	life.height_at = func(x: float, z_: float) -> float: return height_at(x, z_)
	add_child(life)
	life.setup({"seed": 7, "count": int(data.d.get("life", {}).get("count", 14)), "waypoints": keep, "edges": kept_edges, "points_of_interest": pois})
	print("life: %d villagers on %d waypoints, %d links, %d points of interest" % [life.villagers.size(), keep.size(), kept_edges.size(), pois.size()])

# --- street kit + original props (positions baked from v3), re-lit with the reference materials ------------------
func _place(n: Node3D, pos2: Vector2, face: Vector2, y := INF) -> void:
	add_child(n)
	n.position = Vector3(pos2.x, height_at(pos2.x, pos2.y) if y == INF else y, pos2.y)
	n.rotation.y = -Vector2(0, 1).angle_to(face.normalized())

## Authored-colour models (GLB props): the building shader with vertex colours.
func _faithful(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var src: Material = n.mesh.surface_get_material(i)
			var m := _mat("res://shaders/vh/building.gdshader")
			m.set_shader_parameter("use_vcol", n.mesh is ArrayMesh and (n.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0)
			if src is BaseMaterial3D: m.set_shader_parameter("base", (src as BaseMaterial3D).albedo_color)
			n.set_surface_override_material(i, m)
	for c in n.get_children(): _faithful(c)

## Kit pieces (vertex-coloured MeshUtil meshes): PBR with their colours, emissive parts as LEDs.
func _vh_kit(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var glow: bool = n.mesh.surface_get_material(i) == MeshUtil.mat("glow")
			n.set_surface_override_material(i, _led(Color("ffd7a6"), 3.2) if glow else _pbr(Color.WHITE, 0.8, 0.0, true))
	for c in n.get_children(): _vh_kit(c)

func _props() -> void:
	for pr in data.d.props:
		var p := WorldData.v2(pr.pos)
		var face := WorldData.v2(pr.get("face", [0, 1]))
		if pr.has("kit"):
			if kit == null or not kit.has_method(pr.kit): continue
			var kn: Node3D = kit.call(pr.kit, pr.get("cfg", {}).duplicate())
			if kn == null: continue
			_vh_kit(kn)
			_place(kn, p, face)
			block(p, 1.1)
			if pr.kit == "lamp":
				var head := Vector3(p.x, height_at(p.x, p.y) + float(pr.get("cfg", {}).get("height", 3.0)) - 0.3, p.y)
				_add_lamp(LAMP_STREET, head)
				lamp_heads.append(head)
			continue
		var path := "res://assets/props/%s.glb" % pr.glb
		if not ResourceLoader.exists(path): continue
		var n: Node3D = (load(path) as PackedScene).instantiate()
		_faithful(n)
		_place(n, p, face)
		block(p, 1.4)

# --- crossings: ferry bridge, river landing, the skybridge (structures.ts bridge) --------------------------------------
func _crossings() -> void:
	if kit and data.d.has("ferry_bridge"):
		var b: Dictionary = data.d.ferry_bridge
		var p := WorldData.v2(b.pos)
		var f := WorldData.v2(b.face).normalized()
		var wl := data.water_z(p)
		var half := float(b.length) * 0.5 + 1.0
		var top := maxf(height_at(p.x + f.x * half, p.y + f.y * half), height_at(p.x - f.x * half, p.y - f.y * half))
		var fb: Node3D = kit.dock({"length": half * 2.0, "width": 3.4, "deck_height": maxf(top - wl + 0.15, 1.2), "water_depth": 3.0, "ladder": false, "seed": 5})
		_vh_kit(fb)
		_place(fb, p, f, wl)
		var l: Dictionary = data.d.landing
		var lp := WorldData.v2(l.pos)
		var g := Vector2(data.water_sd(lp + Vector2(1, 0)) - data.water_sd(lp - Vector2(1, 0)), data.water_sd(lp + Vector2(0, 1)) - data.water_sd(lp - Vector2(0, 1)))
		var dir := -g.normalized()
		var c := lp + dir * 3.0
		var jetty: Node3D = kit.dock({"length": 9.0, "width": 3.0, "seed": 9})
		_vh_kit(jetty)
		_place(jetty, c, dir, data.water_z(c) + 0.45)
		var boat: Node3D = kit.rowboat({"length": 3.4, "paint": Color("8a6746"), "seed": 2})
		_vh_kit(boat)
		_place(boat, c + dir * 3.5 + dir.orthogonal() * 3.0, dir.orthogonal(), data.water_z(c) + 0.05)
		block(c, 5.0)
	if data.d.has("skybridge"): _skybridge()

func _skybridge() -> void:
	var sb: Dictionary = data.d.skybridge
	var a := WorldData.v2(sb.a)
	var b := WorldData.v2(sb.b)
	var L := a.distance_to(b)
	var y0: float = sb.deck_y
	var arch: float = sb.arch
	var deck_y := func(u: float) -> float: return y0 + arch * (1.0 - pow(u * 2.0 - 1.0, 2.0))
	var bags: Dictionary = VHProps.bridge(L, float(sb.width), deck_y)
	var root := Node3D.new()
	add_child(root)
	var dir := (b - a) / L
	root.global_transform = Transform3D(Basis(Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(-dir.y, 0, dir.x)), Vector3(a.x, 0, a.y))
	for k in [["paving", _pbr(Color("a39e95"), 0.8, 0.0, false, "concrete", 0.32, 0.6)], ["concrete", _pbr(Color("b3aea5"), 0.85, 0.0, false, "concrete", 0.25, 0.8)],
			["metal", _pbr(Color("232528"), 0.38, 0.85)], ["led_soft", _led(Color("ffd5a2"), 1.6)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (bags[k[0]] as VHProps.Bag).build()
		mi.material_override = k[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k[0] == "led_soft" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	var body := StaticBody3D.new()
	root.add_child(body)
	var n := 28
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var ya: float = deck_y.call(u0)
		var yb: float = deck_y.call(u1)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(L / n + 0.05, 0.3, float(sb.width))
		cs.shape = bs
		cs.position = Vector3(L * (u0 + u1) * 0.5, (ya + yb) * 0.5 - 0.15, 0)
		cs.rotation.z = atan2(yb - ya, L / n)
		body.add_child(cs)
		for s in [-1.0, 1.0]:
			var rail := CollisionShape3D.new()
			var rb := BoxShape3D.new()
			rb.size = Vector3(L / n + 0.05, 1.2, 0.15)
			rail.shape = rb
			rail.position = Vector3(L * (u0 + u1) * 0.5, (ya + yb) * 0.5 + 0.6, s * (float(sb.width) * 0.5 - 0.06))
			body.add_child(rail)

# --- lit trails: the reference's LED bollards + warm ground pools ----------------------------------------------------------
func _trails() -> void:
	var metal := VHProps.Bag.new()
	var led := VHProps.Bag.new()
	var pools := VHProps.Bag.new()
	var h := func(x: float, z: float) -> float: return height_at(x, z)
	var count := 0
	for t in data.d.get("trails", []):
		if not t.get("glow", false): continue
		var off: float = float(t.width) * 0.5 + 0.6
		var carry := 6.0
		var k := 0
		for i in t.points.size() - 1:
			var a := WorldData.v2(t.points[i])
			var b := WorldData.v2(t.points[i + 1])
			var seg := a.distance_to(b)
			var dir := (b - a) / seg
			var s := carry
			while s < seg:
				var q := a + dir * s + dir.orthogonal() * off * (1.0 if k % 2 == 0 else -1.0)
				if data.water_sd(q) > 0.8 and not blocked(q, 0.3):
					var p := Vector3(q.x, height_at(q.x, q.y), q.y)
					VHProps.bollard(metal, led, p)
					VHProps.light_pool(pools, p, h)
					_add_lamp(LAMP_BOLLARD, p + Vector3(0, 1.2, 0))
					block(q, 0.3)
					count += 1
				k += 1
				s += 16.0
			carry = s - seg
	_mesh(metal.build(), _pbr(Color("232528"), 0.38, 0.85))
	_mesh(led.build(), _led(Color("ffd5a2"), 7.0), false)
	var pm := _mat("res://shaders/vh/pool.gdshader")
	pm.set_shader_parameter("t_glow", VHTex.get_tex("glow"))
	_mesh(pools.build(), pm, false, LAYER_WATER).sorting_offset = 1.0
	print("bollards: ", count)

## The street lamps at night: warm ground glow (a decal, standing in for the lamps beyond the lit few)
## and a halo round each lantern.
func _lamp_glows() -> void:
	if lamp_heads.is_empty(): return
	var pools := VHProps.Bag.new()
	var h := func(x: float, z: float) -> float: return height_at(x, z)
	var box := AABB(lamp_heads[0], Vector3.ZERO)
	for head in lamp_heads:
		VHProps.light_pool(pools, Vector3(head.x, height_at(head.x, head.z), head.z), h, 6.0)
		box = box.expand(head)
	var pm := _mat("res://shaders/vh/pool.gdshader")
	pm.set_shader_parameter("t_glow", VHTex.get_tex("glow"))
	pm.set_shader_parameter("drive", 1)
	pm.set_shader_parameter("color", Color("ffc27a"))
	pm.set_shader_parameter("energy", 0.45)
	_mesh(pools.build(), pm, false, LAYER_WATER).sorting_offset = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = lamp_heads.size()
	for i in lamp_heads.size():
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(lamp_heads[i].x, lamp_heads[i].y, lamp_heads[i].z, 2.4))
	halos = MultiMeshInstance3D.new()
	halos.multimesh = mm
	var hm := _mat("res://shaders/vh/halo.gdshader")
	hm.set_shader_parameter("t_glow", VHTex.get_tex("glow"))
	halos.material_override = hm
	halos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halos.custom_aabb = box.grow(3.0)
	add_child(halos)

# --- rocks (rocks.ts): shoreline stones + pebbles, mid-river stones, falls lip, gorge cliff blocks, meadow stones ------
func _rocks() -> void:
	var nr := VHNoise.rng(2024)
	var R := func(a: float, b: float) -> float: return a + (b - a) * nr.next()
	var list: Array = []       # [x, z, sx, sy, sz, yaw, tilt, sink, variant, collide]
	var pebbles: Array = []
	var add := func(x: float, z: float, sx: float, sy: float, sz: float, yaw: float, tilt: float, sink: float, v: int, collide: bool) -> void:
		list.append([x, z, sx, sy, sz, yaw, tilt, sink, v, collide])
	for r in data.d.river.reaches:
		var pts: Array = r.points
		var gorge: bool = r.id == "gorge"
		var acc := 0.0
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1][0], pts[i - 1][1])
			var b := Vector2(pts[i][0], pts[i][1])
			acc += a.distance_to(b)
			var step: float = R.call(3.5, 5.5) if gorge else R.call(1.6, 3.2)
			if acc < step: continue
			acc = 0.0
			var nrm := (b - a).normalized().orthogonal()
			var hw := float(pts[i][2])
			for side in [-1.0, 1.0]:
				if gorge:
					var q: Vector2 = b + nrm * side * (hw + R.call(1.5, 3.8))
					var s: float = R.call(2.6, 5.0)
					add.call(q.x, q.y, s * R.call(1.2, 1.8), s * R.call(0.7, 1.1), s * R.call(0.8, 1.2), atan2(nrm.x, nrm.y) + R.call(-0.3, 0.3), R.call(-0.15, 0.15), 0.45, int(R.call(0, 8)), true)
					continue
				if nr.next() < 0.18 or not data.inside(b, 4.0): continue
				var q: Vector2 = b + nrm * side * (hw + R.call(-0.6, 1.4))
				if height_at(q.x, q.y) - data.water_z(q) > 1.2: continue    # a quay wall, not a shore
				var big := nr.next() < 0.25
				var s: float = R.call(0.8, 1.5) if big else R.call(0.3, 0.75)
				add.call(q.x, q.y, s * R.call(1.0, 1.5), s * R.call(0.5, 0.8), s * R.call(0.9, 1.3), R.call(0, 6.28), R.call(-0.2, 0.2), R.call(0.3, 0.5), -1, s > 0.55)
				for p in 4:
					pebbles.append([q.x + R.call(-1.5, 1.5), q.y + R.call(-1.5, 1.5), R.call(0.05, 0.16), R.call(0.04, 0.1), R.call(0.05, 0.15), R.call(0, 6.28), 0.0, 0.4, -1, false])
	var tries := 0
	var mids := 0
	while mids < 14 and tries < 4000:
		tries += 1
		var q := Vector2(rng.randf_range(data.x0, data.x0 + data.w), rng.randf_range(data.z0, data.z0 + data.dep))
		var ws := data.water_sd(q)
		if ws < -2.5 and ws > -6.0:
			var s := rng.randf_range(0.6, 1.1)
			add.call(q.x, q.y, s * 1.3, s * 0.7, s, R.call(0, 6.28), 0.0, 0.45, -1, false)
			mids += 1
	var f: Dictionary = data.d.river.get("falls", {})
	var ft := WorldData.v3(f.top) if f else Vector3.ZERO
	var fb := WorldData.v3(f.bottom) if f else Vector3.ZERO
	var fdir := Vector2(fb.x - ft.x, fb.z - ft.z).normalized()
	var fside := fdir.orthogonal()
	for e in ([] if f.is_empty() else [[-0.6, -0.4, 2.3, 1.9], [0.6, -0.4, 2.5, 2.1], [-0.45, 0.8, 1.3, 0.9], [0.45, 0.9, 1.5, 1.0], [-0.2, 1.8, 0.7, 0.5], [0.3, 2.2, 0.8, 0.5], [-0.75, -1.5, 2.2, 1.8], [0.75, -1.6, 2.4, 2.0]]):
		var q: Vector2 = Vector2(fb.x, fb.z) + fside * e[0] * float(f.width) + fdir * e[1] * 2.0
		add.call(q.x, q.y, e[2], e[3], e[2] * 0.9, R.call(0, 6.28), 0.0, 0.3, 0, true)
	var placed := 0
	tries = 0
	var loose := int(data.d.get("flora", {}).get("loose_rocks", 60))
	while placed < loose and tries < 3000:
		tries += 1
		var q := Vector2(rng.randf_range(data.x0 + 20, data.x0 + data.w - 20), rng.randf_range(data.z0 + 20, data.z0 + data.dep - 20))
		if data.water_sd(q) < 2.0 or data.pave_dist(q) < 2.5 or blocked(q, 1.5): continue
		var s := rng.randf_range(0.35, 1.1)
		add.call(q.x, q.y, s * 1.3, s * 0.7, s, R.call(0, 6.28), 0.0, 0.4, -1, s > 0.6)
		placed += 1
	var geos: Array = []
	for i in 8: geos.append(VHProps.rock(31 + i * 17, 6, 1.5 if i % 3 == 0 else 1.0))
	var pebble := VHProps.rock(999, 2, 0.6)
	var mat := _mat("res://shaders/foliage/rock.gdshader")
	mat.set_shader_parameter("field_tex", data.field_tex)
	mat.set_shader_parameter("map_rect", data.field_rect)
	var buckets: Array = []
	for i in 8: buckets.append([])
	for i in list.size():
		var e: Array = list[i]
		buckets[e[8] if e[8] >= 0 else i % 8].append(e)
	var body := StaticBody3D.new()
	add_child(body)
	for v in 8: _rock_mmi(geos[v], buckets[v], mat, true, body)
	_rock_mmi(pebble, pebbles, mat, false, null)
	print("rocks: ", list.size(), " pebbles: ", pebbles.size())

func _rock_mmi(mesh: Mesh, arr: Array, mat: Material, shadows: bool, body: StaticBody3D) -> void:
	if arr.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = arr.size()
	for i in arr.size():
		var e: Array = arr[i]
		var y := height_at(e[0], e[1])
		var pos := Vector3(e[0], y - float(e[7]) * float(e[3]), e[1])
		var basis := Basis.from_euler(Vector3(e[6], e[5], float(e[6]) * 0.7), EULER_ORDER_XYZ).scaled(Vector3(e[2], e[3], e[4]))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		if body:
			var r := maxf(e[2], e[4]) * 0.85
			block(Vector2(e[0], e[1]), r)
			if e[9] or r > 0.6:
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = r * 0.95
				cyl.height = float(e[3]) * 1.25
				cs.shape = cyl
				cs.position = pos + Vector3(0, float(e[3]) * 0.4, 0)
				body.add_child(cs)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not shadows: mmi.visibility_range_end = 60.0
	add_child(mmi)

# --- trees: grown and cel shaded as just-a-simple-tree's (scripts/foliage), species by place, chunked --------------------
## The valley's tree kinds: the species that grows each (TreeSpecies), how many templates (picked at random per
## tree), the palette (TreeSpecies.PALETTES), and the ranges each template draws every one of the reference's
## knobs from, so no two templates share a height or a silhouette. Whole numbers draw whole numbers.
## flowers: the blooms a flowering shrub's templates take in turn (FLOWERS), with flower_share of its clusters.
const KINDS := {
	"broadleaf": {"species": "oak", "variants": 5, "palette": "green", "vary": {"tree_age": [0.5, 0.8], "size": [4.2, 6.0],
		"main_limbs": [3, 5], "branches": [3, 5], "spread": [0.75, 1.05], "crookedness": [0.25, 0.5], "split_height": [0.32, 0.5],
		"trunk_height": [0.0, 1.0], "clump_size": [0.85, 1.15], "roundness": [0.45, 0.75], "blade_width": [0.28, 0.36]}},
	# the Old Fig: the one tree that big, low heavy limbs spreading wide over the square (planted by _landmarks)
	"fig": {"species": "oak", "variants": 1, "palette": "green", "vary": {"tree_age": [1.0, 1.0], "size": [6.5, 6.5],
		"main_limbs": [6, 6], "branches": [5, 5], "spread": [1.45, 1.45], "crookedness": [0.7, 0.7], "split_height": [0.16, 0.16],
		"trunk_height": [0.0, 0.0], "clump_size": [1.3, 1.3], "roundness": [0.45, 0.45]}},
	"oak": {"species": "oak", "variants": 3, "palette": "green", "vary": {"tree_age": [0.85, 1.0], "size": [5.0, 6.5],
		"main_limbs": [4, 6], "branches": [4, 5], "spread": [0.95, 1.2], "crookedness": [0.45, 0.75], "split_height": [0.25, 0.38],
		"trunk_height": [0.0, 0.4], "clump_size": [0.95, 1.2], "roundness": [0.5, 0.7]}},
	"young": {"species": "oak", "variants": 3, "palette": "green", "vary": {"tree_age": [0.3, 0.45], "size": [3.5, 4.6],
		"main_limbs": [3, 4], "spread": [0.7, 1.0], "crookedness": [0.2, 0.4], "trunk_height": [0.2, 0.8]}},
	"blossom": {"species": "oak", "variants": 3, "palette": "blossom", "vary": {"tree_age": [0.55, 0.75], "size": [3.8, 5.0],
		"main_limbs": [3, 5], "spread": [0.85, 1.15], "crookedness": [0.35, 0.65], "blade_width": [0.42, 0.5]}},
	"spruce": {"species": "pine", "variants": 4, "palette": "conifer", "vary": {"tree_age": [0.5, 0.9], "size": [5.5, 8.0],
		"whorls": [7, 11], "whorl_branches": [5, 7], "droop": [-1.0, -0.3], "crookedness": [0.3, 0.55]}},
	"column": {"species": "cypress", "variants": 3, "palette": "conifer", "vary": {"tree_age": [0.55, 0.85], "size": [4.5, 6.5],
		"slenderness": [0.8, 1.3], "trunk_height": [0.3, 1.2], "cypress_branches": [16, 26]}},
	"shrub": {"species": "bush", "variants": 6, "palette": "green", "vary": {"size": [1.8, 3.0], "bush_clumps": [4, 10],
		"spread": [0.6, 1.1], "flower_share": [0.25, 0.4]}, "flowers": ["", "bougainvillea", "jasmine", "marigold", "hibiscus", "bougainvillea"]},
}
## A flowering shrub's two bloom colours (sRGB), its main one and a fewer second one.
const FLOWERS := {
	"bougainvillea": ["e0428f", "f7a8cf"],
	"jasmine": ["fff6e8", "ffe9b8"],
	"marigold": ["f39a2b", "ffd166"],
	"hibiscus": ["e8463a", "ffb3a8"],
}
const TREE_NEAR := 24.0        # whole trees within this (m), the lighter copies beyond
const TREE_FAR := 80.0         # and impostors past this
var twig_nodes: Array = []     # the twigs, shown only while the leaves unfold, thin or are gone

## A kind's v-th template: each knob drawn from its range by a random of the template's own, grown once
## (and cached on disk, TreeFoliage.build_cached).
func _tree_template(sp: String, v: int) -> Dictionary:
	var k: Dictionary = KINDS[sp]
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + v * 7919 + sp.length() * 131
	var set := {"seed": int(r.seed % 9973)}
	for knob in k.vary:
		var range_: Array = k.vary[knob]
		set[knob] = r.randi_range(range_[0], range_[1]) if range_[0] is int else r.randf_range(range_[0], range_[1])
	var flowers: Array = k.get("flowers", [])
	var bloom: String = flowers[v % flowers.size()] if not flowers.is_empty() else ""
	if bloom == "": set.flower_share = 0.0
	var t := TreeFoliage.build_cached(TreeSpecies.params_for(k.species, set))
	t.palette = k.palette
	t.flowers = FLOWERS.get(bloom, [])
	return t

func _fol_leaf_mat(tpl: Dictionary) -> ShaderMaterial:
	var key := "fol_leaf_%s_%.2f_%s" % [tpl.palette, tpl.flutter, ",".join(tpl.flowers)]
	if mats.has(key): return mats[key]
	var m := _mat("res://shaders/foliage/leaves.gdshader")
	var pal: Dictionary = TreeSpecies.PALETTES[tpl.palette]
	for i in 3:
		m.set_shader_parameter(["shadow_col", "mid_col", "light_col"][i], Color(pal.leaves[i]))
		m.set_shader_parameter(["turned_shadow", "turned_mid", "turned_light"][i], Color(TreeSpecies.TURNED[i]))
	for i in tpl.flowers.size(): m.set_shader_parameter(["flower_a", "flower_b"][i], Color(tpl.flowers[i]))
	m.set_shader_parameter("flutter", tpl.flutter)
	mats[key] = m
	return m

func _fol_wood_mat(palette: String) -> ShaderMaterial:
	var key := "fol_wood_" + palette
	if mats.has(key): return mats[key]
	var m := _mat("res://shaders/foliage/wood.gdshader")
	var pal: Dictionary = TreeSpecies.PALETTES[palette]
	for i in 3: m.set_shader_parameter(["shadow_col", "mid_col", "light_col"][i], Color(pal.wood[i]))
	mats[key] = m
	return m

func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights: total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0: return k
	return weights.keys()[0]

func _plant(sp: String, p: Vector2, scl: float) -> void:
	var key := "%s:%d" % [sp, rng.randi_range(0, int(KINDS[sp].variants) - 1)]
	if not trees.has(key):
		trees[key] = {"sp": sp, "tpl": _tree_template(sp, int(key.get_slice(":", 1))), "xf": []}
	var g: Dictionary = trees[key]
	var pos := Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y)
	g.xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scl), pos))
	var tr: float = g.tpl.trunk_radius
	if tr > 0.05: block(p, tr * scl * 1.4 + 1.0)

func _trees() -> void:
	_trees_t0 = Time.get_ticks_msec()
	# the cover map's tree density (peaking near 0.45) read as a woodland: about one tree per 19 m2 in the forest
	var step := 3.4
	var z := data.z0 + 3.0
	while z < data.z0 + data.dep - 3.0:
		var x := data.x0 + 3.0
		while x < data.x0 + data.w - 3.0:
			var p := Vector2(x + rng.randf_range(-1.4, 1.4), z + rng.randf_range(-1.4, 1.4))
			x += step
			var dens := minf(data.cover_at(3, p) * 1.35, 0.9)
			if dens <= 0.0 or rng.randf() > dens or blocked(p, 1.5): continue
			var h := data.height(p)
			var ws := data.water_sd(p)
			var pd := data.pave_dist(p)
			var sp: String
			if ws < 9.0: sp = _pick({"broadleaf": 0.45, "oak": 0.25, "young": 0.2, "shrub": 0.1})
			elif pd < 6.0: sp = _pick({"young": 0.35, "broadleaf": 0.25, "column": 0.15, "blossom": 0.15, "shrub": 0.1})
			elif rng.randf() < 0.12 + smoothstep(3.0, 10.0, h) * 0.68: sp = "spruce"
			else: sp = _pick({"broadleaf": 0.45, "oak": 0.3, "young": 0.15, "shrub": 0.1})
			var scl := rng.randf_range(0.85, 1.1) if sp == "spruce" else rng.randf_range(0.85, 1.35)
			_plant(sp, p, scl)
		z += step
	var o: Dictionary = data.d.get("flora", {}).get("orchard", {})
	var r: Array = o.get("rect", [0, 0, -1, -1])
	z = float(r[1]) + 4.0
	while z < float(r[3]):
		var x := float(r[0]) + 4.0
		while x < float(r[2]):
			var p := Vector2(x + rng.randf_range(-0.6, 0.6), z + rng.randf_range(-0.4, 0.4))
			x += float(o.tree_spacing)
			if data.pave_dist(p) < 2.5 or data.water_sd(p) < 2.0 or rng.randf() < 0.06: continue
			_plant("blossom" if rng.randf() < float(o.blossom) else "young", p, rng.randf_range(0.85, 1.05))
		z += float(o.row_spacing)
	for s in sites:
		var c: Vector2 = s.center2
		var hh: Vector2 = s.half2 + Vector2(1.6, 1.6)
		var per := 4.0 * (hh.x + hh.y)
		var t := 0.0
		while t < per:
			var u := t
			var q: Vector2
			if u < 2.0 * hh.x: q = c + Vector2(-hh.x + u, -hh.y)
			elif u < 2.0 * hh.x + 2.0 * hh.y: q = c + Vector2(hh.x, -hh.y + u - 2.0 * hh.x)
			elif u < 4.0 * hh.x + 2.0 * hh.y: q = c + Vector2(hh.x - (u - 2.0 * hh.x - 2.0 * hh.y), hh.y)
			else: q = c + Vector2(-hh.x, hh.y - (u - 4.0 * hh.x - 2.0 * hh.y))
			t += rng.randf_range(2.2, 4.0)
			if rng.randf() < 0.5 and data.pave_dist(q) > 1.0 and data.water_sd(q) > 1.0 and not blocked(q, 0.3):
				_plant("shrub", q, rng.randf_range(0.8, 1.5))
	# in small chunks, whole trees close and their lighter copies beyond, switched by the chunk's distance
	var total := 0
	var t0 := Time.get_ticks_msec()
	for key in trees:
		var g: Dictionary = trees[key]
		var tpl: Dictionary = g.tpl
		var leaf := _fol_leaf_mat(tpl)
		var wood := _fol_wood_mat(tpl.palette)
		var chunks := {}
		for i in g.xf.size():
			var o2: Vector3 = g.xf[i].origin
			chunks.get_or_add(Vector2i(floori(o2.x / TREE_CHUNK), floori(o2.z / TREE_CHUNK)), []).append(g.xf[i])
		for ck in chunks:
			var list: Array = chunks[ck]
			var centre := Vector3((ck.x + 0.5) * TREE_CHUNK, 0.0, (ck.y + 0.5) * TREE_CHUNK)
			_tree_mmi(tpl.wood, wood, list, centre, 0.0, TREE_NEAR, true)
			_tree_mmi(tpl.leaves, leaf, list, centre, 0.0, TREE_NEAR, true)
			_tree_mmi(tpl.low_wood, wood, list, centre, TREE_NEAR, TREE_FAR, true)
			_tree_mmi(tpl.low_leaves, leaf, list, centre, TREE_NEAR, TREE_FAR, true)
			var tw := _tree_mmi(tpl.twigs, wood, list, centre, 0.0, TREE_NEAR, false)
			if tw: twig_nodes.append(tw)
		total += g.xf.size()
	_show_twigs()
	print("trees + shrubs: ", total, " in ", trees.size(), " templates, grown in ", t0 - _trees_t0, " ms, placed in ", Time.get_ticks_msec() - t0, " ms")

var _trees_t0 := 0
## The season (0..1, fol_season) the leaves are at, and the twigs with it.
func set_season(s: float) -> void:
	RenderingServer.global_shader_parameter_set("fol_season", s)
	_season = s
	_show_twigs()

var _season := 0.35
func _show_twigs() -> void:
	for n in twig_nodes: n.visible = TreeFoliage.twigs_show(_season)

## Tree impostors (VHImpostor's octahedral atlases, cel shaded by shaders/foliage/impostor.gdshader): one per
## kind, baked from its first template's lighter copy (_proto), one card per tree for every tree in the valley
## past TREE_FAR plus the forests on the far hills (far_trees). Other templates borrow their kind's atlas,
## scaled to their own height.
var far_trees := {}             # kind -> [Transform3D] beyond the valley (_distant_forest)

## A kind's first template, the one its impostor is baked from.
func _proto(sp: String) -> Dictionary:
	var key := sp + ":0"
	if not trees.has(key): trees[key] = {"sp": sp, "tpl": _tree_template(sp, 0), "xf": []}
	return trees[key].tpl

func _impostors() -> void:
	var kinds := {}
	for key in trees: kinds[trees[key].sp] = true
	for sp in far_trees: kinds[sp] = true
	var items := {}
	for sp in kinds:
		var tpl := _proto(sp)
		items[sp] = {"trunk": tpl.low_wood, "leaves": tpl.low_leaves, "bark_mat": _fol_wood_mat(tpl.palette),
			"leaf_mat": _fol_leaf_mat(tpl), "frame_px": VHImpostor.frame_px(sp)}
	var t0 := Time.get_ticks_msec()
	var baked: Dictionary = await VHImpostor.bake(self, items)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump-impostors="):   # dev: -- --dump-impostors=D:/path/prefix
			for sp in baked:
				for k in ["albedo", "normal"]: (baked[sp][k] as ImageTexture).get_image().save_png("%s_%s_%s.png" % [a.trim_prefix("--dump-impostors="), sp, k])
	var quad := QuadMesh.new()
	var n := 0
	for sp in baked:
		var b: Dictionary = baked[sp]
		var proto := _proto(sp)
		var xfs: Array = []
		for key in trees:
			var g: Dictionary = trees[key]
			if g.sp != sp: continue
			var k := float(g.tpl.height) / float(proto.height)
			for xf in g.xf: xfs.append(Transform3D(xf.basis.scaled(Vector3.ONE * k), xf.origin))
		xfs.append_array(far_trees.get(sp, []))
		if xfs.is_empty(): continue
		var leaf := _fol_leaf_mat(proto)
		var m := _mat("res://shaders/foliage/impostor.gdshader")
		m.set_shader_parameter("albedo_atlas", b.albedo)
		m.set_shader_parameter("normal_atlas", b.normal)
		m.set_shader_parameter("frames", float(VHImpostor.FRAMES))
		m.set_shader_parameter("frame_px", float(b.frame_px))
		m.set_shader_parameter("radius", b.radius)
		m.set_shader_parameter("center_y", b.center_y)
		m.set_shader_parameter("near", TREE_FAR)
		for p in ["shadow_col", "mid_col", "light_col", "turned_shadow", "turned_mid", "turned_light"]:
			m.set_shader_parameter(p, leaf.get_shader_parameter(p))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = xfs.size()
		for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.custom_aabb = AABB(Vector3(-1e4, -200.0, -1e4), Vector3(2e4, 600.0, 2e4))
		if sp == "shrub": mmi.visibility_range_end = SHRUB_FAR
		add_child(mmi)
		n += xfs.size()
	print("tree impostors: ", n, " of ", baked.size(), " kinds, baked in ", Time.get_ticks_msec() - t0, " ms")

## Daylight beams under the crowns of the bigger trees (shaders/vh/shaft.gdshader), chunked like the
## trees and drawn out to ~95 m. Each hangs from a gap inside the crown and follows the sunlight down.
const SHAFT_SPECIES := {"broadleaf": 2, "oak": 2, "blossom": 1, "spruce": 1}

func _shafts() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9157
	var chunks := {}
	for key in trees:
		var g: Dictionary = trees[key]
		if not SHAFT_SPECIES.has(g.sp): continue
		for xf in g.xf:
			var scl: float = xf.basis.get_scale().x
			var hgt: float = float(g.tpl.height) * scl
			var cr: float = float(g.tpl.get("crown_radius", 1.5)) * scl
			for i in SHAFT_SPECIES[g.sp]:
				if r.randf() < 0.3: continue
				var a := r.randf() * TAU
				var off := Vector2(cos(a), sin(a)) * cr * r.randf_range(0.0, 0.55)
				var up := hgt * r.randf_range(0.55, 0.75)
				var top := Vector3(xf.origin.x + off.x, xf.origin.y + up, xf.origin.z + off.y)
				chunks.get_or_add(Vector2i(floori(top.x / CHUNK), floori(top.z / CHUNK)), []).append([top, Color(up, r.randf_range(0.35, 0.8), r.randf(), 0.0)])
	shafts = Node3D.new()
	add_child(shafts)
	var mat := _mat("res://shaders/vh/shaft.gdshader")
	var quad := QuadMesh.new()
	var n := 0
	for ck in chunks:
		var list: Array = chunks[ck]
		var centre := Vector3((ck.x + 0.5) * CHUNK, 0.0, (ck.y + 0.5) * CHUNK)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, Transform3D(Basis(), list[k][0] - centre))
			mm.set_instance_custom_data(k, list[k][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.layers = LAYER_FIELDS
		mmi.custom_aabb = AABB(Vector3(-CHUNK, -30.0, -CHUNK), Vector3(CHUNK * 2.0, 90.0, CHUNK * 2.0))
		mmi.position = centre
		mmi.visibility_range_end = CHUNK * 0.7 + 50.0
		shafts.add_child(mmi)
		n += list.size()
	print("sun shafts: ", n, " in ", chunks.size(), " chunks")

func _tree_mmi(mesh: Mesh, mat: Material, list: Array, centre: Vector3, vb: float, ve: float, shadows: bool) -> MultiMeshInstance3D:
	if mesh.get_surface_count() == 0: return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for k in list.size():
		var xf: Transform3D = list[k]
		mm.set_instance_transform(k, Transform3D(xf.basis, xf.origin - centre))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = centre
	mmi.visibility_range_begin = vb
	mmi.visibility_range_end = ve
	add_child(mmi)
	return mmi

# --- falling leaves + petals from the crowns, sunlit motes around the camera (GPU-animated, no per-frame CPU) -----------
const FALL_LEAVES := {"broadleaf": 6, "oak": 6, "young": 4, "blossom": 10}
const LEAF_TINTS := [Color("b0b34a"), Color("9aae3e"), Color("c4b84e"), Color("8fa23a"), Color("c99a46")]
const PETAL_TINTS := [Color("edb0c2"), Color("f4c9d6"), Color("e8a4b8")]

func _falling_leaves() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4417
	var mat := _mat("res://shaders/vh/falling_leaf.gdshader")
	var chunks := {}   # chunk -> [[base, custom, tint], ...]
	for key in trees:
		var g: Dictionary = trees[key]
		if not FALL_LEAVES.has(g.sp): continue
		var petal: bool = g.sp == "blossom"
		for xf in g.xf:
			var scl: float = xf.basis.get_scale().x
			var top: float = float(g.tpl.height) * scl
			var cr: float = float(g.tpl.get("crown_radius", 1.5)) * scl
			var list: Array = chunks.get_or_add(Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK)), [])
			for i in FALL_LEAVES[g.sp]:
				var tint: Color = PETAL_TINTS[r.randi() % PETAL_TINTS.size()] if petal else LEAF_TINTS[r.randi() % LEAF_TINTS.size()]
				list.append([xf.origin, Color(r.randf(), r.randf(), top * r.randf_range(0.55, 0.9), cr), tint])
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.19)
	var n := 0
	for ck in chunks:
		var list: Array = chunks[ck]
		var centre := Vector3((ck.x + 0.5) * CHUNK, 0.0, (ck.y + 0.5) * CHUNK)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, Transform3D(Basis(), list[k][0] - centre))
			mm.set_instance_custom_data(k, list[k][1])
			mm.set_instance_color(k, list[k][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.layers = LAYER_FIELDS
		mmi.custom_aabb = AABB(Vector3(-CHUNK, -4.0, -CHUNK), Vector3(CHUNK * 2.0, 40.0, CHUNK * 2.0))
		mmi.position = centre
		mmi.visibility_range_end = CHUNK * 0.7 + 40.0
		add_child(mmi)
		n += list.size()
	print("falling leaves: ", n, " in ", chunks.size(), " chunks")

func _motes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 2711
	var quad := QuadMesh.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 160
	for i in mm.instance_count: mm.set_instance_transform(i, Transform3D(Basis(), Vector3(r.randf() * 26.0, r.randf() * 9.0, r.randf() * 26.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat("res://shaders/vh/motes.gdshader")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.layers = LAYER_FIELDS
	mmi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	add_child(mmi)

## Night: fireflies wandering and blinking over the ground around the player (the motes shader's
## firefly mode, faded in with vh_night).
## Butterflies (shaders/foliage/butterfly.gdshader), flying round the flowering shrubs, more of them where
## a shrub blooms, and round the blossom trees: all on the GPU, one MultiMesh for the valley.
func _butterflies() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 6047
	var homes: Array = []        # [where, how far it strays]
	for key in trees:
		var g: Dictionary = trees[key]
		if g.sp != "shrub" and g.sp != "blossom": continue
		var blooms: bool = not g.tpl.get("flowers", []).is_empty() or g.sp == "blossom"
		for xf in g.xf:
			var n := (1 if r.randf() < 0.55 else 0) + (1 if r.randf() < 0.25 else 0) if blooms else (1 if r.randf() < 0.12 else 0)
			for i in n: homes.append([xf.origin, r.randf_range(0.8, 2.6) if g.sp == "shrub" else r.randf_range(2.0, 3.5)])
	homes.shuffle()
	homes.resize(mini(homes.size(), 600))
	# two wings, each a quad hinged on the body: x out along the wing, z from the front (+) to the back
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var corners := [Vector2(0, 0.6), Vector2(1, 0.6), Vector2(1, -0.6), Vector2(0, -0.6)]
		for k in [0, 1, 2, 0, 2, 3]:
			var c: Vector2 = corners[k]
			st.set_uv(Vector2(c.x, (0.6 - c.y) / 1.2))
			st.add_vertex(Vector3(s * c.x, 0.0, c.y))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = st.commit()
	mm.instance_count = homes.size()
	for i in homes.size():
		mm.set_instance_transform(i, Transform3D(Basis(), homes[i][0]))
		mm.set_instance_custom_data(i, Color(r.randf(), float(r.randi_range(0, 4)), homes[i][1], 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat("res://shaders/foliage/butterfly.gdshader")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.layers = LAYER_FIELDS
	mmi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	add_child(mmi)
	print("butterflies: ", homes.size())

func _fireflies() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3319
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	mm.instance_count = 90
	for i in mm.instance_count: mm.set_instance_transform(i, Transform3D(Basis(), Vector3(r.randf() * 36.0, r.randf() * 3.0, r.randf() * 36.0)))
	fireflies = MultiMeshInstance3D.new()
	fireflies.multimesh = mm
	var m := _mat("res://shaders/vh/motes.gdshader")
	m.set_shader_parameter("fireflies", true)
	m.set_shader_parameter("box", Vector3(36.0, 3.0, 36.0))
	m.set_shader_parameter("size", 0.07)
	m.set_shader_parameter("tint", Vector3(0.8, 1.0, 0.3))
	fireflies.material_override = m
	fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fireflies.layers = LAYER_FIELDS
	fireflies.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	add_child(fireflies)

# --- GPU ground cover (vegetation.ts GrassField, ported): grass rings, wildflowers, ferns ------------------------------------
func _fields() -> void:
	RenderingServer.global_shader_parameter_set("fol_noise_tex", MeadowNoise.texture())
	add_child(GrassTrails.new())
	if OS.get_cmdline_user_args().has("--no-grass"): return   # dev: what the ground cover costs
	# the reference's blades at town scale, dense near (some 380 a square metre), fewer further out where the ground's
	# matching colour carries the lawn: [lattice spacing, outer radius, inner radius, blades a clump]
	# and strip segments, fewer where a bend is too small to see
	# sized for the 20 degree lens: a default frame reaches ~15 m from the focus, so the outer ring ends at 30 m
	# (perf: ~160k blades a frame was half the frame; now ~45k, and the painted meadow carries the lawn beyond)
	for ring in [[0.32, 10.0, 0.0, 16, 3], [0.6, 20.0, 10.0, 9, 2]]:
		var m := _mat("res://shaders/foliage/grass.gdshader")
		m.set_shader_parameter("target_density", 1.0 / (ring[0] * ring[0]))
		m.set_shader_parameter("max_dist", 20.0)
		m.set_shader_parameter("clump_spread", ring[0] * 0.75)
		_add_field(m, _blade_mesh(ring[3], 31 + ring[3], ring[4]), ring[0], ring[1], ring[2], Vector4(1, 0, 0, 0))
	var fm := _mat("res://shaders/foliage/flower.gdshader")
	fm.set_shader_parameter("target_density", 1.0)
	fm.set_shader_parameter("max_dist", 24.0)
	_add_field(fm, _flower_mesh(), 1.0, 24.0, 0.0, Vector4(1, 0, 0, 0))

func _add_field(mat: ShaderMaterial, mesh: Mesh, spacing: float, radius: float, inner: float, channel: Vector4) -> void:
	mat.set_shader_parameter("height_tex", data.field_tex)
	mat.set_shader_parameter("dens_tex", data.cover_tex)
	mat.set_shader_parameter("paved_tex", data.paved_tex)
	mat.set_shader_parameter("map_rect", data.field_rect)
	mat.set_shader_parameter("paved_rect", data.paved_rect)
	mat.set_shader_parameter("spacing", spacing)
	mat.set_shader_parameter("field_radius", radius)
	mat.set_shader_parameter("inner_radius", inner)
	mat.set_shader_parameter("channel", channel)
	var f := GrassBuilder.field(mat, spacing, radius, mesh, inner, LAYER_FIELDS)
	add_child(f)
	fields.append([f, spacing])

## A clump of `blades` grass blades for shaders/foliage/grass.gdshaderinc, which builds each blade itself: every
## vertex carries its blade's root in the clump (xz, within 0.3 m, scaled there by clump_spread), where it is on
## the blade's strip (UV: x across, y up, `segs` segments) and the blade's three randoms (COLOR).
func _blade_mesh(blades: int, seed: int, segs := 3) -> ArrayMesh:
	var rnd := RandomNumberGenerator.new()
	rnd.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var r := 0.3 * sqrt(rnd.randf())
		var a := rnd.randf() * TAU
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var col := Color(rnd.randf(), rnd.randf(), rnd.randf())
		for i in segs + 1:
			for s in 2:
				st.set_color(col)
				st.set_uv(Vector2(s, float(i) / segs))
				st.set_normal(Vector3.UP)
				st.add_vertex(root)
		for i in segs:
			var v := b * (segs + 1) * 2 + i * 2
			for k in [v, v + 2, v + 1, v + 1, v + 2, v + 3]: st.add_index(k)
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	return m

## vegetation.ts flowerGeometry: thin stem + 7-petal head, vertex colours (petals white = recoloured).
func _flower_mesh() -> ArrayMesh:
	# vertex colour convention (flower.gdshader): white = petal (recoloured per flower), anything else as is
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.16, 0.3, 0.07)
	var leaf := Color(0.2, 0.36, 0.09)
	var eye := Color(0.95, 0.72, 0.18)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3) -> void:
		for p in [a, c, b]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)
	# stem: a gentle curve, three segments, as a thin strip each way
	var stem := [Vector3(0, 0, 0), Vector3(0.006, 0.35, 0.008), Vector3(0.012, 0.7, 0.014), Vector3(0.016, 0.98, 0.02)]
	for k in 3:
		var a: Vector3 = stem[k]
		var b: Vector3 = stem[k + 1]
		var w0 := 0.0055 - k * 0.001
		var w1 := 0.0045 - k * 0.001
		for d in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			tri.call(a - d * w0, a + d * w0, b + d * w1, green, Vector3(d.z, 0, -d.x))
			tri.call(a - d * w0, b + d * w1, b - d * w1, green, Vector3(d.z, 0, -d.x))
	# two lance leaves on the stem
	for e in [[0.22, 0.0, 0.16], [0.42, PI, 0.13]]:
		var y: float = e[0]
		var ang: float = e[1]
		var L: float = e[2]
		var dir := Vector3(cos(ang), 0.55, sin(ang)).normalized()
		var side := Vector3(-sin(ang), 0, cos(ang))
		var o := Vector3(0.004, y, 0.005)
		var mid := o + dir * L * 0.5 + Vector3(0, 0.02, 0)
		var tip := o + dir * L - Vector3(0, 0.01, 0)
		var nn := dir.cross(side).normalized()
		if nn.y < 0.0: nn = -nn
		tri.call(o, mid + side * 0.014, tip, leaf, nn)
		tri.call(o, tip, mid - side * 0.014, leaf, nn)
	# head: six outer petals and six inner ones offset between them, each cupped (raised at its edges)
	var top := Vector3(0.016, 0.985, 0.02)
	for ring in [[6, 0.075, 0.0, 0.32, 0.0], [6, 0.05, PI / 6.0, 0.5, 0.006]]:
		var count: int = ring[0]
		var R: float = ring[1]
		var off: float = ring[2]
		var lift: float = ring[3]
		var dy: float = ring[4]
		for i in count:
			var a := TAU * i / count + off
			var fwd := Vector3(cos(a), lift, sin(a)).normalized()
			var side := Vector3(-sin(a), 0, cos(a))
			var base := top + Vector3(0, dy, 0) + fwd * 0.006
			var mid := base + fwd * R * 0.55
			var tip := base + fwd * R
			var hw := R * 0.32
			var up := fwd.cross(side).normalized()
			if up.y < 0.0: up = -up
			var cup := up * R * 0.12
			tri.call(base, mid + side * hw + cup, mid - side * hw + cup, Color(1, 1, 1), up)
			tri.call(mid + side * hw + cup, tip, mid - side * hw + cup, Color(1, 1, 1), up)
	# the centre: a small dome
	var segs := 8
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var r := 0.014
		var p0 := top + Vector3(cos(a0) * r, 0.006, sin(a0) * r)
		var p1 := top + Vector3(cos(a1) * r, 0.006, sin(a1) * r)
		tri.call(top + Vector3(0, 0.014, 0), p0, p1, eye, Vector3.UP)
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	return m

# --- horizon: far hills, the river running out to the capital, the city, silhouette forests ----------------------------
func _far_h(p: Vector2, open_az: float, outflow: Vector2, cap: Vector2) -> float:
	var hz: Dictionary = data.d.horizon.far_land
	var c := Vector2(data.x0 + data.w * 0.5, data.z0 + data.dep * 0.5)
	var e := maxf(maxf(data.x0 - p.x, p.x - data.x0 - data.w), maxf(data.z0 - p.y, p.y - data.z0 - data.dep))
	var edge_h := data.height(p)
	if e < 0.0: return edge_h - 4.0
	var ridge := absf(sin(p.x * 0.0021 + 1.3) * cos(p.y * 0.0017 - 0.4)) * 0.6 + (sin(p.x * 0.0063 + p.y * 0.0049) * 0.5 + 0.5) * 0.4
	var amp := float(hz.height) * smoothstep(0.0, 1400.0, e)
	var az := atan2(p.x - c.x, -(p.y - c.y))
	var gap := absf(angle_difference(az, open_az))
	amp *= lerpf(0.06, 1.0, smoothstep(deg_to_rad(float(hz.open_width)) * 0.5, deg_to_rad(float(hz.open_width)), gap))
	var y := lerpf(edge_h, 0.0, smoothstep(0.0, 260.0, e)) + ridge * amp + smoothstep(0.0, 260.0, e) * 3.0
	var carve := WorldData.seg_dist(p, outflow, cap)
	if _upstream: carve = minf(carve, WorldData.seg_dist(p, _upstream[0], _upstream[1]))
	return minf(y, -6.0 + maxf(carve - 30.0, 0.0) * 0.08)

func _horizon() -> void:
	var hz: Dictionary = data.d.horizon
	var c := Vector2(data.x0 + data.w * 0.5, data.z0 + data.dep * 0.5)
	# the river runs out toward open_az: to the capital in the valley, to plain far country from the quarter
	var capital: Dictionary = hz.get("capital", {})
	var open_az := deg_to_rad(float(capital.az if capital else hz.far_land.open_az))
	var outflow := WorldData.v2(data.d.river.reaches[-1].points[-1])
	var cap := c + Vector2(sin(open_az), -cos(open_az)) * float(capital.get("dist", 2350.0))
	if hz.has("inflow_az"):
		var ia := deg_to_rad(float(hz.inflow_az))
		var src := WorldData.v2(data.d.river.reaches[0].points[0])
		_upstream = [src + Vector2(sin(ia), -cos(ia)) * 2350.0, src]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 160
	var radii: Array = []
	var r := minf(300.0, 0.45 * minf(data.w, data.dep))   # the first ring sits under the terrain's edge
	while r < float(hz.far_land.r1):
		radii.append(r)
		r *= 1.09
	for j in radii.size():
		for i in na + 1:
			var az := TAU * i / na
			var p := c + Vector2(sin(az), -cos(az)) * float(radii[j])
			st.add_vertex(Vector3(p.x, _far_h(p, open_az, outflow, cap), p.y))
	for j in radii.size() - 1:
		for i in na:
			var a := j * (na + 1) + i
			var b := a + na + 1
			st.add_index(a); st.add_index(b); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(b); st.add_index(b + 1)
	st.generate_normals()
	var fm := _mat("res://shaders/vh/far.gdshader")
	fm.set_shader_parameter("t_rock", VHTex.get_tex("rock_map"))
	fm.set_shader_parameter("t_noise", VHTex.get_tex("noise"))
	_mesh(st.commit(), fm, false)
	# the river keeps going, widening, out to the capital
	var lvl := float(data.d.river.reaches[-1].points[-1][3])
	var out_pts: Array = []
	for k in 13:
		var q: Vector2 = outflow.lerp(cap, k / 12.0 * 0.92)
		out_pts.append([q.x, q.y, lerpf(16.0, 70.0, k / 12.0), lvl - k * 0.15])
	_water_ribbon(out_pts, 2.0, 0.32, Vector2(0, -1e5))
	if _upstream:
		var lvl0 := float(data.d.river.reaches[0].points[0][3])
		var in_pts: Array = []
		for k in 13:
			var q: Vector2 = _upstream[1].lerp(_upstream[0], (12 - k) / 12.0 * 0.92)
			in_pts.append([q.x, q.y, lerpf(60.0, 16.0, k / 12.0), lvl0 + (12 - k) * 0.15])
		_water_ribbon(in_pts, 2.0, 0.32, Vector2(0, -1e5))
	if capital.is_empty():
		_distant_forest(open_az, outflow, cap)
		return
	# the city (distant.ts createCity) on the far bank of the outflow
	var city := VHProps.city()
	city_mat = _mat("res://shaders/vh/city.gdshader")
	var glow := _led(Color("f4ecff"), 5.5)
	glow.set_shader_parameter("day_on", 0.6)      # the capital's rings stay lit by day
	RenderingServer.global_shader_parameter_set("vh_glow_dir", Vector2(sin(open_az), -cos(open_az)))
	var base := Vector3(cap.x, -3.0, cap.y)
	var yaw := atan2(c.x - cap.x, c.y - cap.y) - PI
	for part in [[city.solid, city_mat], [city.glow, glow]]:
		var mi := _mesh(part[0], part[1], false)
		mi.transform = Transform3D(Basis(Vector3.UP, yaw), base)
		mi.extra_cull_margin = 4000.0
	_distant_forest(open_az, outflow, cap)

## distant.ts createDistantForest, as real trees: spruce, broadleaf and oak impostors (far_trees, drawn by
## _impostors) over the far hills, in woods that thin out into clearings, densest close to the valley.
func _distant_forest(open_az: float, outflow: Vector2, cap: Vector2) -> void:
	var rnd := VHNoise.rng(5150)
	var c := Vector2(data.x0 + data.w * 0.5, data.z0 + data.dep * 0.5)
	for kind in [["spruce", 4500, 12.5], ["broadleaf", 2100, 7.5], ["oak", 1300, 6.5]]:
		var sp: String = kind[0]
		var xfs: Array = far_trees.get_or_add(sp, [])
		var tries := 0
		var want: int = kind[1]
		var h0 := float(_proto(sp).height)
		while xfs.size() < want and tries < want * 40:
			tries += 1
			var a := rnd.next() * TAU
			var rr := minf(330.0, 0.6 * maxf(data.w, data.dep)) + pow(rnd.next(), 1.15) * 1350.0
			var p := c + Vector2(cos(a), sin(a)) * rr
			if data.inside(p, -4.0): continue
			if p.distance_to(cap) < 900.0: continue
			var y := _far_h(p, open_az, outflow, cap)
			if y < -3.0: continue
			if absf(_far_h(p + Vector2(3, 0), open_az, outflow, cap) - _far_h(p - Vector2(3, 0), open_az, outflow, cap)) / 6.0 > 0.7: continue
			# woods and clearings: a broad noise for the stands, a finer one ragging their edges
			var wood := sin(p.x * 0.006) * cos(p.y * 0.0055) + 0.35 * sin(p.x * 0.021 + 1.7) * sin(p.y * 0.019 - 0.6)
			if wood < -0.3: continue
			if wood < 0.0 and rnd.next() > (wood + 0.3) / 0.3: continue
			var sc: float = float(kind[2]) / h0 * (0.75 + rnd.next() * 0.55)
			xfs.append(Transform3D(Basis(Vector3.UP, rnd.next() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, y - 0.3, p.y)))


# --- player --------------------------------------------------------------------------------------------------------------
func _player() -> void:
	player = PlayerScript.new()
	add_child(player)
	var sp := WorldData.v2(data.d.spawn)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):          # testing: start somewhere else (x,z)
			var xz := a.trim_prefix("--at=").split(",")
			sp = Vector2(float(xz[0]), float(xz[1]))
	player.global_position = Vector3(sp.x, height_at(sp.x, sp.y) + 0.5, sp.y)
	rig = CameraRig.new()
	rig.target = player
	rig.floor_at = _camera_floor
	add_child(rig)
	rig.cam.far = 6000.0
	rig.cam.near = 0.1
	rig.set_mode(str(_setting("camera", "top")), true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="): rig.set_mode(a.trim_prefix("--view="), true)    # testing: start in a view
	rig.mode_changed.connect(func(m): _save_setting("camera", m))
	player.rig = rig

## The lowest a camera may sink to at a point: the ground, or the water surface over the river.
func _camera_floor(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := height_at(x, z)
	return maxf(h, data.water_z(p)) if data.water_sd(p) < 1.0 else h

var _fps_avg := 60.0
var _res_t := 0.0

## Hold the frame rate: the 3D image renders at 60-100% of the window and is scaled up (the UI is not).
func _dynamic_resolution(delta: float) -> void:
	if _capturing or delta <= 0.0: return
	_fps_avg = lerpf(_fps_avg, 1.0 / delta, 1.0 - exp(-2.0 * delta))
	_res_t += delta
	if _res_t < 1.0: return
	_res_t = 0.0
	var vp := get_viewport()
	var s := vp.scaling_3d_scale
	if _fps_avg < 46.0: s = maxf(0.6, s - 0.05)
	elif _fps_avg > 57.0: s = minf(1.0, s + 0.05)
	vp.scaling_3d_scale = s

func _process(delta: float) -> void:
	_dynamic_resolution(delta)
	var eye := get_viewport().get_camera_3d()
	if eye:
		RenderingServer.global_shader_parameter_set("vh_eye", eye.global_position)
		var ppm := get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(eye.fov) * 0.5)
		RenderingServer.global_shader_parameter_set("vh_tree_lod", Vector4(TREE_LOD.x, TREE_LOD.y, ppm, TREE_MAG))
	_update_time_of_day(delta)
	if sun: RenderingServer.global_shader_parameter_set("light_direction", sun.global_transform.basis.z.normalized())
	if rig:
		var c: Vector3 = rig.global_position
		for f in fields:
			f[0].global_position = Vector3(snappedf(c.x, f[1]), 0.0, snappedf(c.z, f[1]))
	if player: RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	# keep the player in sight: leaves, branches and roofs between the camera and them dissolve
	var keep: float = {"top": 3.2, "third": 1.3, "first": 0.0}.get(rig.mode if rig else "top", 3.2)
	if _capturing and not OS.get_cmdline_user_args().has("--keep-in-sight"): keep = 0.0
	if player: RenderingServer.global_shader_parameter_set("fol_occlude", Vector4(player.smooth_position().x, player.smooth_position().y + 1.0, player.smooth_position().z, keep))
	_update_cast(delta)

# --- grade + intro -----------------------------------------------------------------------------------------------------------
## Screen-space ambient occlusion over the opaque scene (shaders/vh/ssao.gdshader); -- --no-ssao leaves it out.
func _ssao() -> void:
	if OS.get_cmdline_user_args().has("--no-ssao"): return
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := _mat("res://shaders/vh/ssao.gdshader")
	m.render_priority = -128
	mi.material_override = m
	mi.layers = LAYER_POST
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(mi)

func _post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.material = _mat("res://shaders/vh/grade.gdshader")
	layer.add_child(post)

func _intro() -> void:
	var keys: Array = data.d.intro
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	player.frozen = true
	post.material.set_shader_parameter("letterbox", 1.0)
	var title := Label.new()
	title.text = "DHANIVERSE"
	title.add_theme_font_override("font", load("res://assets/fonts/Nunito.ttf"))
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.modulate.a = 0.0
	var tl := CanvasLayer.new()
	tl.add_child(title)
	add_child(tl)
	var tt := create_tween()
	tt.tween_interval(1.2)
	tt.tween_property(title, "modulate:a", 1.0, 1.5)
	tt.tween_interval(3.0)
	tt.tween_property(title, "modulate:a", 0.0, 1.5)
	var t0 := Time.get_ticks_msec()
	var total: float = keys[-1].t
	cam.global_position = WorldData.v3(keys[0].pos)
	while true:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if t >= total or Input.is_anything_pressed(): break
		var i := 0
		while i < keys.size() - 2 and t > float(keys[i + 1].t): i += 1
		var f := smoothstep(float(keys[i].t), float(keys[i + 1].t), t)
		cam.global_position = cam.global_position.lerp(WorldData.v3(keys[i].pos).lerp(WorldData.v3(keys[i + 1].pos), f), 0.12)
		cam.look_at(WorldData.v3(keys[i].look).lerp(WorldData.v3(keys[i + 1].look), f))
		await get_tree().process_frame
	tl.queue_free()
	create_tween().tween_method(func(v): post.material.set_shader_parameter("letterbox", v), 1.0, 0.0, 0.8)
	rig.cam.make_current()
	cam.queue_free()
	player.frozen = false
	_save_setting("seen_quarter_intro", true)
	# Bo rings the arrival bell and waves the newcomer in
	if cast_people.has("bo"): cast_people.bo.gesture("Wave")

func _snap(path: String) -> void:
	await get_tree().create_timer(10.0).timeout
	var fps := Engine.get_frames_per_second()
	print("snap: %d fps, weather %s %s, time %s, view %s, window %s" % [fps, weather.season if weather else "", weather.weather if weather else "", mode, rig.mode, get_viewport().get_visible_rect().size])
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

## Dev: save review screenshots of every authored view, then quit.  -- --shots=D:/path/prefix
## Optional: --only=view,view  --modes=day,evening,night (one set per time of day, prefix_mode_view.png)
func _capture(prefix: String) -> void:
	_capturing = true
	player.frozen = true
	rig.set_mode("top", true)
	# a covered window stops rendering properly on Windows: keep it on top while capturing
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	rig.fov = float(data.d.hero_camera.get("fov", 40.0))
	rig.cam.fov = rig.fov
	var only := ""
	var modes: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.trim_prefix("--only=")
		if a.begins_with("--modes="): modes = Array(a.trim_prefix("--modes=").split(","))
	for m in (modes if not modes.is_empty() else [mode]):
		if not modes.is_empty(): set_time_mode(m, true)
		for v in data.d.views:
			if only != "" and not str(v.name) in only.split(","): continue
			var fp := WorldData.v3(v.focus)
			if v.get("eye", false): fp.y = height_at(fp.x, fp.z) + 1.5
			rig._focus_point = fp
			rig.yaw = deg_to_rad(float(v.yaw))
			rig.pitch = deg_to_rad(float(v.pitch))
			rig.distance = float(v.distance)
			rig.fov = float(v.get("fov", data.d.hero_camera.get("fov", 40.0)))
			rig.global_position = fp
			rig._follow = fp
			rig._yaw = rig.yaw
			rig._pitch = rig.pitch
			rig._dist = rig.distance
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)   # minimized windows stop rendering
			var vp := get_viewport().get_viewport_rid()
			for i in 50: await get_tree().process_frame
			# then the GPU time averaged (and its best) over 60 frames, the laptop's clocks being what they are
			var gsum := 0.0
			var gmin := INF
			for i in 60:
				await get_tree().process_frame
				var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
				gsum += g
				gmin = minf(gmin, g)
			var shot := get_viewport().get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			shot.save_png("%s_%s.png" % [prefix, v.name] if modes.is_empty() else "%s_%s_%s.png" % [prefix, m, v.name])
			print("view ", m, " ", v.name, " fps=", Engine.get_frames_per_second(), " gpu_ms=", snappedf(gsum / 60.0, 0.01), " best=", snappedf(gmin, 0.01),
				" draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " tris=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	get_tree().quit()
