class_name DebugConsoleService
extends CanvasLayer
## Autoload "DebugConsole". An in-game console for testing, opened with the debug console key (`).
## Other systems add commands with register_command() and spawners with register_spawner(), so the
## console never needs editing when content or systems are added. Spec: docs/systems/debug_console.md.
##
## Cheats ("host only" commands) run only on the host, and only in editor builds unless
## Config.game.cheats_in_release is on. A client typing one sends it to the host, which runs it as
## that player and sends the output back.

const HISTORY_FILE: String = "user://console_history.txt"
const MAX_HISTORY: int = 50
const MAX_OUTPUT_LINES: int = 200
## Above the game and the UI.
const LAYER: int = 20
## How far ahead of you `spawn` puts things when you aren't looking at anything (metres).
const SPAWN_DISTANCE: float = 2.5
## The furthest point `spawn` can use (metres).
const SPAWN_REACH: float = 20.0
## Spawned things are lifted this far off the surface you look at, and spread this far apart.
const SPAWN_LIFT: float = 0.5
const SPAWN_SPREAD: float = 0.7

## The content registry's script, for its static type_key_for_id() (the autoload has no class_name).
const REGISTRY_SCRIPT := preload("res://core/autoload/content_registry.gd")
const MSG_UNKNOWN: String = "Unknown command '%s'. Type help for the list."
const MSG_NO_CHEATS: String = "Cheats are off in this build (Config: cheats_in_release)."
const MSG_SENT_TO_HOST: String = "(sent to the host)"
## Export presets with this custom feature allow cheats (test builds only, never the Steam release).
const CHEATS_FEATURE: String = "cheats"

## Command name -> {"handler": Callable, "help": String, "host_only": bool}
var _commands: Dictionary[StringName, Dictionary] = {}
## Content type -> spawner: func(id: StringName, at: Transform3D, count: int, player_id: int) -> String
var _spawners: Dictionary[StringName, Callable] = {}
var _net: NetService
var _config: GameConfig
## Editor builds, and test builds exported with the custom feature "cheats" (the "Windows Steam test" preset).
var _is_editor: bool = OS.has_feature("editor") or OS.has_feature(CHEATS_FEATURE)
var _history: PackedStringArray = []
var _history_index: int = -1
var _panel: PanelContainer
var _output: RichTextLabel
var _input: LineEdit
var _fps_on: bool = false
var _fps_label: Label
## The last output the host sent back (used by tests).
var last_remote_output: String = ""


## For tests only: a different Net and config, and whether to act like an editor build.
## Call before adding the node to the tree.
func use_test_setup(net: NetService, config: GameConfig, is_editor: bool) -> void:
	_net = net
	_config = config
	_is_editor = is_editor


func _ready() -> void:
	if _net == null:
		_net = Net
	if _config == null:
		_config = Config.game
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_load_history()
	_register_built_ins()


## Adds a command. handler: func(args: PackedStringArray, player_id: int) -> String (text to print).
## host_only commands are cheats: they run on the host, and only when cheats are allowed.
func register_command(command: StringName, handler: Callable, help: String, host_only: bool = true) -> void:
	_commands[command] = {"handler": handler, "help": help, "host_only": host_only}


## Makes a content type spawnable with `spawn <id>`.
## handler: func(id: StringName, at: Transform3D, count: int, player_id: int) -> String
func register_spawner(type_key: StringName, handler: Callable) -> void:
	_spawners[type_key] = handler


## Runs a command line as the local player and returns what it printed.
func run(command_line: String) -> String:
	var parts: PackedStringArray = command_line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var command := StringName(parts[0].to_lower())
	if not _commands.has(command):
		return MSG_UNKNOWN % parts[0]
	var host_only: bool = _commands[command]["host_only"]
	if host_only and not _net.is_host():
		_run_on_host.rpc_id(1, command_line)
		return MSG_SENT_TO_HOST
	return _execute(command_line, _net.local_player_id())


## Editor builds, test builds with the "cheats" feature, or Config.game.cheats_in_release.
## In multiplayer only the host's setting matters.
func cheats_allowed() -> bool:
	return _is_editor or _config.cheats_in_release


func print_line(text: String) -> void:
	if _output == null:
		return
	_output.append_text(text + "\n")
	if _output.get_line_count() > MAX_OUTPUT_LINES:
		var lines: PackedStringArray = _output.get_parsed_text().split("\n")
		_output.clear()
		_output.append_text("\n".join(lines.slice(lines.size() - MAX_OUTPUT_LINES)))


func is_open() -> bool:
	return _panel != null and _panel.visible


func set_open(open: bool) -> void:
	if _panel == null or open == is_open():
		return
	_panel.visible = open
	var body: PlayerCharacter = PlayerCharacter.find(_net.local_player_id())
	if body != null:
		body.set_input_enabled(not open)
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.mouse_mode
	if open:
		_input.grab_focus()
		_input.clear()


## Runs a command for a player on this PC (checks cheats for host-only commands).
func _execute(command_line: String, player_id: int) -> String:
	var parts: PackedStringArray = command_line.strip_edges().split(" ", false)
	var command := StringName(parts[0].to_lower())
	var entry: Dictionary = _commands.get(command, {})
	if entry.is_empty():
		return MSG_UNKNOWN % parts[0]
	var host_only: bool = entry["host_only"]
	if host_only and not cheats_allowed():
		return MSG_NO_CHEATS
	var handler: Callable = entry["handler"]
	return str(handler.call(parts.slice(1), player_id))


## Client -> host: run a host-only command as the sending player, send the output back.
@rpc("any_peer", "call_remote", "reliable")
func _run_on_host(command_line: String) -> void:
	if not _net.is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var player_id: int = _net.get_player_id_for_peer(sender)
	if player_id == 0:
		return
	_print_remote.rpc_id(sender, _execute(command_line, player_id))


@rpc("authority", "call_remote", "reliable")
func _print_remote(text: String) -> void:
	last_remote_output = text
	print_line(text)


# --- Built-in commands ------------------------------------------------------------------------

func _register_built_ins() -> void:
	register_command(&"help", _cmd_help, "help: list every command", false)
	register_command(&"list", _cmd_list, "list <type>: ids of a content type (e.g. list prop). No type: the types", false)
	register_command(&"validate", _cmd_validate, "validate: check every content file for mistakes", false)
	register_command(&"spawn", _cmd_spawn, "spawn <id> [count]: spawn content where you are looking", true)
	register_command(&"seed", _cmd_seed, "seed: the current run's seed", false)
	register_command(&"net", _cmd_net, "net: who is connected, slots and ping", false)
	register_command(&"fps", _cmd_fps, "fps: show or hide the frame rate", false)
	register_command(&"clear", _cmd_clear, "clear: empty the console", false)
	# NEW 2026-10-29: feel tuning. Runs on this PC only (not sent to the host), but still a cheat.
	register_command(&"tune", _cmd_tune,
		"tune [section.name] [value]: show or change a feel number live, e.g. tune props.throw_force 25 (this PC only)", false)
	register_command(&"tune_save", _cmd_tune_save, "tune_save: keep tuned numbers (writes config/feel_tuning.tres, editor only)", false)
	register_command(&"tune_reset", _cmd_tune_reset, "tune_reset: undo unsaved tuning (reloads the files)", false)


func _cmd_help(_args: PackedStringArray, _player_id: int) -> String:
	var names: Array[StringName] = _commands.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var lines: PackedStringArray = []
	for command: StringName in names:
		var entry: Dictionary = _commands[command]
		var cheat: bool = entry["host_only"]
		lines.append(("%s   (cheat)" if cheat else "%s") % str(entry["help"]))
	return "\n".join(lines)


func _cmd_list(args: PackedStringArray, _player_id: int) -> String:
	if args.is_empty():
		return "Content types: " + ", ".join(ContentRegistry.get_type_keys())
	var ids: Array[StringName] = ContentRegistry.get_all_ids(StringName(args[0]), true)
	if ids.is_empty():
		return "No content of type '%s'." % args[0]
	return "%d %s: %s" % [ids.size(), args[0], ", ".join(ids)]


func _cmd_validate(_args: PackedStringArray, _player_id: int) -> String:
	var problems: PackedStringArray = ContentValidator.validate_all(
		ContentRegistry.get_everything(), ContentRegistry.get_type_keys())
	problems.append_array(ContentRegistry.load_errors)
	if problems.is_empty():
		return "All %d content files are OK." % ContentRegistry.get_everything().size()
	return "%d problem(s):\n%s" % [problems.size(), "\n".join(problems)]


func _cmd_spawn(args: PackedStringArray, player_id: int) -> String:
	if args.is_empty():
		return "Usage: spawn <id> [count]"
	var id := StringName(args[0])
	var count: int = clampi(args[1].to_int(), 1, 100) if args.size() > 1 and args[1].is_valid_int() else 1
	if not ContentRegistry.has_content(id):
		return "No content called '%s'. Try: list" % id
	var type_key: StringName = REGISTRY_SCRIPT.type_key_for_id(id)
	if not _spawners.has(type_key):
		return "Nothing can spawn '%s' content yet (no spawner registered for it)." % type_key
	var handler: Callable = _spawners[type_key]
	return str(handler.call(id, _spawn_point(player_id), count, player_id))


func _cmd_seed(_args: PackedStringArray, _player_id: int) -> String:
	# STUB until game_flow: there is no run yet.
	return "No run in progress (game_flow isn't built yet)."


func _cmd_net(_args: PackedStringArray, _player_id: int) -> String:
	var lines: PackedStringArray = ["%s | %d player(s) | %s" % ["HOST" if _net.is_host() else "CLIENT",
		_net.get_player_count(), "online" if _net.is_online() else "solo"]]
	for player_id: int in _net.get_player_ids():
		lines.append("  slot %d: %s (%d)%s%s" % [_net.get_slot_index(player_id), _net.get_display_name(player_id),
			player_id, " (you)" if player_id == _net.local_player_id() else "", _ping_text(player_id)])
	return "\n".join(lines)


func _cmd_fps(_args: PackedStringArray, _player_id: int) -> String:
	_fps_on = not _fps_on
	_fps_label.visible = _fps_on
	return "FPS display %s." % ("on" if _fps_on else "off")


func _cmd_tune(args: PackedStringArray, _player_id: int) -> String:
	if not cheats_allowed():
		return MSG_NO_CHEATS
	return TuneCommands.tune(args, Config.feel)


func _cmd_tune_save(_args: PackedStringArray, _player_id: int) -> String:
	if not cheats_allowed():
		return MSG_NO_CHEATS
	return TuneCommands.save(Config.feel, OS.has_feature("editor"))


func _cmd_tune_reset(_args: PackedStringArray, _player_id: int) -> String:
	if not cheats_allowed():
		return MSG_NO_CHEATS
	return TuneCommands.reset(Config.feel)


func _cmd_clear(_args: PackedStringArray, _player_id: int) -> String:
	if _output != null:
		_output.clear()
	return ""


## Round-trip time to a player, in local (ENet) mode. Steam doesn't report it here yet.
func _ping_text(player_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var peer_id: int = _net.get_peer_id(player_id)
	if enet == null or peer_id == 0 or peer_id == multiplayer.get_unique_id():
		return ""
	var target: int = peer_id if _net.is_host() else 1
	var packet_peer: ENetPacketPeer = enet.get_peer(target)
	if packet_peer == null:
		return ""
	return " ping %d ms" % int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## Where `spawn` puts things for this player: the surface they look at (lifted a bit), or a few
## metres ahead.
func _spawn_point(player_id: int) -> Transform3D:
	var body: PlayerCharacter = PlayerCharacter.find(player_id)
	if body == null:
		return Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	var origin: Vector3 = body.get_aim_origin()
	var direction: Vector3 = body.get_aim_direction()
	var point: Vector3 = origin + direction * SPAWN_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * SPAWN_REACH,
		PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS))
	query.exclude = [body.get_rid()]
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		point = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * SPAWN_LIFT
	return Transform3D(Basis.IDENTITY, point)


## Spread `count` spawned things in a little grid around a point (for spawners that want it).
static func spread(at: Transform3D, index: int) -> Transform3D:
	var row: int = floori(float(index) / 4.0)
	var column: int = index % 4
	return at.translated(Vector3((float(column) - 1.5) * SPAWN_SPREAD, float(row) * SPAWN_SPREAD, 0.0))


# --- The console window -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.DEBUG_CONSOLE):
		set_open(not is_open())
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(InputActions.PAUSE):
		set_open(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _fps_on:
		_fps_label.text = "%d fps" % Engine.get_frames_per_second()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.custom_minimum_size = Vector2(0, 320)
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_output = RichTextLabel.new()
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 270)
	column.add_child(_output)
	_input = LineEdit.new()
	_input.placeholder_text = "Type a command (help for the list). ` or Esc closes."
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_key)
	column.add_child(_input)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-90, 8)
	_fps_label.visible = false
	add_child(_fps_label)


func _on_submitted(text: String) -> void:
	_input.clear()
	if text.strip_edges().is_empty():
		return
	print_line("> " + text)
	_add_history(text)
	var result: String = run(text)
	if not result.is_empty():
		print_line(result)


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_QUOTELEFT:
		# The open/close key: don't type it into the box.
		_input.accept_event()
		set_open(false)
		return
	if _history.is_empty():
		return
	if key.keycode == KEY_UP:
		_history_index = clampi(_history_index - 1, 0, _history.size() - 1)
	elif key.keycode == KEY_DOWN:
		_history_index = clampi(_history_index + 1, 0, _history.size() - 1)
	else:
		return
	_input.text = _history[_history_index]
	_input.caret_column = _input.text.length()
	_input.accept_event()


func _add_history(text: String) -> void:
	if _history.is_empty() or _history[_history.size() - 1] != text:
		_history.append(text)
	if _history.size() > MAX_HISTORY:
		_history = _history.slice(_history.size() - MAX_HISTORY)
	_history_index = _history.size()
	var file := FileAccess.open(HISTORY_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_history))


func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_FILE):
		return
	_history = FileAccess.get_file_as_string(HISTORY_FILE).split("\n", false)
	_history_index = _history.size()
