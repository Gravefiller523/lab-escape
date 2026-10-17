extends Control
## Test scene for steam_session (run alone with F6). Buttons for every SteamSession feature,
## a list of lobby members, and a Ping button that proves messages travel between windows.
## Run two instances (Debug > Customize Run Instances) for the local test.

const REFRESH_SECONDS: float = 0.5

var _status: Label
var _members: Label
var _log: Label
var _lobby_id_edit: LineEdit
var _refresh_timer: float = 0.0


func _ready() -> void:
	_build_ui()
	SteamSession.lobby_created.connect(func(lobby_id: int) -> void: _add_log("Lobby created: %d" % lobby_id))
	SteamSession.lobby_joined.connect(func(lobby_id: int) -> void: _add_log("Joined lobby: %d" % lobby_id))
	SteamSession.lobby_join_failed.connect(func(reason: String) -> void: _add_log("Failed: " + reason))
	SteamSession.connection_lost.connect(func() -> void: _add_log("Connection lost: the host left. (game_flow will return to the menu here.)"))
	_add_log("Steam running: %s" % SteamSession.is_steam_running())
	_refresh()
	_run_launch_options.call_deferred()


## Optional launch options, so test windows can start themselves (Customize Run Instances >
## Launch Arguments, after "--"): "host" hosts locally, "join" joins locally and pings once connected.
func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("host"):
		SteamSession.host_local()
	elif args.has("join"):
		SteamSession.lobby_joined.connect(func(_lobby_id: int) -> void: _on_ping(), CONNECT_ONE_SHOT)
		SteamSession.join_local()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_SECONDS:
		_refresh_timer = 0.0
		_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var title := Label.new()
	title.text = "steam_session test"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	var steam_row := HBoxContainer.new()
	column.add_child(steam_row)
	_add_button(steam_row, "Host (Steam)", SteamSession.host_lobby)
	_lobby_id_edit = LineEdit.new()
	_lobby_id_edit.placeholder_text = "lobby id"
	_lobby_id_edit.custom_minimum_size = Vector2(220, 0)
	steam_row.add_child(_lobby_id_edit)
	_add_button(steam_row, "Join by id", _on_join_by_id)
	_add_button(steam_row, "Invite", SteamSession.open_invite_overlay)
	_add_button(steam_row, "Copy lobby id", _on_copy_lobby_id)

	var local_row := HBoxContainer.new()
	column.add_child(local_row)
	_add_button(local_row, "Host local", func() -> void: SteamSession.host_local())
	_add_button(local_row, "Join local", func() -> void: SteamSession.join_local())
	_add_button(local_row, "Leave", SteamSession.leave_lobby)
	_add_button(local_row, "Ping everyone", _on_ping)

	_status = Label.new()
	column.add_child(_status)
	_members = Label.new()
	column.add_child(_members)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_log)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _refresh() -> void:
	var mode: String = "local" if SteamSession.is_local_mode() else "Steam"
	if SteamSession.get_lobby_id() == 0:
		_status.text = "Not in a lobby. Steam running: %s" % SteamSession.is_steam_running()
	else:
		_status.text = "In lobby %d (%s mode). I am %s (%d)." % [SteamSession.get_lobby_id(), mode,
			SteamSession.get_persona_name(SteamSession.get_local_steam_id()), SteamSession.get_local_steam_id()]
	var lines: PackedStringArray = ["Lobby members (max %d):" % SteamSession.get_lobby_max_members()]
	for member_id: int in SteamSession.get_lobby_member_ids():
		lines.append("  - %s (%d)" % [SteamSession.get_persona_name(member_id), member_id])
	_members.text = "\n".join(lines)


func _add_log(text: String) -> void:
	print("[lobby_test] " + text)
	_log.text = text + "\n" + _log.text


func _on_join_by_id() -> void:
	var text: String = _lobby_id_edit.text.strip_edges()
	if not text.is_valid_int():
		_add_log("Type a lobby id (numbers only) first.")
		return
	SteamSession.join_lobby(text.to_int())


func _on_copy_lobby_id() -> void:
	DisplayServer.clipboard_set(str(SteamSession.get_lobby_id()))
	_add_log("Copied lobby id %d." % SteamSession.get_lobby_id())


func _on_ping() -> void:
	if SteamSession.get_lobby_id() == 0:
		_add_log("Join or host a lobby first.")
		return
	_receive_ping.rpc(SteamSession.get_local_steam_id())


@rpc("any_peer", "call_local", "reliable")
func _receive_ping(from_id: int) -> void:
	_add_log("Ping from %s (%d)" % [SteamSession.get_persona_name(from_id), from_id])
