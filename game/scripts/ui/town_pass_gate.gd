class_name TownPassGate
extends Control
## The Town Pass, shown at the gangway: one pass for one real person, proven once with World ID, before a new passenger steps ashore.
## Someone who left before finishing it is asked again when they come back; once it's stamped it's never asked for again (the server
## keeps it). Asking goes through the town hall's desk (TownPassDesk.ask), which opens the pass page in the browser; this sheet waits
## for HumanVerified. Only on a town that can stamp one (TownClient.town_pass): elsewhere nobody is held at the gangway.

signal passed                    # stamped: on with the landing

var client: TownClient
var desk: TownPassDesk
var _sheet := PaperSheet.new(680.0)
var _status := PaperSheet.words("", Brand.FONT_BODY, 16, 600.0)
var _key_up := false             # E let go since it opened: the press that asks is a new one

## Should this player be held at the gangway?
static func wanted(c: TownClient) -> bool:
	return c.town_pass and not c.you.is_empty() and not bool(c.you.get("human", false))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = PaperSheet.ABOVE_THE_WORLD
	_sheet.card()
	add_child(_sheet)
	var lead := PaperSheet.words("One person, one passenger.", Brand.FONT_EDITORIAL, 40)
	lead.add_theme_color_override("font_color", PaperSheet.INK)
	var body := PaperSheet.words("Tallyport's money is real, so everyone here is a real, single person. Show your Town Pass once, with "
		+ "World ID, and you're in for good. World ID proves you're a unique human; it never tells the town who you are.",
		Brand.FONT_PROSE, 19, 600.0)
	body.add_theme_color_override("font_color", PaperSheet.INK)
	_status.add_theme_color_override("font_color", Brand.ORANGE)
	for part in [PaperSheet.caption("TOWN PASS · AT THE GANGWAY"), lead, body, _status]:
		_sheet.page.add_child(part)
	_sheet.actions.add_child(PaperSheet.Pill.new("E", "Verify with World ID"))
	client.you_changed.connect(_refresh)
	client.synced.connect(_refresh)
	client.event.connect(_on_event)
	desk.waiting_changed.connect(func(_w): _refresh())

func open() -> void:
	_key_up = false
	_sheet.open()
	_refresh()

func is_open() -> bool:
	return _sheet.visible

func _refresh() -> void:
	if not _sheet.visible: return
	if bool(client.you.get("human", false)):
		_done()
	elif client.you.get("wallet") == null:
		_status.text = "Your wallet is being made on the chain. A moment…"
	elif desk.waiting:
		_status.text = "Finish in the browser tab that opened: scan its code with the World App. This page moves on by itself. E opens it again."
	else:
		_status.text = "Press E to verify. A browser tab opens with a code to scan in the World App." + (" This town takes a rehearsal pass." if client.debug else "")

func _process(_delta: float) -> void:
	if _sheet.visible and not Input.is_action_pressed("interact"): _key_up = true

func _unhandled_input(e: InputEvent) -> void:
	if not _sheet.visible or not _key_up: return
	if not (e.is_action_pressed("interact") or e.is_action_pressed("ui_accept")): return
	get_viewport().set_input_as_handled()
	_key_up = false
	if client.you.get("wallet") == null: return
	desk.ask()
	_status.text = "Opening the pass page…"

func _on_event(e: Dictionary) -> void:
	if e.get("type") == "HumanVerified" and str(e.get("account", "")) == client.player: _done()

func _done() -> void:
	if not _sheet.visible: return
	_sheet.close()
	passed.emit()
