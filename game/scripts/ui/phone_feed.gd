class_name PhoneFeed
extends PhonePage
## The town's feed: posts the server writes from what really happened, newest first (the snapshot's latest, then each FeedPost). A
## meal, a payout or a chest is never posted, and no post says what anyone paid or holds (PROTOCOL.md).

const KEEP := 40
const KIND_WORDS := {"first": "A first", "board": "The boards", "city": "The town", "season": "The season", "quest": "A quest", "call": "Price Call",
	"goal": "Town Goal", "draw": "The draw", "bounty": "Bounty Board"}

var _posts: Array[Dictionary] = []

func listen() -> void:
	client.event.connect(_on_event)
	client.synced.connect(_from_snapshot)

func _from_snapshot() -> void:
	_posts.clear()
	for p in client.feed: _posts.push_front(p)
	if is_visible_in_tree(): refresh()

func _on_event(e: Dictionary) -> void:
	if str(e.type) != "FeedPost": return
	_posts.push_front(e.duplicate())
	if _posts.size() > KEEP: _posts.pop_back()
	if is_visible_in_tree(): refresh()

func refresh() -> void:
	clear_page()
	add_theme_constant_override("separation", 8)
	add_child(heading("the feed"))
	if _posts.is_empty():
		add_child(words("Nothing yet. The town's news lands here as it happens.", 15, MUTED))
		return
	for post in _posts: add_child(_post_row(post))

func _post_row(post: Dictionary) -> Control:
	var r := row()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(caps("%s · day %d" % [KIND_WORDS.get(str(post.get("kind", "")), "The town"), int(post.get("day", 0))]))
	var text := words(str(post.text), 15)
	text.custom_minimum_size.x = WIDTH - 24.0
	column.add_child(text)
	r.add_child(column)
	return r
