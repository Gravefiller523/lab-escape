class_name SteamSessionService
extends Node
## Autoload "SteamSession". Starts Steam, makes and joins lobbies, invites friends, sets rich
## presence, and creates the network connection (the "peer") that Godot's multiplayer uses.
##
## It also has a **local mode** (ENet on 127.0.0.1, no Steam) so every system can test multiplayer
## with two Godot windows: SteamSession.host_local() in one, SteamSession.join_local() in the other.
##
## Spec: docs/systems/steam_session.md. Who is in the game and joining rules belong to net_core.

## We made a lobby and are now the host. In local mode lobby_id is LOCAL_LOBBY_ID.
signal lobby_created(lobby_id: int)
## We joined someone's lobby AND the network connection to the host is up, so RPCs work.
signal lobby_joined(lobby_id: int)
## Making or joining a lobby failed. reason is plain text that can be shown to the player.
signal lobby_join_failed(reason: String)
## We were a client and the host vanished (quit, crashed or left).
signal connection_lost()

## The pretend lobby id used in local mode (real Steam lobby ids are huge numbers).
const LOCAL_LOBBY_ID: int = 1
## Used when steam_appid.txt is missing. 480 is Steam's test game "Spacewar".
const DEFAULT_APP_ID: int = 480
const APP_ID_FILE: String = "res://steam_appid.txt"
const LAUNCH_ARG_CONNECT: String = "+connect_lobby"
## How long a local host keeps its connection open after saying goodbye (GOODBYE_POLLS x GOODBYE_POLL_MS).
const GOODBYE_POLLS: int = 5
const GOODBYE_POLL_MS: int = 10
## Rich presence text. "%s" parts are filled in from content display names.
const PRESENCE_BREAK_ROOM: String = "In the Break Room"
const PRESENCE_FLOOR: String = "%s, floor %d"
const PRESENCE_BOSS: String = "Fighting the %s"
## STUB until game_flow is merged: the value of GameFlow.State.BREAK_ROOM (docs/systems/game_flow.md).
## Swap for the real enum then.
const _GAME_STATE_BREAK_ROOM: int = 2

enum Mode { NONE, STEAM, LOCAL }

var _api: SteamApi
var _config: GameConfig
var _steam_ok: bool = false
var _mode: Mode = Mode.NONE
var _lobby_id: int = 0
var _is_host: bool = false
## Set while we wait for Steam to answer a create or join call.
var _pending_lobby: bool = false
var _avatars: Dictionary[int, Texture2D] = {}
var _avatars_requested: Dictionary[int, bool] = {}


## For tests only: use a fake Steam and a custom config. Call before adding the node to the tree.
func use_backend(api: SteamApi, config: GameConfig) -> void:
	_api = api
	_config = config


func _ready() -> void:
	if _config == null:
		_config = Config.game
	if _api == null:
		_api = SteamApi.new()
		# Headless runs (GUT tests, servers) never start Steam, so running tests doesn't show
		# you as "playing Spacewar" and works on PCs without Steam.
		if DisplayServer.get_name() != "headless":
			_steam_ok = _api.init(_read_app_id())
	else:
		_steam_ok = _api.init(_read_app_id())

	_api.lobby_created.connect(_on_steam_lobby_created)
	_api.lobby_entered.connect(_on_steam_lobby_entered)
	_api.join_requested.connect(_on_steam_join_requested)
	_api.lobby_member_changed.connect(_on_steam_lobby_member_changed)
	_api.avatar_loaded.connect(_on_steam_avatar_loaded)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.floor_ready.connect(_on_floor_ready)
	EventBus.boss_floor_started.connect(_on_boss_floor_started)
	EventBus.run_ended.connect(_on_run_ended)

	if _steam_ok:
		_join_from_launch_args.call_deferred()


func _exit_tree() -> void:
	if _mode != Mode.NONE:
		leave_lobby()


## True when Steam started and is logged in. False in headless runs and when Steam is closed.
func is_steam_running() -> bool:
	return _steam_ok


func is_local_mode() -> bool:
	return _mode == Mode.LOCAL


## Our Steam ID. In local mode it is our network peer id instead (host = 1, clients get a
## random number from ENet), which is only valid once connected.
func get_local_steam_id() -> int:
	if _mode == Mode.LOCAL or not _steam_ok:
		return multiplayer.get_unique_id()
	return _api.get_local_steam_id()


## Turns a Godot network peer id (from multiplayer.get_remote_sender_id() etc.) into a Steam ID.
## Returns 0 if unknown. In local mode the two are the same number.
func get_steam_id_for_peer(peer_id: int) -> int:
	if _mode == Mode.LOCAL:
		return peer_id
	if peer_id == multiplayer.get_unique_id():
		return get_local_steam_id()
	var peer := multiplayer.multiplayer_peer as SteamMultiplayerPeer
	if peer == null:
		return 0
	return peer.get_steam_id_for_peer_id(peer_id)


## Turns a Steam ID into a Godot network peer id. Returns 0 if that player isn't connected.
func get_peer_for_steam_id(steam_id: int) -> int:
	if _mode == Mode.LOCAL:
		return steam_id
	if steam_id == get_local_steam_id():
		return multiplayer.get_unique_id()
	var peer := multiplayer.multiplayer_peer as SteamMultiplayerPeer
	if peer == null:
		return 0
	return peer.get_peer_id_for_steam_id(steam_id)


func get_persona_name(steam_id: int) -> String:
	if _mode == Mode.LOCAL or not _steam_ok:
		return "Player %d" % steam_id
	return _api.get_persona_name(steam_id)


## May return null the first time; the picture is fetched and later calls return it.
## Always null in local mode.
func get_avatar(steam_id: int) -> Texture2D:
	if _avatars.has(steam_id):
		return _avatars[steam_id]
	if _steam_ok and _mode != Mode.LOCAL and not _avatars_requested.has(steam_id):
		_avatars_requested[steam_id] = true
		_api.request_avatar(steam_id)
	return null


## The most players a lobby allows (Config.game.max_players).
func get_lobby_max_members() -> int:
	return _config.max_players


## Makes a friends-only Steam lobby and becomes its host. Answers with lobby_created or lobby_join_failed.
func host_lobby() -> void:
	if not _steam_ok:
		lobby_join_failed.emit("Steam is not running.")
		return
	if not _can_start():
		return
	_pending_lobby = true
	_api.create_lobby(get_lobby_max_members())


## Joins a friend's Steam lobby. Answers with lobby_joined or lobby_join_failed.
func join_lobby(lobby_id: int) -> void:
	if not _steam_ok:
		lobby_join_failed.emit("Steam is not running.")
		return
	if not _can_start():
		return
	_pending_lobby = true
	_api.join_lobby(lobby_id)


## Leaves the lobby and closes the network connection. Safe to call when not in a lobby.
## If we were the host, every client gets connection_lost.
func leave_lobby() -> void:
	if _mode == Mode.STEAM and _lobby_id != 0:
		_api.leave_lobby(_lobby_id)
		_api.clear_rich_presence()
	_close_peer()


## 0 when not in a lobby. LOCAL_LOBBY_ID in local mode.
func get_lobby_id() -> int:
	return _lobby_id


## Steam IDs of everyone in our lobby, us included. In local mode: peer ids we are connected to
## (a client only sees itself and the host; net_core's roster is the full list).
func get_lobby_member_ids() -> Array[int]:
	var ids: Array[int] = []
	if _lobby_id == 0:
		return ids
	if _mode == Mode.STEAM:
		return _api.get_lobby_member_ids(_lobby_id)
	ids.append(multiplayer.get_unique_id())
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	return ids


## Host only. Lets friends join (or not). Lobbies stay joinable during runs (mid-run joining,
## decided 2026-10-17); use this to close a lobby, e.g. while the game is shutting down.
func set_lobby_joinable(joinable: bool) -> void:
	if _mode == Mode.STEAM and _is_host and _lobby_id != 0:
		_api.set_lobby_joinable(_lobby_id, joinable)


## Opens Steam's "invite a friend" window for our lobby. Does nothing without Steam.
func open_invite_overlay() -> void:
	if _mode == Mode.STEAM and _lobby_id != 0:
		_api.open_invite_overlay(_lobby_id)


## Text friends see next to our name in Steam. Key used: "status". Does nothing without Steam.
func set_rich_presence(key: String, value: String) -> void:
	if _steam_ok:
		_api.set_rich_presence(key, value)


## Testing without Steam: become the host of a local game on this PC.
func host_local(port: int = 7777) -> void:
	if not _can_start():
		return
	var peer := ENetMultiplayerPeer.new()
	var error: int = peer.create_server(port, maxi(1, _config.max_players - 1))
	if error != OK:
		lobby_join_failed.emit("Could not host on port %d (%s). Is another window already hosting?"
			% [port, error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	_mode = Mode.LOCAL
	_is_host = true
	_lobby_id = LOCAL_LOBBY_ID
	lobby_created.emit(_lobby_id)


## Testing without Steam: join a local game. Answers with lobby_joined or lobby_join_failed.
func join_local(address: String = "127.0.0.1", port: int = 7777) -> void:
	if not _can_start():
		return
	var peer := ENetMultiplayerPeer.new()
	var error: int = peer.create_client(address, port)
	if error != OK:
		lobby_join_failed.emit("Could not connect to %s:%d (%s)." % [address, port, error_string(error)])
		return
	multiplayer.multiplayer_peer = peer
	_mode = Mode.LOCAL
	_is_host = false
	_pending_lobby = true


func _can_start() -> bool:
	if _mode != Mode.NONE or _pending_lobby:
		lobby_join_failed.emit("Already in a lobby. Leave it first.")
		return false
	return true


func _close_peer() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and _is_host and enet.host != null:
		_say_goodbye(enet)
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_mode = Mode.NONE
	_is_host = false
	_lobby_id = 0
	_pending_lobby = false


## ENet's close() alone doesn't tell clients, so they would only notice after a long timeout.
## Sends each client a polite "disconnect" and keeps the connection running for a moment
## (a few dozen milliseconds) so it actually goes out.
func _say_goodbye(enet: ENetMultiplayerPeer) -> void:
	for client: ENetPacketPeer in enet.host.get_peers():
		client.peer_disconnect()
	for attempt: int in GOODBYE_POLLS:
		enet.poll()
		OS.delay_msec(GOODBYE_POLL_MS)


func _read_app_id() -> int:
	if not FileAccess.file_exists(APP_ID_FILE):
		return DEFAULT_APP_ID
	var text: String = FileAccess.get_file_as_string(APP_ID_FILE).strip_edges()
	return int(text) if text.is_valid_int() else DEFAULT_APP_ID


func _join_from_launch_args() -> void:
	var lobby_id: int = find_connect_lobby(OS.get_cmdline_args())
	if lobby_id == 0:
		lobby_id = find_connect_lobby(_api.get_launch_command_line().split(" ", false))
	if lobby_id != 0:
		join_lobby(lobby_id)


## Finds the number after "+connect_lobby" in launch arguments. 0 if there is none.
static func find_connect_lobby(args: PackedStringArray) -> int:
	for index: int in args.size() - 1:
		if args[index] == LAUNCH_ARG_CONNECT and args[index + 1].is_valid_int():
			return args[index + 1].to_int()
	return 0


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	_pending_lobby = false
	if result != SteamApi.RESULT_OK:
		lobby_join_failed.emit("Steam could not create a lobby (error %d)." % result)
		return
	var peer: MultiplayerPeer = _api.make_host_peer(lobby_id)
	if peer == null:
		_api.leave_lobby(lobby_id)
		lobby_join_failed.emit("Could not start the network connection.")
		return
	multiplayer.multiplayer_peer = peer
	_mode = Mode.STEAM
	_is_host = true
	_lobby_id = lobby_id
	_set_lobby_presence()
	set_rich_presence("status", PRESENCE_BREAK_ROOM)
	lobby_created.emit(lobby_id)


func _on_steam_lobby_entered(lobby_id: int, response: int) -> void:
	# Steam also sends this to the host right after it creates a lobby; that case is handled above.
	if _is_host or not _pending_lobby:
		return
	if response != SteamApi.ENTER_RESPONSE_SUCCESS:
		_pending_lobby = false
		lobby_join_failed.emit(_enter_response_text(response))
		return
	var peer: MultiplayerPeer = _api.make_client_peer(lobby_id)
	if peer == null:
		_pending_lobby = false
		_api.leave_lobby(lobby_id)
		lobby_join_failed.emit("Could not connect to the host.")
		return
	multiplayer.multiplayer_peer = peer
	_mode = Mode.STEAM
	_lobby_id = lobby_id
	# lobby_joined is emitted once the connection is up, in _on_connected_to_server.


func _on_steam_join_requested(lobby_id: int) -> void:
	if _lobby_id == lobby_id:
		return
	if _mode != Mode.NONE:
		leave_lobby()
	join_lobby(lobby_id)


func _on_steam_lobby_member_changed(lobby_id: int, steam_id: int, state: int) -> void:
	if lobby_id != _lobby_id or _is_host:
		return
	var gone: bool = (state & (SteamApi.MEMBER_LEFT | SteamApi.MEMBER_DISCONNECTED
		| SteamApi.MEMBER_KICKED | SteamApi.MEMBER_BANNED)) != 0
	if gone and steam_id == _api.get_lobby_owner(lobby_id):
		_lose_connection()


func _on_steam_avatar_loaded(steam_id: int, size: int, data: PackedByteArray) -> void:
	if size <= 0 or data.size() != size * size * 4:
		return
	var image: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	_avatars[steam_id] = ImageTexture.create_from_image(image)


func _on_connected_to_server() -> void:
	if not _pending_lobby:
		return
	_pending_lobby = false
	if _mode == Mode.LOCAL:
		_lobby_id = LOCAL_LOBBY_ID
	else:
		_set_lobby_presence()
		set_rich_presence("status", PRESENCE_BREAK_ROOM)
	lobby_joined.emit(_lobby_id)


func _on_connection_failed() -> void:
	if _mode == Mode.STEAM and _lobby_id != 0:
		_api.leave_lobby(_lobby_id)
	_close_peer()
	lobby_join_failed.emit("Could not connect to the host.")


func _on_server_disconnected() -> void:
	_lose_connection()


## Called once when the host goes away. Cleans up and tells listeners (game_flow → main menu).
func _lose_connection() -> void:
	if _mode == Mode.NONE or _is_host:
		return
	leave_lobby()
	connection_lost.emit()


## Lets friends see which game we are in and join it with "Join game" from their friends list.
func _set_lobby_presence() -> void:
	set_rich_presence("steam_player_group", str(_lobby_id))
	set_rich_presence("connect", "%s %d" % [LAUNCH_ARG_CONNECT, _lobby_id])


func _enter_response_text(response: int) -> String:
	match response:
		2:
			return "That lobby doesn't exist any more."
		4:
			return "That lobby is full."
		3:
			return "You aren't allowed to join that lobby."
		5:
			return "Steam had a problem joining the lobby."
		6:
			return "You are banned from that lobby."
		_:
			return "Could not join the lobby (Steam response %d)." % response


func _on_game_state_changed(_old_state: int, new_state: int) -> void:
	if new_state == _GAME_STATE_BREAK_ROOM:
		set_rich_presence("status", PRESENCE_BREAK_ROOM)


func _on_floor_ready(floor_number: int, department_id: StringName) -> void:
	set_rich_presence("status", PRESENCE_FLOOR % [_display_name(department_id), floor_number])


func _on_boss_floor_started(boss_id: StringName) -> void:
	set_rich_presence("status", PRESENCE_BOSS % _display_name(boss_id))


func _on_run_ended(_result: StringName) -> void:
	set_rich_presence("status", PRESENCE_BREAK_ROOM)


func _display_name(content_id: StringName) -> String:
	var data: ContentData = ContentRegistry.get_content(content_id)
	if data == null or data.display_name.is_empty():
		return String(content_id)
	return data.display_name
