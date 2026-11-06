# AppSettings — Autoload singleton. Single source of truth for wind/cloud shader globals.
extends Node

@export_group("Cloud Shadows")
@export var cloud_contrast: float = 3.845:
	set(v):
		cloud_contrast = v
		RenderingServer.global_shader_parameter_set("cloud_contrast", v)
@export var cloud_speed: float = -0.01:
	set(v):
		cloud_speed = v
		RenderingServer.global_shader_parameter_set("cloud_speed", v)
@export var cloud_scale: float = 0.002:
	set(v):
		cloud_scale = v
		RenderingServer.global_shader_parameter_set("cloud_scale", v)
@export var cloud_world_y: float = 20.0:
	set(v):
		cloud_world_y = v
		RenderingServer.global_shader_parameter_set("cloud_world_y", v)
@export var cloud_threshold: float = 0.0:
	set(v):
		cloud_threshold = v
		RenderingServer.global_shader_parameter_set("cloud_threshold", v)
@export var cloud_shadow_min: float = 0.2:
	set(v):
		cloud_shadow_min = v
		RenderingServer.global_shader_parameter_set("cloud_shadow_min", v)
@export var cloud_diverge_angle: float = 10.0:
	set(v):
		cloud_diverge_angle = v
		RenderingServer.global_shader_parameter_set("cloud_diverge_angle", v)
@export var cloud_direction: Vector2 = Vector2(0, 1):
	set(v):
		cloud_direction = v
		RenderingServer.global_shader_parameter_set("cloud_direction", v)

@export_group("Wind")
@export var wind_direction: Vector3 = Vector3(0, 0, 1):
	set(v):
		wind_direction = v
		RenderingServer.global_shader_parameter_set("wind_direction", v)
@export var wind_speed: float = 0.05:
	set(v):
		wind_speed = v
		RenderingServer.global_shader_parameter_set("wind_speed", v)
@export var wind_strength: float = 0.35:
	set(v):
		wind_strength = v
		RenderingServer.global_shader_parameter_set("wind_strength", v)

func _enter_tree():
	# Force all setters so RenderingServer values match defaults on first frame
	cloud_contrast = cloud_contrast
	cloud_speed = cloud_speed
	cloud_scale = cloud_scale
	cloud_world_y = cloud_world_y
	cloud_threshold = cloud_threshold
	cloud_shadow_min = cloud_shadow_min
	cloud_diverge_angle = cloud_diverge_angle
	cloud_direction = cloud_direction
	wind_direction = wind_direction
	wind_speed = wind_speed
	wind_strength = wind_strength
