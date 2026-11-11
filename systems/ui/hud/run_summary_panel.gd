class_name RunSummaryPanel
extends PanelContainer
## The end of a run, while the lift takes everyone back to the Break Room: escaped or wiped, how far you got, how
## long it took, and a line per player (deaths, gems spent, upgrades). NEW 2026-11-11 (roadmap WP5). Every PC counts
## what it sees on EventBus; upgrades come from the synced player records (net_core). Spec: docs/systems/ui.md.

const PANEL_WIDTH: float = 560.0
const RESULT_TEXTS: Dictionary[StringName, String] = {
	&"escaped": "Escaped", &"wiped": "Wiped out", &"abandoned": "Run abandoned"}

var _title: Label
var _details: Label
var _table: GridContainer
var _started_msec: int = 0
var _floor: int = 0
var _deaths: Dictionary[int, int] = {}
var _gems_spent: Dictionary[int, int] = {}
var _force_visible: bool = false


## For tests only: show the panel now, whatever game_flow's state.
func show_now() -> void:
	_force_visible = true


## The title and details ("Escaped", "12 floors, 58 min"), or "" when hidden.
func get_text() -> String:
	return "%s\n%s" % [_title.text, _details.text] if visible else ""


## One line per player: "Sam | 2 | 63 | Fly, Frog".
func get_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	var cells: Array[Node] = _table.get_children()
	for start: int in range(_table.columns, cells.size(), _table.columns):
		var parts := PackedStringArray()
		for column: int in _table.columns:
			parts.append((cells[start + column] as Label).text)
		rows.append(" | ".join(parts))
	return rows


func _ready() -> void:
	name = "RunSummary"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudStyle.panel_box(HudStyle.ACCENT, 2))
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = HudStyle.label("Title", 30)
	column.add_child(_title)
	_details = HudStyle.label("Details")
	_details.add_theme_color_override("font_color", HudStyle.MUTED)
	column.add_child(_details)
	_table = GridContainer.new()
	_table.name = "Table"
	_table.columns = 4
	_table.add_theme_constant_override("h_separation", 18)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_table)
	visible = false
	EventBus.run_started.connect(func(_run_seed: int) -> void: _reset())
	EventBus.floor_ready.connect(func(floor_number: int, _department_id: StringName) -> void: _floor = floor_number)
	EventBus.player_died.connect(func(player_id: int, _at: Vector3) -> void:
		_deaths[player_id] = _deaths.get(player_id, 0) + 1)
	EventBus.vendor_purchase.connect(func(player_id: int, _item_id: StringName, price: int) -> void:
		_gems_spent[player_id] = _gems_spent.get(player_id, 0) + price)
	EventBus.run_ended.connect(_on_run_ended)


func _process(_delta: float) -> void:
	if _force_visible:
		return
	visible = visible and GameFlow.get_state() == GameFlowService.State.RUN_SUMMARY


func _reset() -> void:
	_started_msec = Time.get_ticks_msec()
	_floor = 0
	_deaths.clear()
	_gems_spent.clear()


func _on_run_ended(result: StringName) -> void:
	_title.text = RESULT_TEXTS.get(result, String(result).capitalize())
	_title.add_theme_color_override("font_color", HudStyle.GOOD if result == &"escaped" else HudStyle.BAD)
	var minutes: int = roundi(float(Time.get_ticks_msec() - _started_msec) / 60000.0) if _started_msec > 0 else 0
	_details.text = "%d %s, %d min" % [_floor, "floor" if _floor == 1 else "floors", minutes]
	for child: Node in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	for header: String in ["Player", "Deaths", "Gems spent", "Upgrades"]:
		_add_cell(header, HudStyle.MUTED)
	for player_id: int in Net.get_record_ids():
		var record: PlayerRecord = Net.get_record(player_id)
		var upgrades := PackedStringArray()
		if record != null:
			for upgrade_id: StringName in record.upgrade_ids:
				var data: ContentData = ContentRegistry.get_content(upgrade_id)
				upgrades.append(data.display_name if data != null and not data.display_name.is_empty() else String(upgrade_id))
		_add_cell(Net.get_display_name(player_id), Color.WHITE)
		_add_cell(str(_deaths.get(player_id, 0)), Color.WHITE)
		_add_cell(str(_gems_spent.get(player_id, 0)), Color.WHITE)
		_add_cell(", ".join(upgrades) if not upgrades.is_empty() else "-", Color.WHITE)
	visible = true


func _add_cell(text: String, color: Color) -> void:
	var cell: Label = HudStyle.label("Cell", HudStyle.SMALL_FONT_SIZE)
	cell.text = text
	cell.add_theme_color_override("font_color", color)
	_table.add_child(cell)
