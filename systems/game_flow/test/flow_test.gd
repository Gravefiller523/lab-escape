extends Node
## game_flow test scene (run with F6, then with 2 windows). A panel of buttons that stays on screen
## while GameFlow changes scenes (it is added to the window, not to this scene), plus the state and run.
## Press "Break Room" first: that puts GameFlow in charge. The buttons that stand in for other systems
## (Depart = cargo_lift, Boss down = bosses, Team wipe = death_respawn) only do something in the host window.
## Launch options after "--": "host", "join", "port=7795".

var _status: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlowTestPanel"
	layer.layer = 15
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_button(row, "Host local", func() -> void: SteamSession.host_local(_port()))
	_add_button(row, "Join local", func() -> void: SteamSession.join_local("127.0.0.1", _port()))
	_add_button(row, "Break Room", GameFlow.go_to_break_room)
	_add_button(row, "Start run", func() -> void: GameFlow.start_run())
	var row2 := HBoxContainer.new()
	column.add_child(row2)
	_add_button(row2, "Depart (stub lift)", func() -> void: EventBus.lift_departed.emit(_floor_number()))
	_add_button(row2, "Boss down (stub)", func() -> void: EventBus.boss_defeated.emit(&""))
	_add_button(row2, "Team wipe (stub)", func() -> void: EventBus.team_wiped.emit())
	_add_button(row2, "End run", func() -> void: GameFlow.end_run(GameFlowService.RESULT_ABANDONED))
	_add_button(row2, "Main menu", GameFlow.return_to_main_menu)
	_status = Label.new()
	column.add_child(_status)
	# Updated by a timer on the panel, because this scene goes away when GameFlow changes scene.
	var updater := Timer.new()
	updater.wait_time = 0.2
	updater.autostart = true
	var label: Label = _status
	updater.timeout.connect(func() -> void:
		label.text = "%s | %s | players: %d" % ["HOST" if Net.is_host() else "CLIENT", GameFlow.describe(),
			Net.get_player_count()])
	layer.add_child(updater)
	# On the window, so it stays when GameFlow changes scene.
	get_tree().root.add_child.call_deferred(layer)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("host"):
		SteamSession.host_local.call_deferred(_port())
	elif args.has("join"):
		SteamSession.join_local.call_deferred("127.0.0.1", _port())


func _floor_number() -> int:
	var run: RunState = GameFlow.get_run()
	return run.floor_number if run != null else 0


func _port() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			return arg.trim_prefix("port=").to_int()
	return 7795


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
