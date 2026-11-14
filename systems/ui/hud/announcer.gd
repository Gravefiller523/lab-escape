class_name Announcer
extends Label
## The lab's PA system (NEW 2026-11-12, roadmap WP8, mock-up approved by Zachary): a few seconds after the lift
## arrives on a floor, one AnnouncementData line shows at the top of the screen. Every PC picks the same line with
## the run's seed (SeededRng stream "announcement", the floor number), so nothing is sent over the network.
## Spec: docs/systems/ui.md.

const PREFIX: String = "PA: "
## NEW 2026-11-13 (roadmap WP19): seconds into the last ride up before its PA line.
const ESCAPE_LINE_DELAY: float = 1.0

var _left: float = 0.0
var _pending: String = ""
var _pending_in: float = -1.0


## The line on screen now ("" when hidden).
func get_line() -> String:
	return text if visible else ""


## The announcement for this floor of this run (the same on every PC), or "" if none fits.
static func pick(run_seed: int, floor_number: int, department_id: StringName, moment: StringName = &"floor") -> String:
	var lines: Array[AnnouncementData] = []
	var weights := PackedFloat32Array()
	for content: ContentData in ContentRegistry.get_all(&"announcement"):
		var line := content as AnnouncementData
		if line == null or line.weight <= 0.0:
			continue
		var line_moment: StringName = line.moment if line.moment != &"" else &"floor"
		if line_moment != moment:
			continue
		if not line.department_ids.is_empty() and not line.department_ids.has(department_id):
			continue
		lines.append(line)
		weights.append(line.weight)
	var index: int = SeededRng.pick_weighted(SeededRng.make(run_seed, &"announcement", floor_number), weights)
	return lines[index].text if index >= 0 else ""


## Shows a line now (tests and the console use this; floors use the delay).
func announce(line: String) -> void:
	text = PREFIX + line
	visible = not line.is_empty()
	_left = Config.game.announcement_seconds


func _ready() -> void:
	name = "Announcer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_minimum_size = Vector2(640, 0)
	add_theme_font_size_override("font_size", HudStyle.FONT_SIZE)
	add_theme_color_override("font_color", HudStyle.ACCENT)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", HudStyle.OUTLINE_SIZE)
	visible = false
	EventBus.floor_ready.connect(_on_floor_ready)
	# NEW 2026-11-13 (roadmap WP19): one line on the last ride up.
	EventBus.run_ended.connect(func(result: StringName) -> void:
		var run: RunState = GameFlow.get_run()
		if result == GameFlowService.RESULT_ESCAPED and run != null:
			_pending = pick(run.run_seed, run.floor_number + 1, &"", &"escape_ride")
			_pending_in = ESCAPE_LINE_DELAY)


func _on_floor_ready(floor_number: int, department_id: StringName) -> void:
	var run: RunState = GameFlow.get_run()
	if run == null:
		return
	_pending = pick(run.run_seed, floor_number, department_id)
	_pending_in = Config.game.announcement_delay_seconds


func _process(delta: float) -> void:
	if _pending_in >= 0.0:
		_pending_in -= delta
		if _pending_in < 0.0:
			announce(_pending)
	if visible:
		_left -= delta
		if _left <= 0.0:
			visible = false
