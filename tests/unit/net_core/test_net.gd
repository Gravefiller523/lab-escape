extends GutTest
## Tests for net_core (docs/systems/net_core.md). Each "PC" is a node with its own multiplayer and
## its own Net, so several players can connect over real ENet inside one test.

const PORT: int = 17800
const WAIT: float = 5.0

var _pcs: Array[Node] = []


func _config(max_players: int = 4) -> GameConfig:
	var config := GameConfig.new()
	config.max_players = max_players
	return config


func _make_pc(config: GameConfig) -> NetService:
	var pc := Node.new()
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	# Each PC gets its own multiplayer. RPC paths are relative to it, so every Net is just "Net".
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	_pcs.append(pc)
	return net


func _host(config: GameConfig) -> NetService:
	var net := _make_pc(config)
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_server(PORT, 32), OK, "server started")
	net.multiplayer.multiplayer_peer = peer
	return net


func _join(net: NetService) -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	net.multiplayer.multiplayer_peer = peer


func _client(config: GameConfig) -> NetService:
	var net := _make_pc(config)
	_join(net)
	return net


## Leaves politely (like quitting the game), so the host notices straight away.
func _leave(net: NetService) -> void:
	var enet := net.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.host != null:
		for other: ENetPacketPeer in enet.host.get_peers():
			other.peer_disconnect()
		for attempt: int in 5:
			enet.poll()
			OS.delay_msec(10)
		enet.close()
	net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _count_is(net: NetService, count: int) -> Callable:
	return func() -> bool: return net.get_player_count() == count


func after_each() -> void:
	for pc: Node in _pcs:
		var net := pc.get_node("Net") as NetService
		if net.multiplayer.multiplayer_peer != null:
			net.multiplayer.multiplayer_peer.close()
			net.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		get_tree().set_multiplayer(null, pc.get_path())
		pc.queue_free()
	_pcs.clear()
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


func test_solo_is_host_with_one_player() -> void:
	var net := _make_pc(_config())
	assert_true(net.is_host())
	assert_false(net.is_online())
	assert_eq(net.get_player_count(), 1)
	var me: int = net.local_player_id()
	assert_eq(net.get_player_ids(), [me] as Array[int])
	assert_not_null(net.get_record(me))
	assert_eq(net.get_slot_index(me), 0)


func test_slot_indexes_unique_and_reused_after_leave() -> void:
	var host := _host(_config())
	var a := _client(_config())
	await wait_until(_count_is(host, 2), WAIT)
	var b := _client(_config())
	await wait_until(_count_is(host, 3), WAIT)
	var a_id: int = a.local_player_id()
	var b_id: int = b.local_player_id()
	assert_eq(host.get_slot_index(host.local_player_id()), 0)
	assert_eq(host.get_slot_index(a_id), 1)
	assert_eq(host.get_slot_index(b_id), 2)

	_leave(a)
	await wait_until(_count_is(host, 2), WAIT)
	assert_null(host.get_record(a_id), "outside a run, a leaver's record is removed")
	var c := _client(_config())
	await wait_until(_count_is(host, 3), WAIT)
	assert_eq(host.get_slot_index(c.local_player_id()), 1, "the free slot is reused")
	assert_eq(host.get_slot_index(b_id), 2, "others keep their slot")
	await wait_until(_count_is(c, 3), WAIT)
	assert_eq(c.get_slot_index(b_id), 2, "clients see the same slots")


func test_join_refused_when_closed() -> void:
	var host := _host(_config())
	host.set_joining_open(false)
	var client := _client(_config())
	watch_signals(client)
	await wait_for_signal(client.join_refused, WAIT)
	assert_signal_emitted(client, "join_refused")
	assert_eq(host.get_player_count(), 1)


func test_reconnect_restores_record() -> void:
	var host := _host(_config())
	var client := _client(_config())
	await wait_until(_count_is(host, 2), WAIT)
	var client_id: int = client.local_player_id()
	EventBus.run_started.emit(123)
	host.update_record(client_id, &"upgrade_ids", [&"mutation_fly"] as Array[StringName])
	await wait_until(func() -> bool: return client.get_record(client_id).upgrade_ids.size() == 1, WAIT)
	assert_eq(client.get_record(client_id).upgrade_ids, [&"mutation_fly"] as Array[StringName], "client copy synced")

	_leave(client)
	await wait_until(_count_is(host, 1), WAIT)
	assert_not_null(host.get_record(client_id), "during a run, the record is kept")
	assert_false(host.get_record(client_id).connected)

	watch_signals(EventBus)
	_join(client)
	await wait_until(_count_is(host, 2), WAIT)
	assert_eq(client.local_player_id(), client_id, "same player id after reconnecting")
	assert_true(host.get_record(client_id).connected)
	assert_eq(host.get_record(client_id).upgrade_ids, [&"mutation_fly"] as Array[StringName], "upgrades kept")
	assert_signal_emitted(EventBus, "player_reconnected")


func test_record_round_trips_to_dict() -> void:
	var record := PlayerRecord.new()
	record.player_id = 76561190000000001
	record.display_name = "Zach"
	record.slot_index = 3
	record.connected = false
	record.is_alive = false
	record.waiting_for_next_floor = true
	record.upgrade_ids = [&"mutation_fly", &"mutation_fly"] as Array[StringName]
	record.cosmetic_loadout = {&"head": &"cosmetic_hard_hat"}
	var copy := PlayerRecord.from_dict(record.to_dict())
	assert_eq(copy.to_dict(), record.to_dict())
	assert_eq(copy.upgrade_ids, record.upgrade_ids)


func test_roster_limit_follows_config() -> void:
	var host := _host(_config(8))
	var clients: Array[NetService] = []
	for index: int in 7:
		clients.append(_client(_config(8)))
	await wait_until(_count_is(host, 8), WAIT * 2)
	assert_eq(host.get_player_count(), 8, "8 players accepted")
	var ninth := _client(_config(8))
	watch_signals(ninth)
	await wait_for_signal(ninth.join_refused, WAIT)
	assert_signal_emitted_with_parameters(ninth, "join_refused", [NetService.REFUSE_FULL])
	assert_eq(host.get_player_count(), 8)


func test_mid_run_joiner_waits_for_next_floor() -> void:
	var host := _host(_config())
	EventBus.run_started.emit(456)
	assert_true(host.is_run_active())
	var client := _client(_config())
	await wait_until(_count_is(host, 2), WAIT)
	var client_id: int = client.local_player_id()
	assert_true(host.is_waiting_for_next_floor(client_id), "mid-run joiner is accepted and waits")
	assert_eq(host.get_waiting_player_ids(), [client_id] as Array[int])
	assert_false(host.is_waiting_for_next_floor(host.local_player_id()))
	await wait_until(func() -> bool: return client.is_waiting_for_next_floor(client_id), WAIT)
	assert_true(client.is_run_active(), "client knows a run is on")

	EventBus.floor_loading.emit(2, &"department_zoology")
	assert_false(host.is_waiting_for_next_floor(client_id), "spawns with everyone on the next floor")
	await wait_until(func() -> bool: return not client.is_waiting_for_next_floor(client_id), WAIT)
	assert_false(client.is_waiting_for_next_floor(client_id), "client copy synced")


func test_joiner_before_run_does_not_wait() -> void:
	var host := _host(_config())
	var client := _client(_config())
	await wait_until(_count_is(host, 2), WAIT)
	assert_false(host.is_waiting_for_next_floor(client.local_player_id()))
