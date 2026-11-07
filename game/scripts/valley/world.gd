extends Node3D
## The Dhani Valley, trimmed to the bank and its surroundings: terrain (shaders/foliage/ground.gdshader, the
## painted meadow and flagstones), the river, the three rings of grass (shaders/foliage/grass.gdshader) and the
## bank. Day, evening and night (SkyModes) blend with T. Everything else is left out until it is asked for.

signal time_mode_changed(mode: String)

const PlayerScript := preload("res://scripts/valley/player.gd")
const CameraRig := preload("res://scripts/valley/camera_rig.gd")
const WORLD_FILE := "res://world/valley/world.json"
const TestPanel := preload("res://scripts/ui/test_panel.gd")
const SpotScript := preload("res://scripts/world/spot.gd")
const PersonScript := preload("res://scripts/life/person.gd")
const CastScript := preload("res://scripts/life/cast.gd")
const STALL_AT := Vector3(-16.2, 0.31, -27.3)   # on the Market Hall's floor, its counter facing the door
const COUNTER_AT := Vector3(-22.88, 0.74, 17.21)   # the bank's counter: its front edge, on the bank's floor
const HOME_AT := Vector2(-40.5, 39.6)   # the room in the Homes' courtyard: its front wall, its door to the tree
const HOME_RECT := Rect2(-44.3, 38.9, 7.6, 6.1)   # the street furniture keeps out of it
const FOOD_COUNTER_AT := Vector3(18.65, 0.0, 12.38)   # the Common Table's counter: its front edge, on the floor, turned to the room
# the customers' way in from the street and back out, clear of the hall's planters and piers
const STREET_ROUTE: Array[Vector3] = [Vector3(-20.0, 0.1, -12.5), Vector3(-20.0, 0.31, -22.0)]
const TILE := 64.0             # terrain tile (m)
const TILE_LOD := 130.0        # near/far terrain switch distance
# The part of the valley that is kept: the town, the river past it and a margin. Terrain beyond it (plus one
# tile) is not built and the player cannot walk out of it; the rest of the 800 x 740 m map is gone.
const SPAWN := Vector2(-27.17, -5.14)   # on the square in front of the bank
const MAP := Rect2(-175.0, -132.0, 305.0, 262.0)
const LAYER_FIELDS := 2        # grass
const LAYER_WATER := 4
const SETTINGS_FILE := "user://settings.cfg"
const MODE_BLEND := 2.5        # seconds to change the time of day
const TOWN_SQUARE := Vector3(-14.5, 0.0, -9.5)   # where the town turns to when news comes
const DAWN_SUN := {"sun_az": 78, "sun_el": 4, "light_az": 82, "light_el": 13, "sun_color": "ffc4a0", "intensity": 2.5, "ambient_intensity": 0.9, "exposure": 0.92}   # the opening's: it isn't one of T's times of day
const BANNERS_AT := [Vector2(-42.0, -3.0), Vector2(-34.0, -14.0), Vector2(-27.0, 0.5), Vector2(-16.0, -2.0), Vector2(-10.0, -14.0), Vector2(-4.0, 0.0)]
const LAMP_SLOTS := 6          # lamps lit at once around the player (vh.gdshaderinc has room for 12); the rest light only the ground decals
# lamp kinds: linear colour, intensity, range (m)
const LAMP_STREET := [Color(1.0, 0.584, 0.254), 14.0, 13.0]     # #ffc98a lanterns
const LAMP_BOLLARD := [Color(1.0, 0.665, 0.361), 3.5, 6.0]      # #ffd5a2 trail bollards
const LAMP_DOOR := [Color(1.0, 0.644, 0.353), 5.0, 8.0]         # #ffd2a0 light over a doorway

var data: WorldData
var sites: Array = []
var bgrid := {}
var fields: Array = []         # [field node (ValleyGrass), snap spacing]
var player: CharacterBody3D
var rig: Node3D
var sun: DirectionalLight3D
var env: Environment
var post: ColorRect
var client: TownClient         # the game's way to the rules
var stall: MarketStall
var food_counter: FoodCounter
var keeper: Harbourmaster
var kiosks: Kiosks
var dhaniverse: Dhaniverse    # protocol 3's things in the world: the boards, the chest, the quests' stops
var hud: GameHud
var furniture: Array[Node3D] = []   # the bank's counter and the courtyard room: scenery, nothing to do at them
var moments: Moments
var title: TitleScreen
var settings: SettingsPanel
var pause: PauseMenu
var world_env: Environment
var cinematic_on := true
## Steady frames: a machine that can't keep up with the screen gets an even half of it (30 on a 60 Hz screen) rather than
## frames that land on 33 and 50 ms by turns, which is what judders. Measured once, a few seconds in; the setting turns it off.
var steady_frames := true:
	set(v):
		steady_frames = v
		_pace_t = 0.0
		_pace_n = 0
		_pace_sum = 0.0
		Engine.max_fps = 0
const PACE_AFTER := 4.0         # s in before it's measured: loading's done
const PACE_OVER := 5.0          # s it's measured over
const PACE_HOLDS := 0.92        # of the screen's rate, kept up on average: then it's left free
var _pace_t := 0.0
var _pace_n := 0
var _pace_sum := 0.0
var rays_on := true:
	set(v):
		rays_on = v
		if shafts: shafts.visible = v and (look.vh_shafts as Vector4).x > 0.002
var people: TownPeople
var _banners: Array[MeshInstance3D] = []
var blast: MilestoneBlast
var morning_paper: MorningPaper
var mentor: MentorChat
var _rooms: Array = []
# from inside a room only what the windows can reach is drawn: the rest of the town isn't there to see
const ROOM_SEES := {1: 90.0}   # m to a building, by room: the Market Hall is all glass
const ROOM_SEES_ELSE := 60.0
const ROOM_SEES_PROPS := 34.0
const ROOM_SEES_TREES := 50.0
const FAR_BUILDING := 190.0    # m: further off than this, fog has it anyway
var _building_nodes: Array = [] # [node, footprint]
var _prop_nodes: Array = []     # [node, where]
var _tree_nodes: Array = []     # [node, where]
var _culled_for := -2           # the room it's culled for, or -1 outdoors
var cinema: Cinema
var phone: Phone
var opening: Opening
var loot: LootCrate
var quest_crate: QuestCrate
var town_map: TownMap
var pass_gate: TownPassGate         # the Town Pass at the gangway: World ID, once, at sign-up
var director: Director
var presence: Presence
var sound: Sound
var _lapsing := false          # the sky is set for a scene (the title, the opening): not the player's choice of time of day
var ui: Control                # the plates on screen: your energy, what floats over things
var energy_plate: EnergyPlate
var link_notice: LinkNotice
var weather = null            # no seasons-and-weather system in the valley yet (the HUD asks)
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
var _blend_speed := 1.0
var lamps: Array = []          # [position, linear colour, intensity, range]
var lamp_w := PackedFloat32Array()   # each lamp's eased weight
var lamp_heads: Array = []     # street lamp heads, for their halos and ground glow
var city_mat: ShaderMaterial
var shafts: Node3D
var fireflies: MultiMeshInstance3D
var halos: MultiMeshInstance3D
var _capturing := false         # dev screenshots: leave the player's saved choices alone

func _ready() -> void:
	data = WorldData.load_file(WORLD_FILE)
	rng.seed = int(data.d.seed)
	kit = _try_load("res://scripts/kit/kit.gd")
	river_kit = _try_load("res://scripts/river/river_kit.gd")
	for r in data.d.river.reaches:
		if r.get("mirror", false): mirror_y = float(r.points[0][3])
	_pick_quality()
	get_viewport().mesh_lod_threshold = LOD_PIXELS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lod="): get_viewport().mesh_lod_threshold = float(a.trim_prefix("--lod="))
	_lighting(_start_mode())
	if _on("town"): _level_town()
	_terrain()
	if _on("water"): _water()
	if _on("town"): _town()
	if _on("street"): _street()
	if _on("grass"): _fields()
	if _on("trees"): _trees()
	if _on("flowers"): _flowers()
	_player()
	if _on("post"): _post()
	_apply_look(look)
	if _on("market"): _market()
	if PORT_DRESSING and _on("port"):
		var port := PortDressing.new()
		add_child(port)
		port.setup(self)
	_near_only()
	if OS.has_feature("web") or OS.get_cmdline_user_args().has("--warm"): _warm_up()
	if OS.get_cmdline_user_args().has("--game"): _game()     # the old game layer, off: being replanned from scratch
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shots="):
			_capture(a.trim_prefix("--shots="))
			return
	set_render_scale(float(_setting("chosen_render_scale", 1.0)), false)
	steady_frames = bool(_setting("steady_frames", true)) and not OS.get_cmdline_user_args().has("--free-frames")     # dev: measure without it
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if quality == "low": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	for a in args:
		if a.begins_with("--render-scale="):
			set_render_scale(float(a.trim_prefix("--render-scale=")), false)
	for a in args:
		if a == "--no-msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		if a.begins_with("--shadow-size="): RenderingServer.directional_shadow_atlas_set_size(int(a.trim_prefix("--shadow-size=")), true)
	for a in args:
		for i in SEASONS.size():
			if a == "--season=" + str(SEASONS[i][0]).replace(" ", "-"): _set_season(i)
	for a in args:
		if a.begins_with("--snap="):      # dev: exactly what a player sees after 10 s, then quit
			_snap(a.trim_prefix("--snap="))
			return

## Shader warm-up (the web): a browser compiles each shader the first time something is drawn with it, a few seconds each
## (ANGLE on Direct3D), and the town's first frame would ask for all of them at once and hold the page for minutes. So the
## camera sees only a speck while the town's materials are drawn on it once each, a shader every two frames, behind the
## boot screen (main.gd fills its line from warm_progress); `warmed` says it's done. -- --warm runs it on the desktop too.
signal warmed
const WARM_LAYER := 1 << 19
var warm_progress := 1.0

## What decides the shader a material is drawn with: its own shader, or for a StandardMaterial3D the features it turns on.
func _shader_key(m: Material):
	if m is ShaderMaterial: return (m as ShaderMaterial).shader
	if not m is BaseMaterial3D: return m
	var b := m as BaseMaterial3D
	var k := [b.get_class(), b.transparency, b.shading_mode, b.cull_mode, b.blend_mode, b.depth_draw_mode, b.vertex_color_use_as_albedo, b.vertex_color_is_srgb,
		b.billboard_mode, b.no_depth_test, b.emission_enabled, b.normal_enabled, b.specular_mode, b.diffuse_mode, b.texture_filter, b.next_pass != null]
	for t in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_EMISSION]:
		k.append(b.get_texture(t) != null)
	return str(k)

func _warm_up() -> void:
	var by_shader := {}
	for gi in find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		var list: Array = [g.material_override, g.material_overlay]
		var mesh: Mesh = null
		if g is MeshInstance3D: mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh: mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh and g.material_override == null:
			for i in mesh.get_surface_count():
				var over: Material = (g as MeshInstance3D).get_surface_override_material(i) if g is MeshInstance3D else null
				list.append(over if over else mesh.surface_get_material(i))
		for m in list:
			if m == null: continue
			var key = _shader_key(m)     # materials on one shader share its programs
			if key != null and not by_shader.has(key): by_shader[key] = m
	var mats: Array = by_shader.values()
	var t0 := Time.get_ticks_msec()
	if mats.is_empty(): return
	warm_progress = 0.0
	var masks := {}                   # the cameras looked through meanwhile, and what they saw: they see only the specks till done
	var stage := Node3D.new()
	get_parent().add_child.call_deferred(stage)
	await get_tree().process_frame
	var speck := QuadMesh.new()
	speck.size = Vector2.ONE * 0.01
	for i in mats.size():
		var mi := MeshInstance3D.new()
		mi.mesh = speck
		mi.material_override = mats[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = WARM_LAYER
		stage.add_child(mi)
		for f in 2:     # drawn this frame: its shader is compiled
			var cam := get_viewport().get_camera_3d()     # whichever is current now: the opening may switch
			if cam:
				if not masks.has(cam): masks[cam] = cam.cull_mask
				cam.cull_mask = WARM_LAYER
				mi.global_transform = cam.global_transform * Transform3D(Basis(), Vector3(0.0, 0.0, -1.0))
			await get_tree().process_frame
		mi.queue_free()
		warm_progress = float(i + 1) / mats.size()
	stage.queue_free()
	for cam in masks: if is_instance_valid(cam): (cam as Camera3D).cull_mask = masks[cam]
	print("warm-up: %d shaders in %.1f s" % [mats.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	warmed.emit()

## Dev: -- --off=grass,water,bank leaves those parts out (to time them).
func _on(part: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--off=") and part in a.trim_prefix("--off=").split(","): return false
	return true

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

func _mesh(mesh: Mesh, mat: Material, shadows := true, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = layers
	add_child(mi)
	return mi

# --- keep-out shapes ------------------------------------------------------------------------------
# --- light & atmosphere (Game.ts: sun #ffc591 x 3.1, sky environment x 0.9, ACES, bloom) --------------------
static func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

func _lighting(pname: String) -> void:
	mode = pname
	look = _look(pname)
	preset = data.d.lighting.get(pname, DAWN_SUN)
	RenderingServer.global_shader_parameter_set("vh_wind", Vector2(0.82, 0.38))
	RenderingServer.global_shader_parameter_set("fol_noise_tex", MeadowNoise.texture())
	RenderingServer.global_shader_parameter_set("vh_water_y", mirror_y)
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.shadow_enabled = _on("shadows") and quality == "high"
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL     # one map: the trimmed valley needs no far split
	sun.directional_shadow_max_distance = 45.0
	var sky := Sky.new()
	sky.sky_material = _mat("res://shaders/valley/sky.gdshader")
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL   # nothing reads its radiance (ambient and reflections are off): never re-render it each frame
	env = Environment.new()
	env.background_mode = Environment.BG_SKY if _on("sky") else Environment.BG_COLOR
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
	world_env = env
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
	var saved := str(_setting("time_of_day", ""))
	return saved if SkyModes.LOOKS.has(saved) else str(data.d.lighting.default)

## A mode's full look: SkyModes' atmosphere + world.json's sun placement, colour and intensity + the SH of
## that sky, computed once per mode.
func _look(m: String) -> Dictionary:
	if looks.has(m): return looks[m]
	var lk: Dictionary = SkyModes.LOOKS[m].duplicate(true)
	var w: Dictionary = data.d.lighting.get(m, DAWN_SUN)
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
	_foliage_light(to_light, Vector3(sc.r, sc.g, sc.b) * lerpf(1.0, 0.3, float(lk.vh_night)), float(lk.vh_night))
	for gm in glow_mats: (gm[0] as ShaderMaterial).set_shader_parameter("emission_energy", float(gm[1]) * (1.0 + 3.0 * float(lk.vh_night)))
	if post:
		for g in lk.grade: post.material.set_shader_parameter(g, lk.grade[g])
		if quality == "low":
			post.material.set_shader_parameter("bloom_strength", 0.0)
			post.material.set_shader_parameter("rays", 0.0)
	if city_mat:
		city_mat.set_shader_parameter("body", lk.city_body)
		city_mat.set_shader_parameter("sun_tint", lk.city_sun)
	if shafts: shafts.visible = rays_on and (lk.vh_shafts as Vector4).x > 0.002
	if fireflies: fireflies.visible = lk.vh_night > 0.02
	if halos: halos.visible = (lk.vh_glow as Vector4).w > 0.02

## Quality: "high" (the sun's shadow map, three rings of grass, bloom and light rays, MSAA) or "low", for old
## phones and browsers (no shadow map: soft blob shadows under the trees and the player, as just-a-simple-tree
## shadows its impostors; the near ring of grass only; the trees' lighter copies sooner; 75% render scale; no
## bloom, light rays or MSAA). The web and phones start low; Q switches (and restarts the scene); -- --quality=low.
var quality := "high"

func _pick_quality() -> void:
	quality = str(_setting("chosen_quality", "low" if OS.has_feature("web") or OS.has_feature("mobile") else "high"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="): quality = a.trim_prefix("--quality=")

## A soft shadow on the ground at `at` (on `parent`, which it follows), `radius` metres round.
func _blob(at: Vector3, radius: float, parent: Node3D) -> void:
	if not mats.has("blob"): mats["blob"] = _mat("res://shaders/valley/blob_shadow.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 2.0
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mats["blob"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent == self: at.y = height_at(at.x, at.z) + 0.04
	else: at.y = 0.04
	mi.position = at
	parent.add_child(mi)

## Render scale: the 3D image drawn at a fraction of the window and scaled up (bilinear, the only scaling the
## Compatibility renderer has), then sharpened back in the grade pass. For weak devices; off (1.0) by default.
const RENDER_SCALES := [1.0, 0.75, 0.6]
var render_scale := 1.0

func set_render_scale(s: float, remember := true) -> void:
	render_scale = s
	get_viewport().scaling_3d_scale = s
	if post: post.material.set_shader_parameter("sharpen", clampf((1.0 - s) / 0.4, 0.0, 1.0) if s < 0.99 else 0.0)
	if remember: _save_setting("chosen_render_scale", s)

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
	if not _lapsing: _save_setting("time_of_day", m)
	time_mode_changed.emit(m)

## The sky moves to a time of day over this long; what the player last chose is theirs again after.
func ease_to_mode(m: String, seconds: float) -> void:
	set_time_mode(m)
	_blend_speed = MODE_BLEND / seconds
	await get_tree().create_timer(seconds + 0.1).timeout
	_blend_speed = 1.0
	_lapsing = false

## The whole town hears something at once.
func town_reacts(bad_news: bool) -> void:
	presence.react(not bad_news)
	people.react(not bad_news, TOWN_SQUARE)

## Banners on the square for the season, in its colour: the town shows what's coming.
func put_up_banners(colour: Color) -> void:
	if _banners.is_empty():
		for at in BANNERS_AT:
			var pole := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.035
			pm.bottom_radius = 0.045
			pm.height = 5.2
			pole.mesh = pm
			var steel := StandardMaterial3D.new()
			steel.albedo_color = Color("34373c")
			pole.material_override = steel
			pole.position = Vector3(at.x, height_at(at.x, at.y) + 2.6, at.y)
			add_child(pole)
			var cloth := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.9, 2.4)
			cloth.mesh = qm
			cloth.position = Vector3(0.5, 1.1, 0.0)
			pole.add_child(cloth)
			_banners.append(cloth)
	for b in _banners:
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.material_override = m
		b.scale = Vector3(1.0, 0.05, 1.0)
		create_tween().tween_property(b, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The trees for a season, by its place in SEASONS.
func set_season_look(i: int) -> void:
	_set_season(i)

func cycle_time_mode() -> void:
	set_time_mode(SkyModes.ORDER[(SkyModes.ORDER.find(mode) + 1) % SkyModes.ORDER.size()])

func _unhandled_input(e: InputEvent) -> void:
	if Screens.holding(): return
	if e.is_action_pressed("time_of_day"): cycle_time_mode()
	elif not OS.is_debug_build(): return     # the rest are for working on the town, not in the shipped game
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F2:
		_save_setting("chosen_quality", "low" if quality == "high" else "high")
		get_tree().reload_current_scene()
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_U:
		set_render_scale(RENDER_SCALES[(RENDER_SCALES.find(render_scale) + 1) % RENDER_SCALES.size()])
		print("render scale: ", render_scale)
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_Y and not leaf_mats.is_empty():
		_set_season(_season_i + 1)
		print("season: ", SEASONS[_season_i][0])

func _update_time_of_day(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(_blend + delta / MODE_BLEND * _blend_speed, 1.0)
		_apply_look(SkyModes.mix(_look_from, _look_to, smoothstep(0.0, 1.0, _blend)))
	RenderingServer.global_shader_parameter_set("vh_time", Time.get_ticks_msec() * 0.001)
	_update_lamps(delta)
	_update_sun_on_screen()

## Light the lamps around the player whose light can reach the view, eased in and out (the base game's).
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
	var pos: Array = []
	var col: Array = []
	for j in n:
		var l: Array = lamps[live[j]]
		var c: Color = l[1] * (float(l[2]) * k * lamp_w[live[j]])
		pos.append(Color(l[0].x, l[0].y, l[0].z, l[3]))
		col.append(Color(c.r, c.g, c.b, 0.0))
	VHTex.set_lamps(pos, col)

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

# --- the town: every building of the town master, 1:1 (tools/blender/export_town.py -> assets/town) ---------------
const TOWN := "res://assets/town/manifest.json"
## The buildings you can walk into: collision from their own geometry (lettering and emblems left out), not boxes.
const WALK_IN := ["DV-01", "DV-02", "DV-03", "DV-04"]
const ROOM_SLOTS := 9          # the rooms shaders/valley/town_pbr.gdshader has space for
## Their rooms (shaders/valley/town_pbr.gdshader): low corner, high corner, sky light kept, indoor light.
const ROOMS := [
	[Vector3(-35.3, -0.2, 9.0), Vector3(-18.7, 16.0, 22.3), 0.12, 0.55],     # the bank
	[Vector3(-39.2, -0.6, -39.2), Vector3(-0.8, 9.4, -15.2), 0.45, 0.32],    # the market hall, under its glass roof
	[Vector3(7.0, -0.7, 9.8), Vector3(22.2, 8.0, 23.3), 0.12, 0.6],         # the common table
	[Vector3(-79.0, -0.3, 10.4), Vector3(-53.0, 3.7, 26.2), 0.15, 0.6],     # the arrival hall, its ground floor
	[Vector3(-44.0, -1.2, 39.1), Vector3(-37.0, 2.8, 44.8), 0.2, 0.62],     # your room, a little past its walls: the light fades over the box's last 0.5 m
]
const LOD_PIXELS := 3.0        # how many pixels a building's lighter copy may be off by
const LETTER_LOD_BIAS := 4.0   # lettering breaks up early as it is simplified: it switches to a lighter copy this much later
const DETAIL_BIG := 5.0       # m: a building's parts shorter than this count as detail
const DETAIL_SEEN_PER_M := 25.0   # how far a detail is drawn, per metre of its size (plus 20 m)
const LEVEL_EDGE := 5.0       # m over which the levelled ground eases back into the land round a building
var town := {}                 # id -> {glb, min, max, base_y, parts}
var town_rects: Array = []     # each building's footprint (Rect2), for what is planted round them
var court_trees: Array = []    # where a big tree stands in a courtyard (Vector2)
var glow_mats: Array = []      # [material, its daylight emission]: lit rooms and lamps, brighter as night falls
## Buildings rebuilt after the concepts (game/world/valley/buildings.json, tools/blender/build_quarter.py
## --recipes=... --out=game/assets/town): each takes the place of the master's, centred where it stood, its
## front (+Z) to the street. Prototypes, to be judged before the rest follow.
const REBUILT := {
	"DV-06": {"glb": "dv06_grocery.glb", "footprint": [26.7, 19.2], "height": 7.3},
	"DV-07": {"glb": "dv07_corner.glb", "footprint": [20.2, 14.4], "height": 10.6},
	"DV-08": {"glb": "dv08_repair.glb", "footprint": [18.7, 14.7], "height": 7.6, "yaw": PI},
	"DV-09": {"glb": "dv09_broker.glb", "footprint": [20.5, 16.9], "height": 12.8},
	"DV-10": {"glb": "dv10_pawn.glb", "footprint": [17.0, 14.9], "height": 10.6},
	# the courtyard blocks: a box per wing (x0, z0, x1, z1 about the centre, as placed), a big tree in the court
	"DV-22": {"glb": "dv22_apartments.glb", "footprint": [56.9, 32.9], "height": 11.9, "yaw": PI, "tree": [0.0, -5.0],
		"wings": [[-28.0, 6.0, 28.0, 16.0], [-28.0, -16.0, -18.0, 6.0], [18.0, -16.0, 28.0, 6.0]]},
	"DV-05": {"glb": "dv05_homes.glb", "footprint": [34.9, 20.9], "height": 11.9, "yaw": PI, "tree": [0.0, -4.0],
		"wings": [[-17.0, 2.0, 17.0, 10.0], [-17.0, -10.0, -9.0, 2.0], [9.0, -10.0, 17.0, 2.0]]},
}

func _read_town() -> void:
	if not town.is_empty() or not FileAccess.file_exists(TOWN): return
	var m = JSON.parse_string(FileAccess.get_file_as_string(TOWN))
	if not m is Dictionary: return
	for id in m.buildings:
		var b: Dictionary = m.buildings[id]
		var r := Rect2(b.min[0], b.min[2], b.max[0] - b.min[0], b.max[2] - b.min[2])
		if not MAP.intersects(r): continue
		if REBUILT.has(id):
			var nb: Dictionary = REBUILT[id]
			var c := r.get_center()
			var half := Vector2(nb.footprint[0], nb.footprint[1]) * 0.5
			var parts := []
			for wg in nb.get("wings", [[-half.x, -half.y, half.x, half.y]]):
				parts.append([[c.x + wg[0], b.base_y, c.y + wg[1]], [c.x + wg[2], b.base_y + float(nb.height), c.y + wg[3]]])
			b = {"glb": nb.glb, "pos": [c.x, c.y], "base_y": b.base_y, "yaw": nb.get("yaw", 0.0), "parts": parts}
			if nb.has("tree"): court_trees.append(c + Vector2(nb.tree[0], nb.tree[1]))
			r = Rect2(c - half, half * 2.0)
		b.rect = r
		town[id] = b
		town_rects.append(r)
	town["_offset"] = m.offset

## Level the ground under each building to the height its base stands at, easing back over LEVEL_EDGE, so none
## stands lifted over a dip or sunk into a rise. Done to the height field itself, before the terrain, its
## collider and the grass read it.
func _level_town() -> void:
	_read_town()
	for id in town:
		if id == "_offset": continue
		var r: Rect2 = (town[id].rect as Rect2).grow(0.5)
		var y: float = town[id].base_y
		var ix0 := maxi(0, floori((r.position.x - LEVEL_EDGE - data.x0) / data.res))
		var ix1 := mini(data.nx - 1, ceili((r.end.x + LEVEL_EDGE - data.x0) / data.res))
		var iz0 := maxi(0, floori((r.position.y - LEVEL_EDGE - data.z0) / data.res))
		var iz1 := mini(data.nz - 1, ceili((r.end.y + LEVEL_EDGE - data.z0) / data.res))
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var p := Vector2(data.x0 + ix * data.res, data.z0 + iz * data.res)
				var d := Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)).length()
				var k := 1.0 - smoothstep(0.0, LEVEL_EDGE, d)
				var o := (iz * data.nx + ix) * 4
				data.field[o] = lerpf(data.field[o], y, k)
	var img := Image.create_from_data(data.nx, data.nz, false, Image.FORMAT_RGBAF, data.field.to_byte_array())
	data.field_tex = ImageTexture.create_from_image(img)

func _town() -> void:
	_read_town()
	var off: Array = town.get("_offset", [0, 0, 0])
	var body := StaticBody3D.new()
	add_child(body)
	var n := 0
	for id in town:
		if id == "_offset": continue
		var b: Dictionary = town[id]
		var path := "res://assets/town/" + str(b.glb)
		if not ResourceLoader.exists(path): continue
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.name = id
		model.position = Vector3(b.pos[0], b.base_y, b.pos[1]) if b.has("pos") else Vector3(off[0], off[1], off[2])
		model.rotation.y = float(b.get("yaw", 0.0))
		add_child(model)
		_town_materials(model)
		_town_detail(model)
		_building_nodes.append([model, b.rect])
		if id in WALK_IN:
			for node in model.find_children("*", "MeshInstance3D", true, false):
				var label := String(node.name).to_lower()
				if label.contains("lettering") or label.contains("emblem") or label.contains("inscription") or label.contains("brand mark"): continue
				(node as MeshInstance3D).create_trimesh_collision()
			n += 1
			continue
		for part in b.parts:      # a box round each part, to walk into
			var lo := Vector3(part[0][0], part[0][1], part[0][2])
			var hi := Vector3(part[1][0], part[1][1], part[1][2])
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = hi - lo
			cs.shape = box
			cs.position = (lo + hi) * 0.5
			body.add_child(cs)
		n += 1
	print("town: ", n, " buildings")

## Small parts of a building (lettering, fixtures) are seen only as close as their size is worth, and cast no shadow.
func _town_detail(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var label := String(mi.name).to_lower()
		if label.contains("lettering") or label.contains("inscription"): mi.lod_bias = LETTER_LOD_BIAS
		var big := mi.get_aabb().get_longest_axis_size()
		mi.visibility_range_end = FAR_BUILDING
		if big >= DETAIL_BIG: continue
		mi.visibility_range_end = DETAIL_SEEN_PER_M * big + 20.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Each surface exactly as the town master's Blender material has it: "paint" and "metal" take their vertex
## colours (roughness 0.78; metal 0.28 metallic), "glow" its vertex colour lit a little from within, "glass" /
## "glazing" clear glass (shaders/valley/glazing.gdshader: the vertex alpha x 0.28, roughness 0.19), and the
## ink, paper and pearl lettering their own flat colours. Lit by the valley's sun and sky (shaders/vh/pbr.gdshader).
func _town_materials(model: Node) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			(mi as MeshInstance3D).set_surface_override_material(i, _town_mat(mesh, i))

## A surface's material as the town master has it, on the valley's light (cached by name, colour and vertex colour).
func _town_mat(mesh: Mesh, i: int) -> Material:
	var src: Material = mesh.surface_get_material(i)
	var nm: String = (src.resource_name if src else "").to_lower()
	var vcol: bool = mesh is ArrayMesh and (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0
	var base := Color(0.8, 0.8, 0.8)
	if src is BaseMaterial3D: base = (src as BaseMaterial3D).albedo_color
	var key := "town|" + nm + ("|v" if vcol else "|" + base.to_html())
	if mats.has(key): return mats[key]
	var m := ShaderMaterial.new()
	var bm := src as BaseMaterial3D
	if nm.contains("glaz") or nm.contains("glass"):
		m.shader = load("res://shaders/valley/glazing.gdshader")
		m.set_shader_parameter("use_vcol", vcol)
		m.set_shader_parameter("tint", base)
	else:
		m.shader = load("res://shaders/valley/town_pbr.gdshader")
		var lo := PackedVector4Array()
		var hi := PackedVector4Array()
		for i2 in ROOM_SLOTS:
			var room: Array = all_rooms()[i2] if i2 < all_rooms().size() else [Vector3.ZERO, Vector3.ZERO, 1.0, 0.0]
			lo.append(Vector4(room[0].x, room[0].y, room[0].z, room[2]))
			hi.append(Vector4(room[1].x, room[1].y, room[1].z, room[3]))
		m.set_shader_parameter("room_lo", lo)
		m.set_shader_parameter("room_hi", hi)
		m.set_shader_parameter("use_vcol", vcol)
		# the importer gives the glTF colour as sRGB already, as the shader's albedo wants it
		m.set_shader_parameter("albedo", Color.WHITE if vcol else base)
		m.set_shader_parameter("rough", bm.roughness if bm and not vcol else 0.78)
		m.set_shader_parameter("metal", bm.metallic if bm and not vcol else (0.28 if nm.contains("metal") else 0.0))
		if nm.contains("glow") or nm == "light" or (bm and bm.emission_enabled):
			m.set_shader_parameter("emission_color", base if not vcol else Color("ffe2b8"))
			var e: float = bm.emission_energy_multiplier if bm and bm.emission_enabled and not vcol else 0.65
			m.set_shader_parameter("emission_energy", e)
			glow_mats.append([m, e])
	mats[key] = m
	return m

# --- street furniture: the town master's lamps, benches, bikes, pots, walls, crates ... (tools/blender/export_props.py)
const STREET := "res://assets/town/props/"
## what a copy of an item may be walked into: items smaller than this (m, the larger side) take no collider
const PROP_SOLID := 0.7
const PROP_CELL := 16.0        # m: copies are drawn by the map cell they stand in, so those off screen cost nothing
const PROP_NEAR := 30.0        # m to a cell's middle: a heavy item's whole model within this, its lighter copy (_far.glb) beyond
var prop_spots: Array = []     # where each piece stands (Vector2), for the trees to keep clear of

func _street() -> void:
	if not FileAccess.file_exists(STREET + "placements.json"): return
	var items = JSON.parse_string(FileAccess.get_file_as_string(STREET + "placements.json"))
	if not items is Dictionary: return
	var body := StaticBody3D.new()
	add_child(body)
	var n := 0
	for name in items:
		var it: Dictionary = items[name]
		if not ResourceLoader.exists(STREET + str(it.glb)): continue
		var mesh := _bake_file(STREET + str(it.glb))
		if mesh.get_surface_count() == 0: continue
		var far: ArrayMesh = _bake_file(STREET + str(it.far)) if it.has("far") else null
		var xfs: Array = []
		for r in it.xfs:
			var xf := Transform3D(Basis(Vector3(r[0][0], r[1][0], r[2][0]), Vector3(r[0][1], r[1][1], r[2][1]), Vector3(r[0][2], r[1][2], r[2][2])), Vector3(r[0][3], r[1][3], r[2][3]))
			if not MAP.has_point(Vector2(xf.origin.x, xf.origin.z)) or HOME_RECT.has_point(Vector2(xf.origin.x, xf.origin.z)): continue
			xfs.append(xf)
			prop_spots.append(Vector2(xf.origin.x, xf.origin.z))
		if xfs.is_empty(): continue
		var lo := Vector3(it.min[0], it.min[1], it.min[2])
		var hi := Vector3(it.max[0], it.max[1], it.max[2])
		var size := hi - lo
		# seen as far as its size is worth: lamps and walls across the town, a pot or a crate only close by
		var big := maxf(size.y, maxf(size.x, size.z))
		var seen_to := 140.0 if big > 2.5 else (90.0 if big > 1.2 else 45.0)
		var cells := {}
		for xf in xfs:
			var cell := Vector2i(floori(xf.origin.x / PROP_CELL), floori(xf.origin.z / PROP_CELL))
			if not cells.has(cell): cells[cell] = []
			cells[cell].append(xf)
		for cell in cells:
			_prop_batch(mesh, cells[cell], 0.0, PROP_NEAR if far else seen_to, big > 1.2)
			if far: _prop_batch(far, cells[cell], PROP_NEAR, seen_to, big > 1.2)
		for xf in xfs:
			if str(name).contains("street_lamp"):    # its light, just under the top of the post
				_add_lamp(LAMP_STREET, xf * Vector3((lo.x + hi.x) * 0.5, hi.y - 0.35, (lo.z + hi.z) * 0.5))
			elif str(name).contains("bollard"):
				_add_lamp(LAMP_BOLLARD, xf * Vector3(0.0, hi.y - 0.1, 0.0))
			if maxf(size.x, size.z) >= PROP_SOLID and size.y > 0.3:
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = size
				cs.shape = box
				cs.transform = xf * Transform3D(Basis(), (lo + hi) * 0.5)
				body.add_child(cs)
		n += xfs.size()
	print("street: ", n, " pieces of ", items.size(), " kinds, lamps ", lamps.size())

func _prop_batch(mesh: Mesh, xfs: Array, seen_from: float, seen_to: float, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_begin = seen_from
	mmi.visibility_range_end = seen_to
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_prop_nodes.append([mmi, (xfs[0] as Transform3D).origin])

func _bake_file(path: String) -> ArrayMesh:
	if not ResourceLoader.exists(path): return ArrayMesh.new()
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	var mesh := _bake(scene)
	scene.free()
	return mesh

## A model's meshes as one mesh in its own frame, a surface per surface, in the town's materials.
func _bake(root: Node3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != root and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for i in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(mi.mesh, i, xf)
			st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, _town_mat(mi.mesh, i))
	return out

# --- trees: just-a-simple-tree's oak, pine, cypress and bush at every age, in their own leaves (ValleyTrees) ----
const TREE_COUNT := 150          # the meadow's, past those planted on purpose
const TREE_SPACING := 8.5
const STREET_STEP := 7.0          # m between places a street tree is tried
const STREET_SPACING := 7.5
const STREET_FROM := 2.6          # m from the paving
const STREET_TO := 5.0
const RIVER_SPACING := 5.5
const STREET_MIX := {"young": 0.5, "oak": 0.25, "cypress": 0.25}
const RIVER_MIX := {"bush": 0.65, "young": 0.35}
# kept clear: the landing's kiosks, the jetty's way, and the open ground on the square, by the river and in the apartments' court
const KEEP_CLEAR := [Rect2(-103.0, 40.0, 19.0, 19.0), Rect2(-112.0, 46.0, 10.0, 6.0), Rect2(-98.0, 70.0, 12.0, 18.0), Rect2(-9.0, -13.0, 8.0, 8.0), Rect2(-27.0, 74.0, 38.0, 22.0)]
# gardens: a bush at each spot
# planted by hand, kind and place: the edges of the square, the bank's front, the Homes, the apartments' court and the hall's forecourt
const PLANTED := [["young", -46.0, -9.5], ["young", -39.0, 1.0], ["cypress", -36.5, 3.2], ["cypress", -17.0, 3.2], ["young", -13.0, 0.5], ["oak", -3.0, -6.0], ["young", 3.0, -5.0],
	["young", -46.0, -16.0], ["young", -2.0, -13.0], ["cypress", -41.5, -13.0], ["cypress", 0.5, -14.0], ["young", 4.5, 3.0], ["young", 25.5, 8.0],
	["young", -50.5, 33.0], ["young", -36.0, 34.0], ["cypress", -55.0, 36.5], ["cypress", -36.5, 38.5],
	["young", -24.0, 75.5], ["young", 8.0, 75.5], ["cypress", -24.5, 84.5], ["cypress", 9.0, 84.5], ["young", -8.0, 74.0],
	["young", -78.0, 7.5], ["young", -55.0, 7.0], ["cypress", -66.0, 7.5], ["oak", -80.5, 30.0], ["young", -52.0, 30.0]]
# hedges: bushes in a row, from, to
const HEDGES := [[Vector2(-38.0, 7.5), Vector2(-30.5, 7.5)], [Vector2(-24.0, 7.5), Vector2(-16.0, 7.5)], [Vector2(-50.0, 31.0), Vector2(-40.0, 31.0)], [Vector2(-6.0, 72.5), Vector2(4.0, 72.5)], [Vector2(-22.0, 72.5), Vector2(-11.0, 72.5)],
	[Vector2(-77.0, 8.8), Vector2(-68.0, 8.8)], [Vector2(-64.0, 8.8), Vector2(-55.0, 8.8)], [Vector2(1.5, 7.8), Vector2(7.0, 7.8)]]
const HEDGE_STEP := 1.9            # m between bushes
const GARDEN_BUSHES := [Vector2(-31.0, 7.0), Vector2(-23.0, 7.0), Vector2(-44.0, 31.5), Vector2(-54.0, 31.5), Vector2(-37.0, 31.5), Vector2(1.0, 7.0), Vector2(23.0, 7.5), Vector2(-52.0, 6.5), Vector2(-80.0, 8.0), Vector2(-80.0, 27.0), Vector2(-27.0, 72.0), Vector2(11.0, 72.0), Vector2(-41.0, -12.5), Vector2(1.5, -13.0), Vector2(-105.0, 56.0), Vector2(-105.0, 42.0)]
const TREE_NEAR := 35.0        # whole trees within this (m), their lighter copies beyond
## what grows round the bank, by share: pines in many shapes, oaks old and young, a few cypresses and bushes
const TREE_MIX := {"pine": 0.4, "oak": 0.25, "young": 0.12, "cypress": 0.1, "bush": 0.13}
## Y steps the year through: every tree at its own season, then all in spring, summer, autumn, winter
const SEASONS := [["every season", 0.35, 1.0], ["spring", 0.12, 0.0], ["summer", 0.35, 0.0], ["autumn", 0.62, 0.0], ["winter", 0.97, 0.0]]
var _season_i := 0
var leaf_mats: Array[ShaderMaterial] = []
var _far_mats := {}
const ROOM_THINGS_SEEN := 75.0  # m
const PEOPLE_SEEN := 70.0       # m
const KIOSKS_SEEN := 95.0       # m
const PORT_DRESSING := false     # the river's reeds, boats, tree line and the rest (port_dressing.gd): turned down by the founder, kept on file
const SHADOW_WITHIN := 85.0    # m to a building or a street's things: past this they cast nothing
const PROP_SHADOW_WITHIN := 60.0   # m: low things throw short shadows, and the map reaches 45
const SHADOW_LOOK_EVERY := 0.5  # s
var _shadow_look_in := 0.0
const FAR_REGION := 240.0      # m

func _trees() -> void:
	var spots: Array = court_trees.duplicate()
	var chosen := {}                   # a spot -> its kind, where it was planted on purpose
	for p in GARDEN_BUSHES:
		spots.append(p)
		chosen[p] = "bush"
	for t in PLANTED + (PortDressing.tree_line(data) if PORT_DRESSING else []):
		var p := Vector2(t[1], t[2])
		spots.append(p)
		chosen[p] = t[0]
	for h in HEDGES:
		var from: Vector2 = h[0]
		var to: Vector2 = h[1]
		var n := int(from.distance_to(to) / HEDGE_STEP)
		for i in n + 1:
			var p := from.lerp(to, float(i) / maxi(n, 1)) + Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
			spots.append(p)
			chosen[p] = "bush"
	var street: Array = []
	var river: Array = []
	var x := MAP.position.x + 4.0
	while x < MAP.end.x - 4.0:
		var z := MAP.position.y + 4.0
		while z < MAP.end.y - 4.0:
			var p := Vector2(x + rng.randf_range(-2.0, 2.0), z + rng.randf_range(-2.0, 2.0))
			var pave := data.pave_dist(p)
			var water := data.water_sd(p)
			if pave > STREET_FROM and pave < STREET_TO and water > 3.0: street.append(p)
			elif water > 3.5 and water < 8.0 and pave > 2.6: river.append(p)
			z += STREET_STEP
		x += STREET_STEP
	for p in street:
		if _can_plant(p, spots, STREET_SPACING):
			spots.append(p)
			chosen[p] = _pick_from(STREET_MIX)
	for p in river:
		if _can_plant(p, spots, RIVER_SPACING):
			spots.append(p)
			chosen[p] = _pick_from(RIVER_MIX)
	var planted := spots.size()
	var tries := 0
	while spots.size() < planted + TREE_COUNT and tries < 8000:
		tries += 1
		var p := Vector2(rng.randf_range(MAP.position.x + 8.0, MAP.end.x - 8.0), rng.randf_range(MAP.position.y + 8.0, MAP.end.y - 8.0))
		if not MAP.has_point(p) or data.water_sd(p) < 3.0 or data.pave_dist(p) < 3.0: continue
		if _can_plant(p, spots, TREE_SPACING): spots.append(p)
	var wood_mat := _mat("res://shaders/foliage/wood.gdshader")
	var pal: Dictionary = TreeSpecies.PALETTES["green"]
	for i in 3: wood_mat.set_shader_parameter(["shadow_col", "mid_col", "light_col"][i], Color(pal.wood[i]))
	var leaf := {}
	for name in ["round", "willow"]:
		var m := _mat("res://shaders/valley/leaf_cards.gdshader")
		m.set_shader_parameter("atlas", ValleyTrees.atlas(name))
		leaf[name] = m
		leaf_mats.append(m)
	var groups := {}
	for q in spots:
		var kind: String = "oak" if court_trees.has(q) else chosen.get(q, _pick_kind())
		var key := "%s:%d" % [kind, rng.randi_range(0, int(ValleyTrees.KINDS[kind].variants) - 1)]
		if not groups.has(key): groups[key] = {"tpl": ValleyTrees.build(kind, int(key.get_slice(":", 1))), "xf": []}
		groups[key].xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, height_at(q.x, q.y) - 0.05, q.y)))
	var far_bushes: Array = []            # far off, one bush looks like another: they share a shape
	var far_bush: Dictionary = {}
	var blobs: Array = []
	var near := TREE_NEAR if quality == "high" else TREE_NEAR * 0.5
	for a in OS.get_cmdline_user_args(): if a.begins_with("--tree-near="): near = float(a.trim_prefix("--tree-near="))     # dev: measuring
	for key in groups:
		var tpl: Dictionary = groups[key].tpl
		_tree_mmi(tpl.wood, wood_mat, groups[key].xf, 0.0, near)
		_tree_mmi(tpl.leaves, leaf[tpl.atlas], groups[key].xf, 0.0, near)
		if key.begins_with("bush:"):
			far_bushes.append_array(groups[key].xf)
			far_bush = tpl
		else:
			_far_trees(tpl.low_wood, _far_mat(wood_mat, near), groups[key].xf)
			_far_trees(tpl.low_leaves, _far_mat(leaf[tpl.atlas], near), groups[key].xf)
		if quality == "low":     # their soft shadows, in a few batches: a draw a region, not a draw a tree
			var r := float(tpl.crown_radius) * 1.1 + 0.6
			for xf in groups[key].xf: blobs.append(Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), Vector3(xf.origin.x, height_at(xf.origin.x, xf.origin.z) + 0.04, xf.origin.z)))
	if not far_bushes.is_empty():
		_far_trees(far_bush.low_wood, _far_mat(wood_mat, near), far_bushes)
		_far_trees(far_bush.low_leaves, _far_mat(leaf[far_bush.atlas], near), far_bushes)
	if not blobs.is_empty():
		if not mats.has("blob"): mats["blob"] = _mat("res://shaders/valley/blob_shadow.gdshader")
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 2.0
		q.orientation = PlaneMesh.FACE_Y
		_far_trees(q, mats["blob"], blobs)
	_set_season(0)
	print("trees: ", spots.size(), " in ", groups.size(), " shapes")

## Could a tree stand here, this far from any other?
func _can_plant(p: Vector2, spots: Array, spacing: float) -> bool:
	if not MAP.has_point(p): return false
	for r in town_rects:
		if (r as Rect2).grow(3.0).has_point(p): return false
	for r in KEEP_CLEAR:
		if (r as Rect2).has_point(p): return false
	for q in prop_spots:
		if p.distance_to(q) < 2.0: return false
	for q in spots:
		if p.distance_to(q) < spacing: return false
	return true

func _pick_from(mix: Dictionary) -> String:
	var r := rng.randf()
	for k in mix:
		r -= float(mix[k])
		if r <= 0.0: return k
	return mix.keys()[0]

## The material for far copies: the same, cut away where the close copies are.
func _far_mat(near_mat: ShaderMaterial, near: float) -> ShaderMaterial:
	if _far_mats.has(near_mat): return _far_mats[near_mat]
	var m: ShaderMaterial = near_mat.duplicate()
	m.set_shader_parameter("near_cut", near - 1.0)
	_far_mats[near_mat] = m
	if near_mat in leaf_mats: leaf_mats.append(m)
	return m

## A shape's far copies, in large regions of the map: a few draws however many trees there are, and what's behind the camera costs nothing.
func _far_trees(mesh: Mesh, mat: Material, list: Array) -> void:
	if list.is_empty() or mesh.get_surface_count() == 0: return
	var regions := {}
	for xf in list:
		var r := Vector2i(floori(xf.origin.x / FAR_REGION), floori(xf.origin.z / FAR_REGION))
		if not regions.has(r): regions[r] = []
		regions[r].append(xf)
	for r in regions:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = regions[r].size()
		for i in regions[r].size(): mm.set_instance_transform(i, regions[r][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _pick_kind() -> String:
	var r := rng.randf()
	for k in TREE_MIX:
		r -= float(TREE_MIX[k])
		if r <= 0.0: return k
	return "oak"

func _set_season(i: int) -> void:
	_season_i = i % SEASONS.size()
	RenderingServer.global_shader_parameter_set("fol_season", float(SEASONS[_season_i][1]))
	for m in leaf_mats: m.set_shader_parameter("season_spread", float(SEASONS[_season_i][2]))

## One tree shape's instances, each its own node (so each is culled and switches its detail by its own distance).
func _tree_mmi(mesh: Mesh, mat: Material, list: Array, vb: float, ve: float) -> void:
	if list.is_empty() or mesh.get_surface_count() == 0: return
	for xf in list:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.transform = xf
		mi.visibility_range_begin = vb
		mi.visibility_range_end = ve
		if vb > 0.0: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF     # past where the shadow map reaches
		add_child(mi)
		_tree_nodes.append([mi, (xf as Transform3D).origin])

# --- the newer terrain and grass (shaders/foliage) -----------------------------------------------------
func _terrain() -> void:
	var mat := _mat("res://shaders/valley/ground.gdshader")
	mat.set_shader_parameter("flag_tex", load("res://assets/valley/flagstones.png"))
	mat.set_shader_parameter("field_tex", data.field_tex)
	mat.set_shader_parameter("paved_tex", data.paved_tex)
	mat.set_shader_parameter("map_rect", data.field_rect)
	mat.set_shader_parameter("paved_rect", data.paved_rect)
	mat.set_shader_parameter("texel", Vector2(1.0 / data.nx, 1.0 / data.nz))
	mat.set_shader_parameter("cell", data.res)
	var near := _grid_mesh(int(TILE / data.res) / 2)
	var far := _grid_mesh(8)
	for tz in int(ceil(data.dep / TILE)):
		for tx in int(ceil(data.w / TILE)):
			if not MAP.grow(TILE).intersects(Rect2(data.x0 + tx * TILE, data.z0 + tz * TILE, TILE, TILE)) or not _on("ground"): continue
			for lod in [[near, 0.0, TILE_LOD, true], [far, TILE_LOD, 0.0, false]]:
				var mi := _mesh(lod[0], mat, false)
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

const FOL_SKY := Vector3(0.522, 0.686, 1.0)
const FOL_GROUND := Vector3(0.147, 0.102, 0.063)
const FOL_SHADOW := Vector4(0.027, 0.044, 0.107, 0.75)    # #2e3b5c at 0.75
func _foliage_light(to_light: Vector3, sun_lin: Vector3, night := 0.0) -> void:
	var k := clampf(sun_lin.dot(Vector3(0.2126, 0.7152, 0.0722)) / 4.5, lerpf(0.08, 0.2, night), 1.0)
	RenderingServer.global_shader_parameter_set("fol_dim", lerpf(1.0, 0.16, night))
	RenderingServer.global_shader_parameter_set("fol_sun", sun_lin)
	RenderingServer.global_shader_parameter_set("fol_sun_dir", to_light)
	RenderingServer.global_shader_parameter_set("fol_sky", FOL_SKY * k)
	RenderingServer.global_shader_parameter_set("fol_ground", FOL_GROUND * k)
	RenderingServer.global_shader_parameter_set("fol_shadow", FOL_SHADOW)

# --- flowers: drifts of them by the paths and round the gardens -------------------------------------------------------------
const FLOWER_COLOURS := [Color("f2c84b"), Color("e59aac"), Color("f1eee6"), Color("c98ad0"), Color("e0704a")]
const FLOWER_DRIFTS := 260
const FLOWERS_IN_A_DRIFT := Vector2i(10, 26)
const FLOWER_SEEN := 46.0          # m

func _flower_mesh(colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color):
		st.set_color(col)
		st.set_normal(Vector3.UP)
		for v in [a, b, c, a, c, d]: st.add_vertex(v)
	var stem := Color("4f7f3a")
	quad.call(Vector3(-0.012, 0.0, 0.0), Vector3(0.012, 0.0, 0.0), Vector3(0.012, 0.22, 0.0), Vector3(-0.012, 0.22, 0.0), stem)
	quad.call(Vector3(0.0, 0.0, -0.012), Vector3(0.0, 0.0, 0.012), Vector3(0.0, 0.22, 0.012), Vector3(0.0, 0.22, -0.012), stem)
	for k in 3:
		var a: float = k * PI / 3.0
		var dx := Vector3(cos(a), 0.0, sin(a)) * 0.06
		var dz := Vector3(-sin(a), 0.0, cos(a)) * 0.022
		quad.call(Vector3.UP * 0.225 - dx - dz, Vector3.UP * 0.225 + dx - dz, Vector3.UP * 0.225 + dx + dz, Vector3.UP * 0.225 - dx + dz, colour)
	return st.commit()

func _flowers() -> void:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 77
	var by_colour := {}
	var made := 0
	var tries := 0
	while made < FLOWER_DRIFTS and tries < 20000:
		tries += 1
		var c := Vector2(rnd.randf_range(MAP.position.x + 6.0, MAP.end.x - 6.0), rnd.randf_range(MAP.position.y + 6.0, MAP.end.y - 6.0))
		var pave := data.pave_dist(c)
		if pave < 0.9 or pave > 9.0 or data.water_sd(c) < 1.5: continue
		var blocked := false
		for r in town_rects:
			if (r as Rect2).grow(0.5).has_point(c): blocked = true
		if blocked: continue
		made += 1
		var colour: Color = FLOWER_COLOURS[rnd.randi_range(0, FLOWER_COLOURS.size() - 1)]
		var cell := Vector3i(floori(c.x / 24.0), floori(c.y / 24.0), FLOWER_COLOURS.find(colour))
		if not by_colour.has(cell): by_colour[cell] = []
		for i in rnd.randi_range(FLOWERS_IN_A_DRIFT.x, FLOWERS_IN_A_DRIFT.y):
			var a := rnd.randf() * TAU
			var r := sqrt(rnd.randf()) * 1.7
			var p := c + Vector2(cos(a), sin(a)) * r
			if data.pave_dist(p) < 0.5: continue
			var s := rnd.randf_range(0.8, 1.35)
			by_colour[cell].append(Transform3D(Basis(Vector3.UP, rnd.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height_at(p.x, p.y), p.y)))
	var meshes := {}
	for cell in by_colour:
		if not meshes.has(cell.z): meshes[cell.z] = _flower_mesh(FLOWER_COLOURS[cell.z])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[cell.z]
		mm.instance_count = by_colour[cell].size()
		for i in by_colour[cell].size(): mm.set_instance_transform(i, by_colour[cell][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.visibility_range_end = FLOWER_SEEN
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_prop_nodes.append([mmi, Vector3((cell.x + 0.5) * 24.0, 0.0, (cell.y + 0.5) * 24.0)])
	print("flowers: ", made, " drifts")

func _fields() -> void:
	RenderingServer.global_shader_parameter_set("fol_noise_tex", MeadowNoise.texture())
	add_child(GrassTrails.new())
	# The dense near grass as it was (rings 1 and 2, thinning out past 16 m), and a coarse third ring that carries
	# it out to 55 m: the blades sink into the ground, which paints the same lawn, so none pops.
	# [lattice spacing, outer radius, inner radius, blades a clump, strip segments, blade width, blade height, thin out]
	var rings := [[0.32, 9.0, 0.0, 13, 3, 0.033, 0.15, true], [0.6, 20.0, 9.0, 8, 2, 0.033, 0.15, true], [1.6, 55.0, 17.0, 5, 1, 0.07, 0.17, false]]
	if quality == "low": rings = [[0.42, 8.0, 0.0, 10, 2, 0.04, 0.15, false]]    # the near ring alone, fading out by 8 m
	for ring in rings:
		var m := _mat("res://shaders/foliage/grass.gdshader")
		m.set_shader_parameter("target_density", 1.0 / (ring[0] * ring[0]))
		if not ring[7]: m.set_shader_parameter("near_full", 1000.0)
		m.set_shader_parameter("trails", ring[1] < 10.0)
		m.set_shader_parameter("max_dist", 20.0 if ring[7] else ring[1])
		m.set_shader_parameter("clump_spread", ring[0] * 0.75)
		m.set_shader_parameter("blade_width", ring[5])
		m.set_shader_parameter("blade_height", ring[6])
		_add_field(m, _blade_mesh(ring[3], 31 + ring[3], ring[4]), ring[0], ring[1], ring[2], Vector4(1, 0, 0, 0))

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
	var f := ValleyGrass.field(mat, spacing, radius, mesh, inner, LAYER_FIELDS)
	add_child(f)
	f.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # it jumps with the camera, a cell at a time
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

# --- water (water.ts): ribbons per reach (reflections traced in the shader), falls sheet + mist ---------------------
const WATER_PIECE := 8          # points of a reach in one piece of its surface (about 25 m)

func _water() -> void:
	var falls: Dictionary = data.d.river.falls
	var foam := Vector2(falls.bottom[0], falls.bottom[2])
	for r in data.d.river.reaches:
		_water_ribbon(r.points, 3.5, 0.42 if r.id == "upper" else 0.32, foam)
	_waterfall(falls)

## In short pieces: a piece out of view isn't drawn, and while no water is, the screen isn't copied for it.
func _water_ribbon(pts: Array, margin: float, speed: float, foam: Vector2) -> void:
	var mat := _mat("res://shaders/vh/water.gdshader")
	mat.set_shader_parameter("field_tex", data.field_tex)
	mat.set_shader_parameter("map_rect", data.field_rect)
	mat.set_shader_parameter("t_normal", VHTex.get_tex("water_normal"))
	mat.set_shader_parameter("foam_center", foam)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 0
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
			rows += 1
		prev = row
		if rows >= WATER_PIECE or (i == pts.size() - 1 and rows > 0):
			var mi := _mesh(st.commit(), mat, false, LAYER_WATER)
			mi.sorting_offset = 2.0
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			rows = 0

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

# --- the old game layer (-- --game): a spot at each building's door, the named cast ---------------------------------
## Each building's role and name come from world.json's sites; this says which side its door is on (the side its
## street runs, -1: north, 1: south) and the name the goals list uses for it.
const DOORS := {"DV-01": -1, "DV-02": -1, "DV-03": 1, "DV-04": -1, "DV-05": -1, "DV-06": 1, "DV-07": 1, "DV-08": -1,
	"DV-09": 1, "DV-10": 1, "DV-19": 1, "DV-22": -1, "DV-23": 1}
const PLACE_NAMES := {"DV-05": "Housing Court"}
const DOOR_RADIUS := 4.0
## Where each of the cast stands, beside their door or on the square (x, z); those without a place here (Priya's
## boathouse, Bo's jetty, Ingrid's bakery: not built in the valley) stay out until it is.
const POSTS := {"harbourmaster": ["DV-01", 3.0], "kofi": ["DV-03", 3.5], "mei": ["DV-04", 3.0], "elias": ["DV-19", 3.0], "arthur": ["DV-02", 3.5],
	"dario": ["DV-10", 3.0], "sam": [-34.0, -8.0], "yusuf": [-18.0, -7.0]}
const OUTFITS := {"harbourmaster": ["Suit_Female", {"top": "2f7c7a"}], "kofi": ["Worker_Male", {"top": "e07a3a", "top2": "f2c14e"}],
	"mei": ["Chef_Female", {"hair": "8a8a8a"}], "elias": ["OldClassy_Male", {"top": "7a6a4f", "hair": "d8d8d8"}],
	"arthur": ["Suit_Male", {"top": "eaf0f4"}], "sam": ["Casual2_Male", {"top": "e9b23c"}],
	"dario": ["Suit_Male", {"top": "f4ead8"}], "yusuf": ["Chef_Male", {"top": "6b4a32"}]}
var cast_people := {}            # cast id -> Person
var _door_of := {}               # building id -> [door position (Vector2), its facing (Vector2)]

func _game() -> void:
	_doors()
	if _on("cast"): _cast()

func _doors() -> void:
	var raw := {}
	for r in data.d.sites: raw[str(r.id)] = r
	for id in town:
		if not DOORS.has(id): continue
		var r: Dictionary = raw.get(str(id).to_lower().replace("-", ""), {})
		if r.is_empty(): continue
		var rect: Rect2 = town[id].rect
		var side: int = DOORS[id]
		var face := Vector2(0, side)
		var at := Vector2(rect.get_center().x, (rect.end.y if side > 0 else rect.position.y) + side * 1.8)
		var spot := SpotScript.new()
		spot.radius = DOOR_RADIUS
		add_child(spot)
		spot.setup({"id": id, "name": PLACE_NAMES.get(id, str(r.name)), "role": str(r.role), "verb": "Enter"}, Vector3(at.x, height_at(at.x, at.y), at.y))
		spot.face = face
		spot.frame = rect.size * 0.5
		spot.center2 = rect.get_center()
		sites.append(spot)
		_door_of[id] = [at, face]

func _cast() -> void:
	var i := 0
	for id in POSTS:
		var post: Array = POSTS[id]
		var q := Vector2(post[0], post[1]) if post[0] is float else Vector2.INF
		var face := Vector2(0, 1)
		if post[0] is String:
			if not _door_of.has(post[0]): continue
			q = (_door_of[post[0]][0] as Vector2) + Vector2(float(post[1]), 0.0)
			face = _door_of[post[0]][1]
		var o: Array = OUTFITS[id]
		var outfit_look: Dictionary = (o[1] as Dictionary).duplicate()
		outfit_look.merge({"skin": PersonScript.SKINS[(i * 3 + 1) % PersonScript.SKINS.size()], "hair": PersonScript.HAIRS[i % 5]}, false)
		var person: Node3D = PersonScript.new()
		add_child(person)
		person.setup(o[0], outfit_look)
		var at := Vector3(q.x, height_at(q.x, q.y), q.y)
		person.position = at
		person.rotation.y = atan2(face.x, face.y)
		cast_people[id] = person
		var spot := SpotScript.new()
		add_child(spot)
		spot.setup({"id": id, "name": CastScript.PEOPLE[id].name, "role": "talk", "verb": "Talk to"}, at)
		spot.set_meta("person", person)
		i += 1

## They turn their heads to the player when near, and keep breathing.
func _update_cast(delta: float) -> void:
	if player == null: return
	for id in cast_people:
		var person: Node3D = cast_people[id]
		var to := player.global_position - person.position
		var yaw := wrapf(atan2(to.x, to.z) - person.rotation.y, -PI, PI)
		person.look_target = Vector2(clampf(yaw, -1.1, 1.1), 0.0) if to.length() < 7.0 else Vector2.ZERO
		person.step(0.0, delta)

# --- the Market Hall's stall, and the plates on screen -------------------------------------------------------------------
func _market() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	energy_plate = EnergyPlate.new()
	ui.add_child(energy_plate)
	client = TownClient.new()
	add_child(client)
	energy_plate.listen(client)
	link_notice = LinkNotice.new()
	link_notice.client = client
	ui.add_child(link_notice)
	stall = MarketStall.new()
	stall.position = STALL_AT
	stall.player = player
	stall.client = client
	stall.paint = _town_materials
	stall.route_in.assign(STREET_ROUTE)
	stall.route_out.assign(STREET_ROUTE.duplicate())
	stall.route_out.reverse()
	add_child(stall)
	stall.setup(ui)
	food_counter = FoodCounter.new()
	food_counter.position = FOOD_COUNTER_AT
	food_counter.player = player
	food_counter.client = client
	food_counter.paint = _town_materials
	add_child(food_counter)
	food_counter.setup(ui)
	_furniture()
	sound = Sound.new()
	sound.world = self
	add_child(sound)
	director = Director.new()
	director.rig = rig
	add_child(director)
	kiosks = Kiosks.new()
	kiosks.world = self
	kiosks.paint = _town_materials
	kiosks.named = {Dhaniverse.EXCHANGE: "Exchange", Dhaniverse.SPICE: "Spice Merchant"}
	add_child(kiosks)
	kiosks.setup()
	var interiors: Node3D = (load("res://assets/market/interiors.glb") as PackedScene).instantiate()
	add_child(interiors)
	_town_materials(interiors)
	for mi in interiors.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).visibility_range_end = 60.0
	people = TownPeople.new()
	people.player = player
	add_child(people)
	keeper = Harbourmaster.new()
	keeper.player = player
	keeper.height_at = height_at
	add_child(keeper)
	keeper.setup(ui)
	# dev: what each part of the market costs to draw (--off=people,kiosks,counters,interiors); left built, only not drawn
	var counters: Array = [stall, food_counter]
	counters.append_array(furniture)
	for part in [["people", [people, keeper]], ["kiosks", [kiosks]], ["counters", counters], ["interiors", [interiors]]]:
		if not _on(part[0]):
			for n in part[1]:
				if n is Node3D: (n as Node3D).visible = false
				else:
					(n as Node).process_mode = Node.PROCESS_MODE_DISABLED     # it shows its people itself, every frame
					for c in (n as Node).get_children(): if c is Node3D: (c as Node3D).visible = false
	cinema = Cinema.new()
	stall.cinema = cinema
	keeper.cinema = cinema
	opening = Opening.new()
	opening.world = self
	opening.player = player
	opening.client = client
	opening.keeper = keeper
	opening.cinema = cinema
	opening.director = director
	opening.sound = sound
	opening.paint = _town_materials
	opening.plates = [energy_plate]
	opening.keep = func(key: String, value): if not OS.get_cmdline_user_args().has("--arrive"): _save_setting(key, value)
	add_child(opening)
	opening.setup(ui)
	presence = Presence.new()
	presence.client = client
	presence.player = player
	presence.tags = ui
	add_child(presence)
	morning_paper = MorningPaper.new()      # the moments that take the screen, over everything else
	morning_paper.client = client
	ui.add_child(morning_paper)
	blast = MilestoneBlast.new()
	blast.wait_for = func(): return director.busy or moments.running or any_sheet_open()
	blast.client = client
	ui.add_child(blast)
	phone = Phone.new()
	phone.client = client
	ui.add_child(phone)
	mentor = MentorChat.new()
	mentor.client = client
	ui.add_child(mentor)
	hud = GameHud.new()
	hud.client = client
	hud.phone = phone
	hud.mentor = mentor
	hud.world = self
	ui.add_child(hud)
	opening.plates.append(hud)
	opening.plates.append(Island.join(ui, self, hud))    # top centre: the day's clock, and each moment as it happens
	settings = SettingsPanel.new()
	settings.world = self
	settings.cinema = cinema
	ui.add_child(settings)
	Screens.up = func(): return sheet_up() or typing() or (title != null and title.is_up)
	Screens.busy = func(): return any_sheet_open() or Screens.holding() or opening.playing or director.busy
	pause = PauseMenu.new()     # Esc in the town: Resume, Settings, Controls, Title, Quit
	pause.world = self
	pause.cinema = cinema
	pause.settings = settings
	ui.add_child(pause)
	var rehearsal := TestPanel.new()     # F1, on a rehearsal server only
	rehearsal.world = self
	rehearsal.client = client
	add_child(rehearsal)
	if TitleScreen.wanted():
		title = TitleScreen.new()
		title.world = self
		title.client = client
		title.cinema = cinema
		title.director = director
		title.opening = opening
		title.settings = settings
		title.bar = hud
		ui.add_child(title)
	ui.add_child(cinema)              # over everything else
	moments = Moments.new()
	moments.world = self
	moments.client = client
	moments.player = player
	moments.director = director
	moments.cinema = cinema
	moments.sound = sound
	add_child(moments)
	dhaniverse = Dhaniverse.new()
	dhaniverse.world = self
	dhaniverse.client = client
	dhaniverse.player = player
	dhaniverse.cinema = cinema
	dhaniverse.sound = sound
	dhaniverse.keeper = keeper
	dhaniverse.hud = hud
	add_child(dhaniverse)
	dhaniverse.setup(ui, kiosks)
	energy_plate.pass_waiting = func(): return dhaniverse.desk.waiting
	pass_gate = TownPassGate.new()     # the Town Pass, in the film: at the gangway, at the town hall's desk and from the phone
	pass_gate.client = client
	pass_gate.desk = dhaniverse.desk
	ui.add_child(pass_gate)
	opening.pass_gate = pass_gate
	dhaniverse.desk.open_gate = pass_gate.open
	loot = LootCrate.new()     # the urgent crate a paid meal drops, for anyone to reach first
	loot.client = client
	loot.world = self
	loot.things = dhaniverse.things
	loot.people = people
	add_child(loot)
	dhaniverse.guide.loot = loot
	quest_crate = QuestCrate.new()     # ux09: the crate a quest done drops at your feet
	quest_crate.client = client
	quest_crate.world = self
	quest_crate.things = dhaniverse.things
	quest_crate.sound = sound
	add_child(quest_crate)
	town_map = TownMap.new()     # ux08: M, the whole town and its quests
	town_map.world = self
	town_map.client = client
	ui.add_child(town_map)
	var quests_page: PhoneQuests = phone.page("quests")
	quests_page.guide = dhaniverse.guide
	quests_page.loot = loot
	phone.town_pass = pass_gate.open
	_say_who()

## The bank's counter and the room in the Homes' courtyard, standing where they always have: nothing to do at them now.
## Models: tools/blender/build_bank.py and build_home.py.
func _furniture() -> void:
	for f in [["res://assets/market/bank.glb", COUNTER_AT], ["res://assets/market/home.glb", Vector3(HOME_AT.x, height_at(HOME_AT.x, HOME_AT.y), HOME_AT.y)]]:
		var model: Node3D = (load(f[0]) as PackedScene).instantiate()
		add_child(model)
		_town_materials(model)
		model.position = f[1]
		model.rotation.y = PI         # the counter's front looks towards the bank's door, the room's door to the tree
		furniture.append(model)

## Who this is: from the command line, or as saved. No one yet: the ferry, connected with no name. Someone who hasn't read the
## letter goes back to it. -- --arrive plays the first time over without saving the name.
func _say_who() -> void:
	var trial := OS.get_cmdline_user_args().has("--arrive")
	var secret := str(_setting("player_secret", ""))
	if secret == "":
		secret = Crypto.new().generate_random_bytes(16).hex_encode()
		_save_setting("player_secret", secret)
	var who := client.player if client.player != "" else ("" if trial else str(_setting("player_name", "")))
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--snap=") or a.begins_with("--shots=")): return   # a capture asks nothing
	if who == "":
		client.secret = secret
		client.connect_nameless()
		if title:
			await title.finished
			opening.play_from_port(title.mode_before)
		else:
			opening.play()
		return
	client.start(who, secret)
	await client.synced
	if title and title.is_up: await title.finished
	if TownPassGate.wanted(client): await opening.hold_for_pass()     # signed up but never stamped: finish that first
	if not opening.has_read() and not opening.playing: opening.resume()

func _in_a_room(p: Vector3) -> bool:
	return room_at(p) >= 0

## Which of ROOMS a point is in, or -1.
func room_at(p: Vector3) -> int:
	var rooms := all_rooms()
	for i in rooms.size():
		if AABB(rooms[i][0], rooms[i][1] - rooms[i][0]).has_point(p): return i
	return -1

## What a foot lands on here, for how it sounds.
func surface_at(p: Vector3) -> String:
	if Vector2(p.x, p.z).distance_to(Vector2(-114.0, 49.0)) < 11.0 and p.y > -0.7: return "wood"     # the jetty
	if p.x < -123.0: return "wood"     # the ferry
	var room := room_at(p)
	if room >= 0: return "wood" if room in [2, 4] or room >= ROOMS.size() else "stone"
	return "stone" if data.pave_dist(Vector2(p.x, p.z)) < 0.8 else "grass"

## Is a paper, the phone or anything like them up on screen?
func any_sheet_open() -> bool:
	return phone.is_open or sheet_up()

## A screen that takes the whole of you: a menu, a paper, the Town Pass, the mentor, the board in focus. (The phone is in your hand:
## you can walk.)
func sheet_up() -> bool:
	return (settings and settings.is_open) or (pause and pause.is_open) or mentor.is_open or morning_paper._sheet.visible or opening.ticket._sheet.visible \
		or opening.letter._sheet.visible or food_counter.food_menu.is_open or BoardSheet.any_open() or (pass_gate and pass_gate.is_open()) \
		or (dhaniverse != null and (dhaniverse.board.is_open or dhaniverse.spice.sheet.is_open)) or (town_map and town_map.is_open)

## Someone is writing in a field (the phone's withdraw form, the mentor's question): the keys are letters, not walking.
func typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit

func _pace(delta: float) -> void:
	if not steady_frames or _pace_t > PACE_AFTER + PACE_OVER: return
	_pace_t += delta
	if _pace_t < PACE_AFTER: return
	_pace_n += 1
	_pace_sum += delta
	if _pace_t < PACE_AFTER + PACE_OVER: return
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz < 30.0: hz = 60.0
	var fps := _pace_n / maxf(_pace_sum, 0.001)
	Engine.max_fps = 0 if fps >= hz * PACE_HOLDS else int(round(hz * 0.5))
	print("frames: %.1f a second on a %.0f Hz screen: %s" % [fps, hz, "free" if Engine.max_fps == 0 else "held at %d" % Engine.max_fps])
	_pace_t = INF                   # decided

## What stands inside the town's rooms and halls: no one sees it from further than this, so it isn't drawn from further than this.
func _near_only() -> void:
	if not _on("market"): return
	var near: Array = [[stall, ROOM_THINGS_SEEN], [food_counter, ROOM_THINGS_SEEN], [people, PEOPLE_SEEN], [kiosks, KIOSKS_SEEN]]
	for f in furniture: near.append([f, ROOM_THINGS_SEEN])
	for what in near:
		for mi in (what[0] as Node).find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).visibility_range_end <= 0.0: (mi as MeshInstance3D).visibility_range_end = what[1]

## A building far from the camera can't throw a shadow as far as the shadow map reaches: it needn't be drawn into it. Same picture, fewer draws.
func _far_shadows(delta: float) -> void:
	if sun == null or not sun.shadow_enabled: return     # low: there is no shadow map to leave them out of
	_shadow_look_in -= delta
	if _shadow_look_in > 0.0: return
	_shadow_look_in = SHADOW_LOOK_EVERY
	var eye := get_viewport().get_camera_3d()
	if eye == null: return
	var p := Vector2(eye.global_position.x, eye.global_position.z)
	for b in _building_nodes:
		var r: Rect2 = b[1]
		var near := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var casts := near.distance_to(p) < SHADOW_WITHIN
		if b.size() > 2 and b[2] == casts: continue
		if b.size() > 2: b[2] = casts
		else: b.append(casts)
		for mi in (b[0] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.get_aabb().get_longest_axis_size() >= DETAIL_BIG:      # the small parts never cast
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in _prop_nodes:
		if n[0] is MultiMeshInstance3D and n.size() == 2:
			n.append((n[0] as MultiMeshInstance3D).cast_shadow)      # what it does when close
		if n.size() < 3 or n[2] == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var far: bool = Vector2(n[1].x, n[1].z).distance_to(p) > PROP_SHADOW_WITHIN
		(n[0] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else n[2]

## In a room, leave out what its windows can't reach. Back outdoors, it all returns. Done once at each door.
func _cull_for_room(room: int) -> void:
	if room == _culled_for: return
	_culled_for = room
	var p := Vector2(player.global_position.x, player.global_position.z)
	var sees: float = ROOM_SEES.get(room, ROOM_SEES_ELSE)
	for b in _building_nodes:
		var r: Rect2 = b[1]
		var near := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		(b[0] as Node3D).visible = room < 0 or near.distance_to(p) < sees
	for n in _prop_nodes: (n[0] as Node3D).visible = room < 0 or Vector2(n[1].x, n[1].z).distance_to(p) < ROOM_SEES_PROPS
	for n in _tree_nodes: (n[0] as Node3D).visible = room < 0 or Vector2(n[1].x, n[1].z).distance_to(p) < ROOM_SEES_TREES
	for i in range(1, fields.size()): (fields[i][0] as Node3D).visible = room < 0

## The rooms (ROOMS), as the town's shader and the camera read them.
func all_rooms() -> Array:
	if _rooms.is_empty(): _rooms = ROOMS.duplicate()
	return _rooms

# --- player --------------------------------------------------------------------------------------------------------------
func _player() -> void:
	player = PlayerScript.new()
	add_child(player)
	if quality == "low": _blob(Vector3.ZERO, 0.55, player)
	var sp := SPAWN
	player.global_position = Vector3(sp.x, height_at(sp.x, sp.y) + 0.5, sp.y)
	if not _on("hero"): player.avatar.visible = false
	rig = CameraRig.new()
	rig.target = player
	rig.floor_at = _camera_floor
	add_child(rig)
	rig.cam.far = 6000.0
	rig.cam.near = 0.1
	rig.set_mode(str(_setting("camera", "third")), true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="): rig.set_mode(a.trim_prefix("--view="), true)
	rig.mode_changed.connect(func(m): if not rig.indoors: _save_setting("camera", m))
	player.rig = rig

## The lowest a camera may sink to at a point: the ground, or the water surface over the river.
func _camera_floor(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := height_at(x, z)
	return maxf(h, data.water_z(p)) if data.water_sd(p) < 1.0 else h

func _process(delta: float) -> void:
	_pace(delta)
	_far_shadows(delta)
	if rig: rig.idle_drift = cinematic_on
	if rig and phone: rig.hold_cursor(settings.is_open or any_sheet_open())     # the mouse is free for as long as anything's held up
	if hud and energy_plate:     # a menu or a paper has the whole screen: none of the HUD under it (the board in focus dims it instead)
		var bare := sheet_up() and not (dhaniverse != null and dhaniverse.board.is_open)
		hud.visible = not bare
		energy_plate.visible = not bare
	var eye := get_viewport().get_camera_3d()
	if eye:
		RenderingServer.global_shader_parameter_set("vh_eye", eye.global_position)
	_update_time_of_day(delta)
	if sun: RenderingServer.global_shader_parameter_set("light_direction", sun.global_transform.basis.z.normalized())
	if rig:
		var c: Vector3 = rig.global_position
		for f in fields:
			f[0].global_position = Vector3(snappedf(c.x, f[1]), 0.0, snappedf(c.z, f[1]))
	if player:
		var q := Vector2(clampf(player.global_position.x, MAP.position.x + 4.0, MAP.end.x - 4.0), clampf(player.global_position.z, MAP.position.y + 4.0, MAP.end.y - 4.0))
		if q != Vector2(player.global_position.x, player.global_position.z):
			player.global_position = Vector3(q.x, player.global_position.y, q.y)
			player.reset_physics_interpolation()
		RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
		rig.set_indoors(_in_a_room(player.global_position))
		_cull_for_room(room_at(player.global_position))
	_update_cast(delta)

# --- grade + intro -----------------------------------------------------------------------------------------------------------
func _post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.material = _mat("res://shaders/valley/grade.gdshader")
	if quality == "low":
		# low has no bloom or light rays, the only reads of the screen's mips: without them the engine stops building a mip chain of the
		# whole frame every frame (on the web: a dozen texture reallocations and a stall on the GPU each frame). Same picture.
		var sh := Shader.new()
		sh.code = (post.material.shader as Shader).code.replace("filter_linear_mipmap", "filter_linear")
		post.material.shader = sh
	layer.add_child(post)

func _snap(path: String) -> void:
	player.frozen = true          # a capture window takes focus: keys typed elsewhere must not walk him off
	if ui: ui.visible = OS.get_cmdline_user_args().has("--hud")
	rig.set_process_input(false)
	rig.set_process_unhandled_input(false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):    # dev: the height of what stands along a line x, z0..z1 (kerbs, steps, walls)
			var v := a.trim_prefix("--probe=").split_floats(",")
			await get_tree().physics_frame
			var line := ""
			var pz := v[1]
			while pz <= v[2]:
				var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(v[0], 30, pz), Vector3(v[0], -30, pz)))
				line += "%.1f:%.2f " % [pz, hit.position.y if hit else -99.0]
				pz += 0.5
			print("probe x=", v[0], " ", line)
		if a.begins_with("--scan="):     # dev: sweep a body along z from z0 to z1 at each x: how far it gets (finds the doors)
			var v := a.trim_prefix("--scan=").split_floats(",")
			await get_tree().physics_frame
			var cap := CapsuleShape3D.new()
			cap.radius = 0.35
			cap.height = 1.0
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			var line := ""
			var sx := v[0]
			while sx <= v[1]:
				q.transform = Transform3D(Basis(), Vector3(sx, float(v[4]), v[2]))
				q.motion = Vector3(0, 0, v[3] - v[2])
				var r := get_world_3d().direct_space_state.cast_motion(q)
				line += "%.0f:%.1f " % [sx, v[2] + (v[3] - v[2]) * r[0]]
				sx += 1.0
			print("scan ", line)
		if a.begins_with("--stand="):    # dev: the player stands here, as if walked there (the room culling sees it)
			var v := a.trim_prefix("--stand=").split_floats(",")
			player.global_position = Vector3(v[0], v[1], v[2])
		if a.begins_with("--map="):      # dev: what's solid at chest height, x0,x1,z0,z1,y, a character a metre, x across: # solid
			var v := a.trim_prefix("--map=").split_floats(",")
			await get_tree().physics_frame
			var ball := SphereShape3D.new()
			ball.radius = 0.3
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = ball
			var zz := v[2]
			while zz <= v[3]:
				var row := ""
				var xx := v[0]
				while xx <= v[1]:
					q.transform = Transform3D(Basis(), Vector3(xx, v[4], zz))
					row += "#" if get_world_3d().direct_space_state.intersect_shape(q, 1).size() > 0 else "."
					xx += 1.0
				print("map z=%6.1f %s" % [zz, row])
				zz += 1.0
		if a.begins_with("--walk="):     # dev: start at sx,sz and walk straight at tx,tz; says how far it got (doors, stairs)
			var w := a.trim_prefix("--walk=").split_floats(",")
			player.global_position = Vector3(w[0], height_at(w[0], w[1]) + 0.4, w[1])
			player.dev_walk = Vector2(w[2], w[3])
		if a.begins_with("--cam="):      # dev: a fixed camera, eye x,y,z then target x,y,z
			var v := a.trim_prefix("--cam=").split_floats(",")
			var cam := Camera3D.new()
			cam.far = 3000.0
			add_child(cam)
			cam.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
			cam.make_current()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var settle := 8.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--settle="): settle = float(a.trim_prefix("--settle="))
	await get_tree().create_timer(settle).timeout
	var g := 0.0
	var best := INF
	for i in 60:
		await get_tree().process_frame
		g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		best = minf(best, RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if player.dev_walk != null: print("walk: ended at ", player.global_position.snapped(Vector3.ONE * 0.1), " wanting ", player.dev_walk)
	print("snap: %d fps, gpu %.2f ms (best %.2f), draws %d, tris %d, time %s, view %s" % [Engine.get_frames_per_second(), g / 60.0, best,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), mode, rig.mode])
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

## The player's brightness and colour, on the real picture.
func set_picture(brightness: float, colour: float) -> void:
	if world_env == null: return
	world_env.adjustment_enabled = true
	world_env.adjustment_brightness = brightness
	world_env.adjustment_saturation = colour

## Esc opens settings only when nothing else has the screen.
func settings_may_open() -> bool:
	if title and title.is_up: return false
	return not any_sheet_open() and not opening.playing and not director.busy
