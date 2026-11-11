extends Control
## The small Esc menu: Resume, Controls (NEW 2026-11-11: the key for every action), Settings, Leave game, Quit.
## The game keeps running for everyone else.
## When you play solo (not connected) it also shows "Testing on one PC": Host local and Join local, so
## a test scene opened with F6 can become a 2-window test without the main menu.

const DEFAULT_PORT: int = 7777
const DEFAULT_ADDRESS: String = "127.0.0.1"
## NEW 2026-11-11 (roadmap WP6): how tall the controls list is (it scrolls).
const CONTROLS_HEIGHT: float = 260.0

var _address_edit: LineEdit
var _port_edit: LineEdit
var _controls: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.55)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(300, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	var title := Label.new()
	title.text = "Paused (the game keeps going for others)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	# The mic sensitivity slider moved to Settings > Audio (settings_input, 2026-10-24).
	if not Net.is_online():
		_add_local_testing(column)
	_add_button(column, "Resume", UI.close_screen)
	_add_button(column, "Controls", _toggle_controls)
	_controls = _controls_list()
	column.add_child(_controls)
	_add_button(column, "Settings", func() -> void: Settings.open(UI.SCREEN_PAUSE))
	_add_button(column, "Leave game", UI.leave_game)
	_add_button(column, "Quit", func() -> void: get_tree().quit())


## NEW 2026-11-11 (roadmap WP6): every action and the key it's on now (your rebinds included). Hidden until the
## Controls button is pressed; change keys in Settings > Controls.
func get_controls_text() -> String:
	var lines := PackedStringArray()
	for row: Node in _controls.get_node(^"Rows").get_children():
		lines.append((row as Label).text)
	return "\n".join(lines)


func is_controls_open() -> bool:
	return _controls.visible


func _toggle_controls() -> void:
	_controls.visible = not _controls.visible


func _controls_list() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.custom_minimum_size = Vector2(0, CONTROLS_HEIGHT)
	scroll.visible = false
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for action: StringName in SettingsService.rebindable_actions():
		var key: String = Settings.get_binding_text(action)
		if key.is_empty():
			continue
		var row := Label.new()
		row.text = "%s: %s" % [SettingsScreen.action_name(action), key]
		rows.add_child(row)
	return scroll


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)


## Address, port, Host local and Join local (the same as the main menu's testing section).
func _add_local_testing(column: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Testing on one PC (no Steam)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var address_row := HBoxContainer.new()
	column.add_child(address_row)
	_address_edit = LineEdit.new()
	_address_edit.name = "AddressEdit"
	_address_edit.text = DEFAULT_ADDRESS
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(_address_edit)
	_port_edit = LineEdit.new()
	_port_edit.name = "PortEdit"
	_port_edit.text = str(DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(90, 0)
	address_row.add_child(_port_edit)
	var local_row := HBoxContainer.new()
	column.add_child(local_row)
	var host := Button.new()
	host.name = "HostLocalButton"
	host.text = "Host local"
	host.custom_minimum_size = Vector2(0, 40)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_on_host_local)
	local_row.add_child(host)
	var join := Button.new()
	join.name = "JoinLocalButton"
	join.text = "Join local"
	join.custom_minimum_size = Vector2(0, 40)
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(_on_join_local)
	local_row.add_child(join)


func _port() -> int:
	var text: String = _port_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() else DEFAULT_PORT


## The scene stays open: its spawners notice the new connection and respawn the players.
func _on_host_local() -> void:
	var port: int = _port()
	UI.close_screen()
	SteamSession.host_local(port)
	UI.toast("Hosting on port %d. Open a second window and press Join local." % port)


func _on_join_local() -> void:
	var address: String = _address_edit.text.strip_edges()
	var port: int = _port()
	UI.close_screen()
	UI.toast("Joining %s:%d..." % [address, port])
	SteamSession.join_local(address, port)
