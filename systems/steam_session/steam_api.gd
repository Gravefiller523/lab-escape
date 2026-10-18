class_name SteamApi
extends RefCounted
## The only script that talks to GodotSteam's `Steam` singleton directly.
##
## SteamSession calls these small functions instead of calling `Steam` itself. That way the GUT
## tests can swap in a fake version (tests/unit/steam_session/fake_steam_api.gd) and check what
## SteamSession asked Steam to do, without Steam running.
## Internal to steam_session: other systems use the SteamSession autoload instead.

## Steam answered a create_lobby() call. result is Steam's result code (1 = OK).
signal lobby_created(result: int, lobby_id: int)
## Steam answered a join_lobby() call (or put us in the lobby we just made).
## response is Steam's chat-room enter response (1 = success).
signal lobby_entered(lobby_id: int, response: int)
## Someone clicked "Join game" on us in their Steam friends list, or accepted our invite.
signal join_requested(lobby_id: int)
## Someone joined, left or disconnected from a lobby we are in. state is Steam's member state change.
signal lobby_member_changed(lobby_id: int, steam_id: int, state: int)
## An avatar picture we asked for has arrived (RGBA8 pixels, size x size).
signal avatar_loaded(steam_id: int, size: int, data: PackedByteArray)

## Steam's numbers for these, copied so the rest of the system doesn't need Steam to read them.
const RESULT_OK: int = 1
const ENTER_RESPONSE_SUCCESS: int = 1
const MEMBER_LEFT: int = 2
const MEMBER_DISCONNECTED: int = 4
const MEMBER_KICKED: int = 8
const MEMBER_BANNED: int = 16

var _connected: bool = false
## True when GodotSteam started Steam before the game window (exported builds, see project.godot
## [steam]): then we must run Steam's callbacks ourselves each frame.
var _started_early: bool = false


## Starts Steam. Returns true if Steam is running and logged in.
## Exported builds start Steam before the renderer (GodotSteam's "initialize on startup"), which
## the Steam overlay (Shift+Tab) needs; then this only checks that it worked.
func init(app_id: int) -> bool:
	var result: Dictionary = Steam.get_steam_init_result()
	var status: int = int(result.get("status", -1))
	_started_early = status == Steam.STEAM_API_INIT_RESULT_OK
	if not _started_early:
		result = Steam.steamInitEx(app_id, true)
		status = int(result.get("status", -1))
	if status != Steam.STEAM_API_INIT_RESULT_OK:
		print("SteamSession: Steam not started (%s)." % str(result.get("verbal", status)))
		return false
	if not _connected:
		_connected = true
		Steam.lobby_created.connect(_on_lobby_created)
		Steam.lobby_joined.connect(_on_lobby_joined)
		Steam.join_requested.connect(_on_join_requested)
		Steam.lobby_chat_update.connect(_on_lobby_chat_update)
		Steam.avatar_loaded.connect(_on_avatar_loaded)
	return true


func get_local_steam_id() -> int:
	return Steam.getSteamID()


func get_persona_name(steam_id: int) -> String:
	if steam_id == Steam.getSteamID():
		return Steam.getPersonaName()
	return Steam.getFriendPersonaName(steam_id)


func request_avatar(steam_id: int) -> void:
	Steam.getPlayerAvatar(Steam.AVATAR_MEDIUM, steam_id)


func create_lobby(max_members: int) -> void:
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_members)


func join_lobby(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)


func leave_lobby(lobby_id: int) -> void:
	Steam.leaveLobby(lobby_id)


func get_lobby_owner(lobby_id: int) -> int:
	return Steam.getLobbyOwner(lobby_id)


func get_lobby_member_ids(lobby_id: int) -> Array[int]:
	var ids: Array[int] = []
	for index: int in Steam.getNumLobbyMembers(lobby_id):
		ids.append(Steam.getLobbyMemberByIndex(lobby_id, index))
	return ids


func set_lobby_joinable(lobby_id: int, joinable: bool) -> void:
	Steam.setLobbyJoinable(lobby_id, joinable)


func open_invite_overlay(lobby_id: int) -> void:
	Steam.activateGameOverlayInviteDialog(lobby_id)


func set_rich_presence(key: String, value: String) -> void:
	Steam.setRichPresence(key, value)


func clear_rich_presence() -> void:
	Steam.clearRichPresence()


## The text after the game's .exe when Steam launched it (holds "+connect_lobby <id>").
func get_launch_command_line() -> String:
	return Steam.getLaunchCommandLine()


## A network connection for the lobby owner. Returns null if it could not be made.
func make_host_peer(lobby_id: int) -> MultiplayerPeer:
	var peer := SteamMultiplayerPeer.new()
	var error: int = peer.host_with_lobby(lobby_id)
	if error != OK:
		push_warning("SteamSession: host_with_lobby failed (%s)." % error_string(error))
		return null
	return peer


## A network connection to the lobby owner. Returns null if it could not be made.
func make_client_peer(lobby_id: int) -> MultiplayerPeer:
	var peer := SteamMultiplayerPeer.new()
	var error: int = peer.connect_to_lobby(lobby_id)
	if error != OK:
		push_warning("SteamSession: connect_to_lobby failed (%s)." % error_string(error))
		return null
	return peer


func _on_lobby_created(result: int, lobby_id: int) -> void:
	lobby_created.emit(result, lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	lobby_entered.emit(lobby_id, response)


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_requested.emit(lobby_id)


func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, state: int) -> void:
	lobby_member_changed.emit(lobby_id, changed_id, state)


func _on_avatar_loaded(steam_id: int, size: int, data: PackedByteArray) -> void:
	avatar_loaded.emit(steam_id, size, data)


## Call every frame: runs Steam's callbacks when Steam was started early (otherwise GodotSteam does it).
func run_callbacks() -> void:
	if _started_early:
		Steam.run_callbacks()
