class_name FakeSteamApi
extends SteamApi
## A pretend Steam for steam_session's GUT tests. It records what SteamSession asked for
## and never talks to the real Steam.

var steam_available: bool = false
var local_steam_id: int = 76561190000000001
var created_lobby_max_members: int = -1
var create_lobby_calls: int = 0
var joined_lobby_id: int = 0
var presence: Dictionary[String, String] = {}


func init(_app_id: int) -> bool:
	return steam_available


func get_local_steam_id() -> int:
	return local_steam_id


func get_persona_name(steam_id: int) -> String:
	return "Fake %d" % steam_id


func request_avatar(_steam_id: int) -> void:
	pass


func create_lobby(max_members: int) -> void:
	create_lobby_calls += 1
	created_lobby_max_members = max_members


func join_lobby(lobby_id: int) -> void:
	joined_lobby_id = lobby_id


func leave_lobby(_lobby_id: int) -> void:
	pass


func get_lobby_owner(_lobby_id: int) -> int:
	return 0


func get_lobby_member_ids(_lobby_id: int) -> Array[int]:
	return [local_steam_id] as Array[int]


func set_lobby_joinable(_lobby_id: int, _joinable: bool) -> void:
	pass


func open_invite_overlay(_lobby_id: int) -> void:
	pass


func set_rich_presence(key: String, value: String) -> void:
	presence[key] = value


func clear_rich_presence() -> void:
	presence.clear()


func get_launch_command_line() -> String:
	return ""


func make_host_peer(_lobby_id: int) -> MultiplayerPeer:
	return null


func make_client_peer(_lobby_id: int) -> MultiplayerPeer:
	return null
