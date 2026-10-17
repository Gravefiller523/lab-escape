class_name NetService
extends Node
## Autoload "Net". Who is playing (the roster), host/client helpers, joining rules, disconnects
## and reconnects, and each player's PlayerRecord for the current run.
##
## Works in solo with no setup: is_host() is true and the roster holds just you.
## Players can join mid-run: they are marked "waiting for the next floor" (spectating) until the
## next floor starts loading. Spec: docs/systems/net_core.md.

## The roster (who is connected) changed on this PC.
signal roster_changed()
## A synced record field changed on this PC. field is &"" when the whole record changed.
signal record_changed(player_id: int, field: StringName)
## We were a client and the host turned us away (game full, joining closed, kicked).
signal join_refused(reason: String)

const REFUSE_FULL: String = "The game is full."
const REFUSE_CLOSED: String = "The host isn't letting anyone join right now."
const REFUSE_DUPLICATE: String = "You are already in this game."
const REFUSE_UNKNOWN: String = "The host couldn't check who you are."
const REFUSE_KICKED: String = "You were removed from the game."
## Seconds between telling a refused peer why and disconnecting them, so the message arrives first.
const REFUSE_DISCONNECT_DELAY: float = 0.5

var _config: GameConfig
## The network connection we last saw, so we notice when steam_session swaps it.
var _peer_seen: MultiplayerPeer
## player_id -> record. On the host: the truth. On clients: copies from the host.
var _records: Dictionary[int, PlayerRecord] = {}
## Player ids in join order, including disconnected players who still have a record.
var _order: Array[int] = []
var _peer_by_player: Dictionary[int, int] = {}
var _player_by_peer: Dictionary[int, int] = {}
var _joining_open: bool = true
var _run_active: bool = false
## Local mode only: our player id, kept for later connections so reconnecting works on one PC.
var _local_identity: int = 0
## Our own player id while we are the host (0 as a client).
var _host_self_id: int = 0


## For tests only: use a custom config. Call before adding the node to the tree.
func use_config(config: GameConfig) -> void:
	_config = config


func _ready() -> void:
	if _config == null:
		_config = Config.game
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.floor_loading.connect(_on_floor_loading)
	_reset_session()


func _process(_delta: float) -> void:
	# steam_session sets and clears the connection; when it changes, start a fresh roster.
	if multiplayer.multiplayer_peer != _peer_seen:
		_reset_session()


# --- Helpers every system uses -----------------------------------------------------------------

## True on the host, and in solo.
func is_host() -> bool:
	return multiplayer.is_server()


## False in solo (no lobby and no connection).
func is_online() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


func local_player_id() -> int:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer is SteamMultiplayerPeer:
		return SteamSession.get_local_steam_id()
	if not is_online():
		return SteamSession.get_local_steam_id() if SteamSession.is_steam_running() else 1
	if is_host():
		return multiplayer.get_unique_id()
	return _local_identity if _local_identity != 0 else multiplayer.get_unique_id()


## Connected players in join order. Loop over this; never assume 4 players.
func get_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for player_id: int in _order:
		if _records[player_id].connected:
			ids.append(player_id)
	return ids


func get_player_count() -> int:
	return get_player_ids().size()


## Every player with a record, in join order, including players who dropped mid-run.
func get_record_ids() -> Array[int]:
	return _order.duplicate()


## The Godot network peer id for a player. 0 if not connected.
func get_peer_id(player_id: int) -> int:
	return _peer_by_player.get(player_id, 0)


func get_player_id_for_peer(peer_id: int) -> int:
	return _player_by_peer.get(peer_id, 0)


## Inside an RPC handler: the player who sent it. 0 if unknown.
func sender_player_id() -> int:
	return get_player_id_for_peer(multiplayer.get_remote_sender_id())


func get_display_name(player_id: int) -> String:
	var record: PlayerRecord = _records.get(player_id)
	return record.display_name if record != null else ""


## 0 to max_players - 1, stable for the session. -1 if unknown.
func get_slot_index(player_id: int) -> int:
	var record: PlayerRecord = _records.get(player_id)
	return record.slot_index if record != null else -1


## Host: the truth. Clients: a read-only copy. Null if there is no such player.
func get_record(player_id: int) -> PlayerRecord:
	return _records.get(player_id)


## Host only. Changes one record field and sends it to every client.
func update_record(player_id: int, field: StringName, value: Variant) -> void:
	if not is_host():
		push_error("Net.update_record: only the host can change records.")
		return
	var record: PlayerRecord = _records.get(player_id)
	if record == null:
		push_error("Net.update_record: no record for player %d." % player_id)
		return
	if not record.to_dict().has(String(field)):
		push_error("Net.update_record: PlayerRecord has no field '%s'." % field)
		return
	record.apply_dict({String(field): value})
	_send_record(player_id, field)
	record_changed.emit(player_id, field)


## Host only. Open by default, also during runs.
func set_joining_open(open: bool) -> void:
	if is_host():
		_joining_open = open


func is_joining_open() -> bool:
	return _joining_open


## Between run_started and run_ended.
func is_run_active() -> bool:
	return _run_active


## True for a player who joined mid-run and is spectating until the next floor.
func is_waiting_for_next_floor(player_id: int) -> bool:
	var record: PlayerRecord = _records.get(player_id)
	return record != null and record.waiting_for_next_floor


func get_waiting_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for player_id: int in get_player_ids():
		if _records[player_id].waiting_for_next_floor:
			ids.append(player_id)
	return ids


## Host only.
func set_waiting_for_next_floor(player_id: int, waiting: bool) -> void:
	update_record(player_id, &"waiting_for_next_floor", waiting)


## Host only. Forgets disconnected players and resets everyone's run progress
## (alive, not waiting, no upgrades). Outfits are kept.
func clear_run_records() -> void:
	if not is_host():
		return
	for player_id: int in _order.duplicate():
		var record: PlayerRecord = _records[player_id]
		if not record.connected:
			_order.erase(player_id)
			_records.erase(player_id)
			continue
		record.is_alive = true
		record.waiting_for_next_floor = false
		record.upgrade_ids.clear()
	_receive_roster.rpc(_roster_to_dict())
	roster_changed.emit()


## Host only. Removes a player from the game.
func kick(player_id: int) -> void:
	if not is_host() or player_id == local_player_id():
		return
	var peer_id: int = get_peer_id(player_id)
	if peer_id != 0:
		_refuse(peer_id, REFUSE_KICKED)


# --- Session start and end ---------------------------------------------------------------------

## Starts a fresh roster for the current connection. As host (and in solo) the roster is just us;
## as a client it stays empty until the host sends it.
func _reset_session() -> void:
	_peer_seen = multiplayer.multiplayer_peer
	# A host keeps its own run progress when its connection changes (e.g. solo, then hosting a lobby).
	var old_self: PlayerRecord = _records.get(_host_self_id) if _host_self_id != 0 else null
	_host_self_id = 0
	var old_ids: Array[int] = get_player_ids()
	_records.clear()
	_order.clear()
	_peer_by_player.clear()
	_player_by_peer.clear()
	var new_self_id: int = 0
	if is_host():
		var record := PlayerRecord.new()
		if old_self != null:
			record.apply_dict(old_self.to_dict())
		record.player_id = local_player_id()
		record.display_name = SteamSession.get_persona_name(record.player_id)
		record.slot_index = 0
		record.connected = true
		_add_record(record, multiplayer.get_unique_id())
		new_self_id = record.player_id
		_host_self_id = new_self_id
	else:
		# As a client, the host sends these with the roster.
		_run_active = false
		_joining_open = true
	for player_id: int in old_ids:
		if player_id != new_self_id:
			EventBus.player_left.emit(player_id)
	if new_self_id != 0 and not old_ids.has(new_self_id):
		EventBus.player_joined.emit(new_self_id)
	roster_changed.emit()


func _add_record(record: PlayerRecord, peer_id: int) -> void:
	_records[record.player_id] = record
	if not _order.has(record.player_id):
		_order.append(record.player_id)
	_peer_by_player[record.player_id] = peer_id
	_player_by_peer[peer_id] = record.player_id


func _on_connected_to_server() -> void:
	if _local_identity == 0:
		_local_identity = multiplayer.get_unique_id()
	var player_id: int = local_player_id()
	_hello.rpc_id(1, player_id, SteamSession.get_persona_name(player_id))


# --- Host: joining, leaving, reconnecting -----------------------------------------------------

## Client -> host, once connected: "this is who I am".
@rpc("any_peer", "call_local", "reliable")
func _hello(claimed_player_id: int, claimed_name: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if not is_host() or sender == multiplayer.get_unique_id() or _player_by_peer.has(sender):
		return
	var player_id: int = claimed_player_id
	var display_name: String = claimed_name
	if multiplayer.multiplayer_peer is SteamMultiplayerPeer:
		# Over Steam, trust Steam, not the message.
		player_id = SteamSession.get_steam_id_for_peer(sender)
		display_name = SteamSession.get_persona_name(player_id)
	if player_id <= 0:
		_refuse(sender, REFUSE_UNKNOWN)
		return

	var record: PlayerRecord = _records.get(player_id)
	if record != null and record.connected:
		_refuse(sender, REFUSE_DUPLICATE)
		return
	if record != null:
		_reconnect(record, sender)
		return
	if not _joining_open:
		_refuse(sender, REFUSE_CLOSED)
		return
	if _records.size() >= _config.max_players:
		_refuse(sender, REFUSE_FULL)
		return

	record = PlayerRecord.new()
	record.player_id = player_id
	record.display_name = display_name
	record.slot_index = _free_slot()
	record.connected = true
	record.waiting_for_next_floor = _run_active
	_add_record(record, sender)
	_receive_roster.rpc_id(sender, _roster_to_dict())
	_send_record(player_id, &"")
	EventBus.player_joined.emit(player_id)
	roster_changed.emit()


func _reconnect(record: PlayerRecord, peer_id: int) -> void:
	record.connected = true
	_add_record(record, peer_id)
	_receive_roster.rpc_id(peer_id, _roster_to_dict())
	_send_record(record.player_id, &"connected")
	EventBus.player_reconnected.emit(record.player_id)
	roster_changed.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	# steam_session says goodbye while the game quits; by then we may already be out of the tree.
	if not is_inside_tree():
		return
	var player_id: int = _player_by_peer.get(peer_id, 0)
	_player_by_peer.erase(peer_id)
	if player_id == 0:
		return
	_peer_by_player.erase(player_id)
	if is_host():
		var keep: bool = _run_active
		_mark_left(player_id, keep)
		_player_left_remote.rpc(player_id, keep)
	elif _records.has(player_id):
		# The host will tell us whether the record is kept; for now just show them gone.
		_records[player_id].connected = false
	EventBus.player_left.emit(player_id)
	roster_changed.emit()


func _mark_left(player_id: int, keep_record: bool) -> void:
	_peer_by_player.erase(player_id)
	if keep_record and _records.has(player_id):
		_records[player_id].connected = false
	else:
		_records.erase(player_id)
		_order.erase(player_id)


## Lowest slot index no record is using.
func _free_slot() -> int:
	var used: Array[int] = []
	for record: PlayerRecord in _records.values():
		used.append(record.slot_index)
	for slot: int in _config.max_players:
		if not used.has(slot):
			return slot
	return _records.size()


func _refuse(peer_id: int, reason: String) -> void:
	_refused.rpc_id(peer_id, reason)
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	get_tree().create_timer(REFUSE_DISCONNECT_DELAY).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer == peer and multiplayer.get_peers().has(peer_id):
			peer.disconnect_peer(peer_id))


func _on_run_started(_run_seed: int) -> void:
	clear_run_records()
	_run_active = true


func _on_run_ended(_result: StringName) -> void:
	_run_active = false
	clear_run_records()


## The next floor is loading: mid-run joiners stop waiting and spawn with everyone.
func _on_floor_loading(_floor_number: int, _department_id: StringName) -> void:
	if not is_host():
		return
	for player_id: int in get_waiting_player_ids():
		set_waiting_for_next_floor(player_id, false)


# --- Syncing to clients ------------------------------------------------------------------------

func _roster_to_dict() -> Dictionary:
	var records: Array[Dictionary] = []
	for player_id: int in _order:
		records.append(_records[player_id].to_dict())
	return {
		"records": records,
		"peers": _peer_by_player.duplicate(),
		"run_active": _run_active,
		"joining_open": _joining_open,
	}


func _send_record(player_id: int, field: StringName) -> void:
	_receive_record.rpc(_records[player_id].to_dict(), get_peer_id(player_id), field)


## Host -> client: the whole roster (when joining, and after records are cleared).
@rpc("authority", "call_local", "reliable")
func _receive_roster(data: Dictionary) -> void:
	if is_host():
		return
	var old_ids: Array[int] = get_player_ids()
	var old_records: Dictionary[int, PlayerRecord] = _records.duplicate()
	_records.clear()
	_order.clear()
	_peer_by_player.clear()
	_player_by_peer.clear()
	var records: Array = data.get("records", [])
	var peers: Dictionary = data.get("peers", {})
	for record_data: Dictionary in records:
		var player_id: int = int(record_data.get("player_id", 0))
		# Keep the same PlayerRecord object when we already had one, so references stay valid.
		var record: PlayerRecord = old_records.get(player_id, PlayerRecord.new())
		record.apply_dict(record_data)
		_records[player_id] = record
		_order.append(player_id)
		if peers.has(player_id):
			_peer_by_player[player_id] = int(peers[player_id])
			_player_by_peer[int(peers[player_id])] = player_id
	_run_active = bool(data.get("run_active", false))
	_joining_open = bool(data.get("joining_open", true))
	var new_ids: Array[int] = get_player_ids()
	for player_id: int in old_ids:
		if not new_ids.has(player_id):
			EventBus.player_left.emit(player_id)
	for player_id: int in new_ids:
		if not old_ids.has(player_id):
			EventBus.player_joined.emit(player_id)
	for player_id: int in new_ids:
		record_changed.emit(player_id, &"")
	roster_changed.emit()


## Host -> clients: one record changed (or a player joined or reconnected).
@rpc("authority", "call_local", "reliable")
func _receive_record(record_data: Dictionary, peer_id: int, field: StringName) -> void:
	if is_host():
		return
	var player_id: int = int(record_data.get("player_id", 0))
	var record: PlayerRecord = _records.get(player_id)
	var was_connected: bool = record != null and record.connected
	if record == null:
		record = PlayerRecord.new()
		_records[player_id] = record
		_order.append(player_id)
	record.apply_dict(record_data)
	if peer_id != 0:
		_peer_by_player[player_id] = peer_id
		_player_by_peer[peer_id] = player_id
	if record.connected and not was_connected:
		if field == &"connected":
			EventBus.player_reconnected.emit(player_id)
		else:
			EventBus.player_joined.emit(player_id)
		roster_changed.emit()
	record_changed.emit(player_id, field)


## Host -> clients: a player left. keep_record is true during a run.
@rpc("authority", "call_local", "reliable")
func _player_left_remote(player_id: int, keep_record: bool) -> void:
	if is_host():
		return
	var was_connected: bool = _records.has(player_id) and _records[player_id].connected
	_mark_left(player_id, keep_record)
	if was_connected:
		EventBus.player_left.emit(player_id)
	roster_changed.emit()


## Host -> one client: you can't join (or were kicked). We leave the lobby ourselves.
@rpc("authority", "call_local", "reliable")
func _refused(reason: String) -> void:
	if is_host():
		return
	join_refused.emit(reason)
	SteamSession.leave_lobby()
	if is_online():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
