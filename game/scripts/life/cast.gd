class_name Cast
## The named townsfolk of Tallyport (spec 3.5): where each one stands, what they look like, and a short line
## that fits the player's day. Lines are plain words any player can read; all of them live here, beside the
## sign table (scripts/ui/strings.gd), so localising is translation, not rewriting.

## post: the site role (or landmark) they keep to; look: outfit hints for the character builder
const PEOPLE := {
	"harbourmaster": {"name": "The harbourmaster", "post": "arrival", "look": {"age": "60s", "top": "teal cardigan", "build": "medium"}},
	"kofi": {"name": "Kofi", "post": "market", "look": {"age": "40s", "top": "orange apron", "build": "broad"}},
	"mei": {"name": "Mei", "post": "food", "look": {"age": "60s", "top": "red apron", "build": "small"}},
	"elias": {"name": "Elias", "post": "library", "look": {"age": "70s", "top": "tweed jacket", "build": "tall"}},
	"priya": {"name": "Priya", "post": "boathouse", "look": {"age": "30s", "top": "work overalls", "build": "medium"}},
	"arthur": {"name": "Arthur", "post": "bank", "look": {"age": "40s", "top": "waistcoat", "build": "slim"}},
	"bo": {"name": "Bo", "post": "jetty", "look": {"age": "70s", "top": "fisherman's jumper", "build": "stocky"}},
	"sam": {"name": "Sam", "post": "square", "look": {"age": "20s", "top": "denim jacket", "build": "slim"}},
	"dario": {"name": "Dario", "post": "pawn", "look": {"age": "50s", "top": "linen suit", "build": "medium"}},
	"yusuf": {"name": "Yusuf", "post": "fig", "look": {"age": "30s", "top": "barista apron", "build": "medium"}},
	"ingrid": {"name": "Ingrid", "post": "bakery", "look": {"age": "60s", "top": "flour apron", "build": "medium"}},
}

## s: what the server has said about the player, as {"milestones": {first: true}} (the firsts they've earned).
static func line(id: String, s: Dictionary) -> String:
	var ms: Dictionary = s.get("milestones", {})
	match id:
		"harbourmaster":
			return "Thirty years ago I came off the evening ferry with one suitcase. Look at you, settling in."
		"kofi":
			return "Customers come in waves. Hand each one what they ask for, quick as you can, and see how many you get through."
		"mei":
			if not ms.has("first_meal"): return "Sit, eat. A hot meal does more for you than three snacks. Nobody here goes hungry."
			return "You look rested. Good. Come back when the rain starts; this place fills up."
		"elias":
			return "Every pair of notches on the Steps was closed but one. Forty years I've asked whose it was."
		"priya":
			return "I fix radios, bicycles, the ferry's engine. One day I'll have my own workshop, and I won't owe anyone for it."
		"arthur":
			return "Did you know the town's first bank was a chest at the top of the Steps? We still have it."
		"bo":
			return "Hear that bell? Rang it for every ferry for fifty years. Rang it for you, too."
		"sam":
			return "Same ferry as you! I'm going to be rich by the next season. Probably."
		"dario":
			return "Prices up again? Wait a day or two. They come down as often as they go up."
		"yusuf":
			return "Coffee? Mei's thali at the Common Table is worth the walk, and Kofi always needs hands at his stall."
		"ingrid":
			return "My stall's still shuttered. One day I'll bake again."
	return "Hello."
