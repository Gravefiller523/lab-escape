extends Control
## The main menu: Host (Steam), Quit, and a "Testing on one PC" section with Host local / Join local.
## Joining a friend over Steam happens through Steam itself: accept their invite, or right-click them
## in your friends list and choose "Join game". There is also a box for a lobby id, for testing.
##
## Launch options after "--" (for test windows): "host" or "join" press the local buttons by
## themselves, "port=7790" picks the port.

const DEFAULT_PORT: int = 7777
const DEFAULT_ADDRESS: String = "127.0.0.1"

var _status: Label
var _lobby_id_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_status()
	_run_launch_options.call_deferred()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.11, 0.85)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := Label.new()
	title.text = "LAB ESCAPE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	column.add_child(title)

	var host_button := _add_button(column, "Host game (Steam)", _on_host_steam)
	host_button.name = "HostSteamButton"
	host_button.disabled = not SteamSession.is_steam_running()
	var join_hint := Label.new()
	join_hint.text = "To join a friend: accept their Steam invite, or right-click them\nin your Steam friends list and choose \"Join game\"."
	join_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_hint.modulate = Color(0.8, 0.8, 0.85)
	column.add_child(join_hint)

	var lobby_row := HBoxContainer.new()
	column.add_child(lobby_row)
	_lobby_id_edit = LineEdit.new()
	_lobby_id_edit.placeholder_text = "Steam lobby id (testing)"
	_lobby_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_row.add_child(_lobby_id_edit)
	var join_id_button := _add_button(lobby_row, "Join by id", _on_join_by_id)
	join_id_button.disabled = not SteamSession.is_steam_running()

	column.add_child(HSeparator.new())
	var local_title := Label.new()
	local_title.text = "Testing on one PC (no Steam)"
	local_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(local_title)
	var address_row := HBoxContainer.new()
	column.add_child(address_row)
	_address_edit = LineEdit.new()
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
	var host_local := _add_button(local_row, "Host local", _on_host_local)
	host_local.name = "HostLocalButton"
	host_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join_local := _add_button(local_row, "Join local", _on_join_local)
	join_local.name = "JoinLocalButton"
	join_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	column.add_child(HSeparator.new())
	_add_button(column, "Quit", func() -> void: get_tree().quit())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 0.7, 0.75)
	column.add_child(_status)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _refresh_status() -> void:
	if SteamSession.is_steam_running():
		_status.text = "Steam: signed in as %s" % SteamSession.get_persona_name(SteamSession.get_local_steam_id())
	else:
		_status.text = "Steam isn't running: only local testing is available."


func _port() -> int:
	var text: String = _port_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() else DEFAULT_PORT


func _on_host_steam() -> void:
	_status.text = "Creating a Steam lobby..."
	SteamSession.host_lobby()


func _on_join_by_id() -> void:
	var text: String = _lobby_id_edit.text.strip_edges()
	if not text.is_valid_int():
		UI.toast("Type a lobby id (numbers only) first.")
		return
	_status.text = "Joining lobby..."
	SteamSession.join_lobby(text.to_int())


func _on_host_local() -> void:
	SteamSession.host_local(_port())


func _on_join_local() -> void:
	_status.text = "Connecting..."
	SteamSession.join_local(_address_edit.text.strip_edges(), _port())


func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			_port_edit.text = arg.trim_prefix("port=")
	if args.has("host_steam"):
		_on_host_steam()
	elif args.has("host"):
		_on_host_local()
	elif args.has("join"):
		_on_join_local()
