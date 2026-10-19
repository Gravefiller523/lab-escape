extends Node
## Test scene for break_room (run alone with F6): the game world with the Break Room around the cargo
## lift (as in the game), plus Host/Join buttons. game_flow isn't in charge here, so pressing Go in
## the lift just rides for a moment and comes back to the Break Room. Run 2 to 4 instances (Debug > Customize Run Instances).
## Launch options after "--": "host" or "join" start by themselves, "port=7790" picks another port.

const BREAK_ROOM_SCENE: PackedScene = preload("res://systems/break_room/break_room.tscn")
const WORLD_SCENE: PackedScene = preload("res://systems/game_flow/game_world.tscn")

var _status: Label
var _prompt: Label
var _toast: Label
var _toast_left: float = 0.0
var _overview: Camera3D


func _ready() -> void:
	var world := WORLD_SCENE.instantiate() as GameWorld
	add_child(world)
	var spawner: PlayerSpawner = world.get_player_spawner()
	spawner.spawn_points = world.build_break_room(BREAK_ROOM_SCENE)
	spawner.auto_spawn = true
	spawner.spawn_all(spawner.spawn_points)
	world.get_lift().arrive(0, true)
	# No game_flow here: a ride just comes back after a moment.
	EventBus.lift_departed.connect(func(_floor_number: int) -> void:
		get_tree().create_timer(Config.game.lift_ride_seconds).timeout.connect(func() -> void:
			world.get_lift().arrive(0, true)))
	# Shown only while this window has no body of its own.
	_overview = Camera3D.new()
	_overview.position = Vector3(0, 14, 12)
	_overview.rotation_degrees = Vector3(-50, 0, 0)
	add_child(_overview)
	_build_ui()
	EventBus.toast_requested.connect(_on_toast)
	_run_launch_options.call_deferred()


func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = 7777
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			port = arg.trim_prefix("port=").to_int()
	if args.has("host"):
		SteamSession.host_local(port)
	elif args.has("join"):
		SteamSession.join_local("127.0.0.1", port)


func _process(delta: float) -> void:
	if PlayerCharacter.find(Net.local_player_id()) == null and not _overview.current:
		_overview.make_current()
	var connection: String = "solo"
	if SteamSession.is_local_mode():
		connection = "local mode"
	elif SteamSession.get_lobby_id() != 0:
		connection = "Steam lobby %d" % SteamSession.get_lobby_id()
	_status.text = "%s | players: %d | %s" % ["HOST" if Net.is_host() else "CLIENT", Net.get_player_count(), connection]
	# STUB (ui HUD): the "E: ..." prompt, drawn here until the HUD exists.
	var controller: InteractionController = Interaction.get_local_controller()
	var prompt: String = controller.get_prompt() if controller != null else ""
	_prompt.text = "" if prompt.is_empty() else "E: %s" % prompt
	_toast_left -= delta
	if _toast_left <= 0.0:
		_toast.text = ""


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(12, 12)
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_button(row, "Host local", func() -> void: SteamSession.host_local())
	_add_button(row, "Join local", func() -> void: SteamSession.join_local())
	_add_button(row, "Host (Steam)", SteamSession.host_lobby)
	_add_button(row, "Invite", SteamSession.open_invite_overlay)
	_add_button(row, "Leave", SteamSession.leave_lobby)
	_add_button(row, "End run (stub)", func() -> void: EventBus.run_ended.emit(&"escaped"))
	_status = Label.new()
	column.add_child(_status)
	var help := Label.new()
	help.text = "WASD move, Shift sprint, Space jump, Ctrl crouch, E use (look at it), Esc frees the mouse."
	column.add_child(help)
	_toast = Label.new()
	_toast.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	column.add_child(_toast)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(300, 80)
	center.add_child(middle)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(crosshair)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	middle.add_child(_prompt)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)


## STUB (ui): shows toasts at the top of the screen.
func _on_toast(text: String) -> void:
	_toast.text = text
	_toast_left = 4.0
