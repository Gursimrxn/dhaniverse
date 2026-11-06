extends Node3D
## Something to walk up to that isn't a building: a person to talk to, the Ledger Wall, a stall. Standing near
## it shows the HUD's prompt (verb + name); pressing E opens its panel directly, without the glide into an
## interior (hud.gd, panel_only). It looks like a site to the HUD and the player (def, door, center2, floor_y).

var def := {}                    # {id, name, role, verb}
var door := Vector3.ZERO
var center2 := Vector2.ZERO
var floor_y := 0.0
var panel_only := true
var radius := 2.4
var face := Vector2(0, 1)        # a building's spot: which way its door looks and its half extents (the minimap draws them)
var frame := Vector2.ZERO

func setup(d: Dictionary, at: Vector3) -> void:
	def = d
	name = str(d.get("id", "spot"))
	position = at
	door = at
	center2 = Vector2(at.x, at.z)
	floor_y = at.y
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	area.add_child(cs)
	area.position.y = 1.0
	add_child(area)
	area.body_entered.connect(func(b): if b.has_method("near_site"): b.near_site(self))
	area.body_exited.connect(func(b): if b.has_method("left_site"): b.left_site(self))
