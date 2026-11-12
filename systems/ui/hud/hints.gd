class_name Hints
extends PanelContainer
## First-time hints (NEW 2026-11-12, roadmap WP8, mock-up approved by Zachary): the first time something happens to
## you, its HintData tip shows for Config.game.hint_seconds, and never again for this player. Which hints were seen is
## kept in the player's profile (SaveSystem, CHANGED 2026-11-12 in WP12). Spec: docs/systems/ui.md.
##
## Triggers (HintData.trigger): first_floor (the first floor of a run), gem_grabbed, vial_grabbed (a DNA vial or data
## drive), lift_part_grabbed, vendor_near (within VENDOR_NEAR_DISTANCE of a vending machine), someone_died,
## boss_floor.

const SECTION: String = "seen"
const VENDOR_NEAR_DISTANCE: float = 4.0
const VENDOR_CHECK_SECONDS: float = 0.5

var _label: Label
var _file_path: String = ""
var _seen: ConfigFile = ConfigFile.new()
var _left: float = 0.0
var _vendor_check_left: float = 0.0
var _loaded: bool = false
var _test_in_world: bool = false


## For tests (and the full-run test's game copies): keep the seen hints in this file instead, so test runs never mark
## hints as seen for the real player. Call before the first hint shows.
func use_file(path: String) -> void:
	_file_path = path
	_loaded = false


## The tip on screen now ("" when hidden).
func get_text() -> String:
	return _label.text if visible else ""


func has_seen(hint_id: StringName) -> bool:
	if _file_path.is_empty():
		return SaveSystem.has_seen_hint(hint_id)
	_load()
	return bool(_seen.get_value(SECTION, String(hint_id), false))


## Something happened: show the first unseen hint for this trigger. True if one showed. Only in the game world
## (game_flow's), so systems' test scenes and unit tests never use up the real player's hints.
func trigger(trigger_name: StringName) -> bool:
	if not _in_game_world():
		return false
	for content: ContentData in ContentRegistry.get_all(&"hint"):
		var hint := content as HintData
		if hint == null or hint.trigger != trigger_name or has_seen(hint.id):
			continue
		_mark_seen(hint.id)
		_label.text = hint.text
		visible = true
		_left = Config.game.hint_seconds
		return true
	return false


func _ready() -> void:
	name = "Hints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudStyle.panel_box(HudStyle.ACCENT, 2))
	custom_minimum_size = Vector2(520, 0)
	_label = HudStyle.label("Text")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	visible = false
	EventBus.floor_ready.connect(func(floor_number: int, _department_id: StringName) -> void:
		if floor_number == 1:
			trigger(&"first_floor"))
	EventBus.prop_grabbed.connect(_on_prop_grabbed)
	DebugConsole.register_command(&"hints", _cmd_hints, "hints reset: show every first-time hint again", false)
	EventBus.player_died.connect(func(_player_id: int, _at: Vector3) -> void: trigger(&"someone_died"))
	EventBus.boss_floor_started.connect(func(_boss_id: StringName) -> void: trigger(&"boss_floor"))


func _on_prop_grabbed(player_id: int, prop: Node3D) -> void:
	var held := prop as NetProp
	if player_id != Net.local_player_id() or held == null or held.data == null:
		return
	if held.data.gem_value > 0:
		trigger(&"gem_grabbed")
	elif held.data.tags.has("dna_vial") or held.data.tags.has("data_drive"):
		trigger(&"vial_grabbed")
	elif held.data.tags.has("lift_part"):
		trigger(&"lift_part_grabbed")


func _process(delta: float) -> void:
	if visible:
		_left -= delta
		if _left <= 0.0:
			visible = false
	_vendor_check_left -= delta
	if _vendor_check_left > 0.0:
		return
	_vendor_check_left = VENDOR_CHECK_SECONDS
	var body: PlayerCharacter = PlayerCharacter.find(Net.local_player_id())
	if body == null:
		return
	for node: Node in get_tree().get_nodes_in_group(Vendor.GROUP):
		var vendor := node as Node3D
		if vendor != null and vendor.global_position.distance_to(body.global_position) <= VENDOR_NEAR_DISTANCE:
			trigger(&"vendor_near")
			return


## For tests only: act as if this were the game world (hints only show there).
func pretend_in_game_world() -> void:
	_test_in_world = true


func _in_game_world() -> bool:
	return _test_in_world or GameWorld.current() != null


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_seen = ConfigFile.new()
	_seen.load(_file_path)


func _mark_seen(hint_id: StringName) -> void:
	if _file_path.is_empty():
		SaveSystem.mark_hint_seen(hint_id)
		return
	_load()
	_seen.set_value(SECTION, String(hint_id), true)
	_seen.save(_file_path)


## Console: `hints reset` forgets which hints this player has seen.
func _cmd_hints(args: PackedStringArray, _player_id: int) -> String:
	if args.is_empty() or args[0] != "reset":
		return "Usage: hints reset"
	if _file_path.is_empty():
		SaveSystem.reset_seen_hints()
	else:
		_seen = ConfigFile.new()
		_seen.save(_file_path)
	return "Every first-time hint will show again."
