class_name PlayerList
extends VBoxContainer
## Everyone in the game (bottom right of the HUD): their name, and "speaking" or "ghost" next to it. One line per
## player in Net.get_player_ids(), never a fixed number. NEW 2026-11-11 (roadmap WP5). Spec: docs/systems/ui.md.

var _speaking: Dictionary[int, bool] = {}
var _shown: String = ""


## The lines on show, e.g. ["Sam  speaking", "Jo  ghost"].
func get_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for child: Node in get_children():
		lines.append((child as Label).text)
	return lines


func _ready() -> void:
	name = "PlayerList"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	EventBus.player_speaking_changed.connect(func(player_id: int, speaking: bool) -> void:
		_speaking[player_id] = speaking)
	EventBus.player_left.connect(func(player_id: int) -> void: _speaking.erase(player_id))


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	for player_id: int in Net.get_player_ids():
		var line: String = Net.get_display_name(player_id)
		if Death.is_dead(player_id):
			line += "  ghost"
		elif Net.is_waiting_for_next_floor(player_id):
			line += "  joining"
		elif _speaking.get(player_id, false):
			line += "  speaking"
		lines.append(line)
	var shown: String = "\n".join(lines)
	if shown == _shown:
		return
	_shown = shown
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for line: String in lines:
		var label: Label = HudStyle.label("Player", HudStyle.SMALL_FONT_SIZE)
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if line.ends_with("ghost"):
			label.add_theme_color_override("font_color", HudStyle.MUTED)
		add_child(label)
