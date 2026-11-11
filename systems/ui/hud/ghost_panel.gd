class_name GhostPanel
extends PanelContainer
## The middle of the screen while you are a ghost: who you're watching and how a teammate brings you back. A player
## who joined mid-run sees when they'll spawn instead. NEW 2026-11-11 (roadmap WP5). Reads Death (death_respawn) and
## Net (net_core). Spec: docs/systems/ui.md.

const PANEL_WIDTH: float = 460.0

var _title: Label
var _lines: Label
var _test_dead: int = -1
var _test_waiting: int = -1


## For tests only: pretend the local player is (1) or isn't (0) dead / waiting. -1 = ask the game.
func use_state(dead: int, waiting: int) -> void:
	_test_dead = dead
	_test_waiting = waiting


## Everything the panel says, or "" when hidden.
func get_text() -> String:
	return "%s\n%s" % [_title.text, _lines.text] if visible else ""


func _ready() -> void:
	name = "GhostPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudStyle.panel_box())
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = HudStyle.label("Title", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_lines = HudStyle.label("Lines")
	_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_lines)
	visible = false


func _process(_delta: float) -> void:
	var me: int = Net.local_player_id()
	var waiting: bool = Net.is_waiting_for_next_floor(me) if _test_waiting < 0 else _test_waiting == 1
	var dead: bool = Death.is_dead(me) if _test_dead < 0 else _test_dead == 1
	visible = waiting or dead
	if waiting:
		_title.text = "Joined mid-run"
		_lines.text = "You'll spawn with everyone on the next floor."
	elif dead:
		_title.text = "You're a ghost"
		var lines: Array[String] = []
		var watched: int = Death.get_watched_player_id()
		if watched != 0:
			lines.append("Watching %s" % Net.get_display_name(watched))
		if Death.get_free_reprints_left() > 0 and Net.get_player_count() <= 1:
			lines.append("Your free reprint is on its way.")
		else:
			var cost: int = Death.get_reprint_cost()
			lines.append("A teammate can reprint you: %d meat in a 3D printer." % cost)
		lines.append("Left / right click: watch someone else")
		_lines.text = "\n".join(lines)
