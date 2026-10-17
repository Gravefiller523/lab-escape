extends Control
## Test scene for net_core (run alone with F6). Shows the roster, slot indexes and records, with
## buttons to fake a disconnect and reconnect. Run 2 or 3 instances (Debug > Customize Run Instances).
##
## STUB: "Start run", "Next floor" and "End run" emit game_flow's EventBus signals on this PC only,
## because game_flow isn't built yet. Press them in the host window.

const REFRESH_SECONDS: float = 0.5
const TEST_UPGRADE_ID: StringName = &"mutation_fly"

var _status: Label
var _roster: Label
var _log: Label
var _refresh_timer: float = 0.0
var _floor_number: int = 0


func _ready() -> void:
	_build_ui()
	Net.join_refused.connect(func(reason: String) -> void: _add_log("Refused: " + reason))
	SteamSession.lobby_join_failed.connect(func(reason: String) -> void: _add_log("Failed: " + reason))
	SteamSession.connection_lost.connect(func() -> void: _add_log("Connection lost: the host left."))
	EventBus.player_joined.connect(func(player_id: int) -> void: _add_log("player_joined %s" % _name(player_id)))
	EventBus.player_left.connect(func(player_id: int) -> void: _add_log("player_left %s" % _name(player_id)))
	EventBus.player_reconnected.connect(func(player_id: int) -> void: _add_log("player_reconnected %s" % _name(player_id)))
	_refresh()
	_run_launch_options.call_deferred()


## Optional launch options (Customize Run Instances > Launch Arguments, after "--"):
## "host" hosts locally, "join" joins locally.
func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("host"):
		SteamSession.host_local()
	elif args.has("join"):
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
	title.text = "net_core roster test"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	var connect_row := HBoxContainer.new()
	column.add_child(connect_row)
	_add_button(connect_row, "Host local", func() -> void: SteamSession.host_local())
	_add_button(connect_row, "Join local", func() -> void: SteamSession.join_local())
	_add_button(connect_row, "Host (Steam)", SteamSession.host_lobby)
	_add_button(connect_row, "Invite", SteamSession.open_invite_overlay)
	_add_button(connect_row, "Disconnect", SteamSession.leave_lobby)
	_add_button(connect_row, "Reconnect", _on_reconnect)

	var host_row := HBoxContainer.new()
	column.add_child(host_row)
	_add_button(host_row, "Start run (stub)", _on_start_run)
	_add_button(host_row, "Next floor (stub)", _on_next_floor)
	_add_button(host_row, "End run (stub)", func() -> void: EventBus.run_ended.emit(&"abandoned"))
	_add_button(host_row, "Give everyone Fly", _on_give_upgrade)
	_add_button(host_row, "Toggle joining", _on_toggle_joining)
	_add_button(host_row, "Kick last player", _on_kick_last)

	_status = Label.new()
	column.add_child(_status)
	_roster = Label.new()
	column.add_child(_roster)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_log)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _refresh() -> void:
	var role: String = "HOST" if Net.is_host() else "CLIENT"
	_status.text = "%s | online: %s | me: %s | run active: %s | joining open: %s | players: %d" % [
		role, Net.is_online(), _name(Net.local_player_id()), Net.is_run_active(),
		Net.is_joining_open(), Net.get_player_count()]
	var lines: PackedStringArray = ["Roster (connected first, then players who dropped mid-run):"]
	var shown: Array[int] = Net.get_player_ids()
	for player_id: int in shown:
		lines.append(_record_line(player_id))
	for record_id: int in Net.get_record_ids():
		if not shown.has(record_id):
			lines.append(_record_line(record_id))
	_roster.text = "\n".join(lines)



func _record_line(player_id: int) -> String:
	var record: PlayerRecord = Net.get_record(player_id)
	if record == null:
		return "  - %d (no record)" % player_id
	var flags: PackedStringArray = []
	if not record.connected:
		flags.append("DISCONNECTED")
	if not record.is_alive:
		flags.append("dead")
	if record.waiting_for_next_floor:
		flags.append("WAITING FOR NEXT FLOOR")
	return "  - slot %d: %s (%d) peer %d upgrades %s %s" % [record.slot_index, record.display_name,
		player_id, Net.get_peer_id(player_id), record.upgrade_ids, " ".join(flags)]


func _name(player_id: int) -> String:
	var display_name: String = Net.get_display_name(player_id)
	return display_name if not display_name.is_empty() else str(player_id)


func _add_log(text: String) -> void:
	print("[roster_test] " + text)
	_log.text = text + "\n" + _log.text


func _on_reconnect() -> void:
	if SteamSession.is_local_mode():
		SteamSession.leave_lobby()
	SteamSession.join_local()


func _on_start_run() -> void:
	_floor_number = 1
	EventBus.run_started.emit(randi())
	_add_log("Run started (stub). New joiners now wait for the next floor.")


func _on_next_floor() -> void:
	_floor_number += 1
	EventBus.floor_loading.emit(_floor_number, &"department_zoology")
	_add_log("Floor %d loading (stub). Waiting players spawn now." % _floor_number)


func _on_give_upgrade() -> void:
	if not Net.is_host():
		_add_log("Only the host can change records.")
		return
	for player_id: int in Net.get_player_ids():
		var upgrades: Array[StringName] = Net.get_record(player_id).upgrade_ids.duplicate()
		upgrades.append(TEST_UPGRADE_ID)
		Net.update_record(player_id, &"upgrade_ids", upgrades)


func _on_toggle_joining() -> void:
	Net.set_joining_open(not Net.is_joining_open())


func _on_kick_last() -> void:
	var ids: Array[int] = Net.get_player_ids()
	if ids.size() > 1:
		Net.kick(ids[ids.size() - 1])
