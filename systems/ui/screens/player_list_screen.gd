extends Control
## The Tab screen (NEW 2026-11-11, roadmap WP6): everyone in the game with their ping, a Mute button for each
## (only for you: voice stops playing their voice), and a Kick button for the host. Tab or Esc closes it. The mouse
## is free and your movement stops while it's open, like the pause menu. Spec: docs/systems/ui.md.

const PANEL_WIDTH: float = 560.0
const REFRESH_SECONDS: float = 0.5

var _rows: VBoxContainer
var _refresh_left: float = 0.0
## What the rows show now, so they're only rebuilt when something changes.
var _shown: String = ""


## One text per row, e.g. ["Sam (host) | 42 ms | Mute", "You | - |"]. Tests read it.
func get_row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for row: Node in _rows.get_children():
		var parts := PackedStringArray()
		for child: Node in row.get_children():
			if child is Label:
				parts.append((child as Label).text)
			elif child is Button:
				parts.append((child as Button).text)
		texts.append(" | ".join(parts))
	return texts


## The button with this text on that player's row (tests).
func find_button(player_id: int, text: String) -> Button:
	var row: Node = _rows.get_node_or_null(NodePath("Player_%d" % player_id))
	if row == null:
		return null
	for child: Node in row.get_children():
		var button := child as Button
		if button != null and button.text == text:
			return button
	return null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.45)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.panel_box(HudStyle.ACCENT, 2))
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title: Label = HudStyle.label("Title", 26)
	title.text = "Players"
	column.add_child(title)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	var hint: Label = HudStyle.label("Hint", HudStyle.SMALL_FONT_SIZE)
	hint.text = "Mute only changes what you hear. Tab or Esc closes this."
	hint.add_theme_color_override("font_color", HudStyle.MUTED)
	column.add_child(hint)
	_refresh()


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.PLAYER_LIST) or event.is_action_pressed(InputActions.PAUSE):
		UI.close_screen()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var me: int = Net.local_player_id()
	var entries: Array[Dictionary] = []
	var signature := PackedStringArray()
	for player_id: int in Net.get_player_ids():
		var name_text: String = Net.get_display_name(player_id)
		if player_id == me:
			name_text += " (you)"
		if Net.get_peer_id(player_id) == 1:
			name_text += " (host)"
		var ping: int = Net.get_ping_msec(player_id)
		var ping_text: String = "%d ms" % ping if ping >= 0 else "-"
		var muted: bool = Voice.is_player_muted(player_id)
		var can_kick: bool = Net.is_host() and player_id != me
		entries.append({"id": player_id, "name": name_text, "ping": ping_text, "muted": muted, "kick": can_kick})
		signature.append("%d|%s|%s|%s|%s" % [player_id, name_text, ping_text, muted, can_kick])
	var shown: String = "\n".join(signature)
	if shown == _shown:
		return
	_shown = shown
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries:
		_rows.add_child(_row(entry, me))


func _row(entry: Dictionary, me: int) -> HBoxContainer:
	var player_id: int = entry["id"]
	var row := HBoxContainer.new()
	row.name = "Player_%d" % player_id
	row.add_theme_constant_override("separation", 12)
	var name_label: Label = HudStyle.label("Name")
	name_label.text = entry["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var ping: Label = HudStyle.label("Ping", HudStyle.SMALL_FONT_SIZE)
	ping.text = entry["ping"]
	ping.custom_minimum_size = Vector2(70, 0)
	row.add_child(ping)
	if player_id != me:
		var mute := Button.new()
		mute.name = "Mute"
		mute.text = "Unmute" if entry["muted"] else "Mute"
		mute.pressed.connect(func() -> void:
			Voice.set_player_muted(player_id, not Voice.is_player_muted(player_id))
			_refresh())
		row.add_child(mute)
	if entry["kick"]:
		var kick := Button.new()
		kick.name = "Kick"
		kick.text = "Kick"
		kick.pressed.connect(func() -> void:
			Net.kick(player_id)
			_refresh())
		row.add_child(kick)
	return row
