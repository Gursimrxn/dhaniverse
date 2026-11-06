extends TestCase
## The material-name convention new GLBs use (tools/blender/dhaniverse_arch.py) and site.gd reads.

const Site := preload("res://scripts/world/site.gd")

func test_each_part_name_maps_to_its_part() -> void:
	var cases := {"wall": 0, "trim": 1, "frame": 2, "roof": 3, "wood": 4, "stone": 5, "metal": 6, "canvas": 7, "plant": 8, "light": 9}
	for name in cases: eq(Site.part_for("Quarter " + name + ".001"), cases[name], name)

func test_names_are_matched_case_insensitively() -> void:
	eq(Site.part_for("ROOF_slate"), Site.PART_ROOF, "ROOF_slate")

func test_glass_is_its_own_kind() -> void:
	eq(Site.part_for("window glass"), Site.PART_GLASS, "window glass")

func test_light_wins_over_the_surface_it_sits_on() -> void:
	# a lamp fixed to a wall glows: 'light' outranks 'wall' and 'metal'
	eq(Site.part_for("wall light metal"), Site.PART_LIGHT, "wall light metal")

func test_unknown_names_fall_back_to_colour_sorting() -> void:
	eq(Site.part_for("Material.003"), Site.PART_BY_COLOUR, "Material.003")
	eq(Site.part_for(""), Site.PART_BY_COLOUR, "empty")
