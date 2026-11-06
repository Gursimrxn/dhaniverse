extends Node3D
## Seasons and weather (spec 6.2, 6.3), the same for everyone: a season lasts 7 real days, counted from
## 2026-01-01 UTC on the real clock; the weather changes on the hour, picked from a seeded schedule by the
## season's chances, and never touches the game. What it does to the world:
##   - the leaves' season (world.set_season, fol_season);
##   - fol_weather (x overcast, y wet, z snow, w mist), which the painted shaders read: overcast dims the sun and
##     fills the shade, wet darkens the ground, snow settles on what faces up, mist thickens the haze;
##   - rain and snow falling round the camera.
## The test panel can set the season and the weather by hand (cycle_season, cycle_weather).

const SEASONS := ["spring", "summer", "autumn", "winter"]
const LEAVES := {"spring": 0.14, "summer": 0.35, "autumn": 0.62, "winter": 0.97}
const WEATHERS := ["clear", "overcast", "rain", "mist", "snow"]
const CHANCE := {
	"spring": {"clear": 0.62, "overcast": 0.16, "rain": 0.14, "mist": 0.08},
	"summer": {"clear": 0.78, "overcast": 0.1, "rain": 0.1, "mist": 0.02},
	"autumn": {"clear": 0.5, "overcast": 0.22, "rain": 0.18, "mist": 0.1},
	"winter": {"clear": 0.45, "overcast": 0.2, "snow": 0.25, "mist": 0.1},
}
const LOOK := {
	"clear": Vector4(0, 0, 0, 0), "overcast": Vector4(0.4, 0, 0, 0.05), "rain": Vector4(0.55, 1, 0, 0.15),
	"mist": Vector4(0.3, 0.15, 0, 0.55), "snow": Vector4(0.35, 0, 1, 0.12),
}
const EPOCH := 1793232000.0      # 2026-10-29 00:00 UTC: spring this week, summer for the 5-11 Nov hackathon
const WEEK := 7.0 * 86400.0
const EASE := 0.25               # how quickly the world turns to new weather, per second

var world: Node
var season := ""
var weather := ""
var season_override := ""
var weather_override := ""
var _cur := Vector4.ZERO
var _rain: GPUParticles3D
var _snow: GPUParticles3D

static func season_at(t: float) -> String:
	return SEASONS[posmod(int(floor((t - EPOCH) / WEEK)), 4)]

static func weather_at(t: float) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = int(floor(t / 3600.0)) * 7919 + 13
	var x := r.randf()
	var ch: Dictionary = CHANCE[season_at(t)]
	for k in ch:
		x -= float(ch[k])
		if x <= 0.0: return k
	return ch.keys()[-1]

func _ready() -> void:
	_rain = _particles(5000, 1.2, QuadMesh.new(), Vector2(0.025, 0.7), Color(0.75, 0.82, 0.92, 0.45), Vector3(0, -20, 0), 0.0)
	_snow = _particles(3500, 11.0, QuadMesh.new(), Vector2(0.2, 0.2), Color(1, 1, 1, 0.95), Vector3(0, -1.3, 0), 0.6)
	_update(true)

func _particles(amount: int, life: float, mesh: QuadMesh, size: Vector2, col: Color, vel: Vector3, wander: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(30, 1, 30)
	m.direction = vel.normalized()
	m.spread = 4.0
	m.initial_velocity_min = vel.length() * 0.85
	m.initial_velocity_max = vel.length() * 1.1
	m.gravity = Vector3.ZERO
	if wander > 0.0:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = wander
		m.turbulence_noise_scale = 4.0
	p.process_material = m
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if size.y > size.x * 2.0 else BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	return p

func _process(delta: float) -> void:
	_update(false, delta)

func _update(instant: bool, delta := 0.0) -> void:
	var t := Time.get_unix_time_from_system()
	var s := season_override if season_override != "" else season_at(t)
	var w := weather_override if weather_override != "" else weather_at(t)
	if s != season:
		season = s
		if world and world.has_method("set_season"): world.set_season(LEAVES[s])
	weather = w
	var goal: Vector4 = LOOK[w]
	_cur = goal if instant else _cur.lerp(goal, 1.0 - exp(-EASE * delta))
	RenderingServer.global_shader_parameter_set("fol_weather", _cur)
	_rain.emitting = w == "rain"
	_rain.amount_ratio = clampf(_cur.y, 0.05, 1.0)
	_snow.emitting = w == "snow"
	_snow.amount_ratio = clampf(_cur.z, 0.05, 1.0)
	# fall round what the camera looks at, from above it
	var cam := get_viewport().get_camera_3d()
	if cam:
		var focus: Vector3 = world.rig.position if world and world.rig else cam.global_position
		global_position = Vector3(focus.x, focus.y + 22.0, focus.z)

func cycle_season() -> void:
	season_override = SEASONS[(SEASONS.find(season) + 1) % 4]

func cycle_weather() -> void:
	weather_override = WEATHERS[(WEATHERS.find(weather) + 1) % WEATHERS.size()]
