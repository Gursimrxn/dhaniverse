extends TestCase
## A person's body: which clip it plays at a speed (and how fast, so its feet don't slide), and which of its
## surfaces is skin, hair or which piece of clothing (so each person can be recoloured).

const Person := preload("res://scripts/life/person.gd")

func test_standing_still_is_idle() -> void:
	eq(Person.gait("W", 0.0)[0], "Idle", "clip at rest")

func test_walking_plays_walk_at_the_speed_travelled() -> void:
	var g: Array = Person.gait("W", 1.3)
	eq(g[0], "Walk", "clip at 1.3 m/s")
	near(float(g[1]) * Person.GAIT.W.Walk, 1.3, 0.001, "feet speed = travel speed")

func test_jogging_plays_run_at_the_speed_travelled() -> void:
	var g: Array = Person.gait("M", 3.4)
	eq(g[0], "Run", "clip at 3.4 m/s")
	near(float(g[1]) * Person.GAIT.M.Run, 3.4, 0.001, "feet speed = travel speed")

## role_for(mesh, material, k): k = how many cloth (non-skin) surfaces of that mesh came before it
func test_surfaces_get_their_roles() -> void:
	eq(Person.role_for("Casual_Body", "Skin", 0), "skin", "skin on the body")
	eq(Person.role_for("Casual_Head", "Hair_Brown", 0), "hair", "hair")
	eq(Person.role_for("Worker_Head", "Eyebrows", 0), "hair", "eyebrows go with the hair")
	eq(Person.role_for("Casual_Head", "Eye", 2), "keep", "eyes keep their colour")
	eq(Person.role_for("Worker_Head", "Worker_Yellow", 1), "hat", "a hard hat")
	eq(Person.role_for("Casual_Body", "White", 0), "top", "shirt")
	eq(Person.role_for("Suit_Body", "Grey", 1), "top2", "second colour on the body")
	eq(Person.role_for("Casual_Legs", "Orange", 0), "bottom", "trousers")
	eq(Person.role_for("Farmer_Pants", "LightBlue", 0), "bottom", "pants are legs too")
	eq(Person.role_for("Casual_Feet", "Grey", 0), "shoes", "shoes")
	eq(Person.role_for("Pistol", "Grey", 0), "hide", "props an outfit came with are hidden")

## the chubby characters (assets/characters/chibi, Quaternius UACP): their own gait and material names
func test_chibi_walks_and_runs_at_the_speed_travelled() -> void:
	var g: Array = Person.gait("C", 0.9)
	eq(g[0], "Walk", "chibi clip at 0.9 m/s")
	near(float(g[1]) * Person.GAIT.C.Walk, 0.9, 0.001, "feet speed = travel speed (walk)")
	var r: Array = Person.gait("C", 2.6)
	eq(r[0], "Run", "chibi clip at 2.6 m/s")
	near(float(r[1]) * Person.GAIT.C.Run, 2.6, 0.001, "feet speed = travel speed (run)")

func test_chibi_surfaces_get_their_roles() -> void:
	var want := {"Skin": "skin", "Face": "keep", "Hair": "hair", "Moustache": "hair", "Hat": "hat", "HatLightBrown": "hat",
		"Shirt": "top", "Clothes": "top", "Main": "top", "Jacket": "top", "Vest": "top2", "Band": "top2", "Scarf": "top2",
		"Pants": "bottom", "DarkClothes": "bottom", "Belt": "shoes", "Black": "keep"}
	for m in want: eq(Person.role_chibi(m), want[m], m)
