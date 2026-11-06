class_name PhoneFeed
extends PhonePage
## The town's feed: posts the server writes from what really happened, newest first (the snapshot's latest, then each FeedPost). Each has
## the town's reactions (city.emotes) with their counts; press one to add yours, once per post. A meal, a payout or a chest is never
## posted, and no post says what anyone paid or holds (PROTOCOL.md).

const KEEP := 40
const KIND_WORDS := {"first": "A first", "board": "The boards", "city": "The town", "season": "The season", "quest": "A quest", "call": "Price Call",
	"goal": "Town Goal", "draw": "The draw", "bounty": "Bounty Board"}
const EMOTE_WORDS := {"clap": "Clap", "laugh": "Ha", "wow": "Wow", "sad": "Aw"}

var _posts: Array[Dictionary] = []
var _mine := {}                    # post id -> true: reacted to from here

var _said := ""                    # why the last reaction didn't count

func listen() -> void:
	client.event.connect(_on_event)
	client.synced.connect(_from_snapshot)
	client.refused.connect(func(command: Dictionary, refusal: Dictionary):
		if command.get("type") != "React": return
		_said = Refusals.say(refusal, client.now_ms())
		if is_visible_in_tree(): refresh())

func _from_snapshot() -> void:
	_posts.clear()
	for p in client.feed: _posts.push_front(p)
	if is_visible_in_tree(): refresh()

func _on_event(e: Dictionary) -> void:
	match str(e.type):
		"FeedPost":
			var p := e.duplicate()
			p["reactions"] = {}
			_posts.push_front(p)
			if _posts.size() > KEEP: _posts.pop_back()
		"Reacted":
			for p in _posts:
				if int(p.get("id", -1)) == int(e.get("post", -2)):
					var r: Dictionary = p.get("reactions", {})
					r[str(e.emote)] = int(r.get(str(e.emote), 0)) + 1
					p["reactions"] = r
					if str(e.get("account", "")) == client.player: _mine[int(p.id)] = true
		_: return
	if is_visible_in_tree(): refresh()

func refresh() -> void:
	clear_page()
	add_theme_constant_override("separation", 8)
	if _said != "":
		add_child(words(_said, 13, WARN))
		_said = ""
	if _posts.is_empty():
		add_child(words("Nothing yet. The town's news lands here as it happens.", 16, MUTED))
		return
	for post in _posts: add_child(_post_row(post))

func _post_row(post: Dictionary) -> Control:
	var r := row()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.add_child(words("%s · day %d" % [KIND_WORDS.get(str(post.get("kind", "")), "The town"), int(post.get("day", 0))], 12, MUTED, false))
	var text := words(str(post.text), 15)
	text.custom_minimum_size.x = WIDTH - 24.0
	column.add_child(text)
	var bottom := HFlowContainer.new()
	bottom.add_theme_constant_override("h_separation", 5)
	var reactions: Dictionary = post.get("reactions", {})
	for emote in client.city.get("emotes", []):
		var n := int(reactions.get(emote, 0))
		var c := chip("%s%s" % [EMOTE_WORDS.get(emote, str(emote).capitalize()), (" %d" % n) if n > 0 else ""], _mine.has(int(post.get("id", -1))) and n > 0)
		c.pressed.connect(func(): client.send({"type": "React", "post": int(post.id), "emote": str(emote)}))
		bottom.add_child(c)
	column.add_child(bottom)
	r.add_child(column)
	return r
