extends GutTest
## Tests for steam_session (docs/systems/steam_session.md). Steam itself is replaced by
## FakeSteamApi; local mode uses real ENet on this PC.

const PORT: int = 17777

var _sessions: Array[SteamSessionService] = []


## Makes a SteamSession with its own multiplayer, so two can talk to each other in one test.
func _make_session(fake: FakeSteamApi, config: GameConfig = null) -> SteamSessionService:
	var session := SteamSessionService.new()
	session.name = "Session%d" % _sessions.size()
	session.use_backend(fake, config if config != null else GameConfig.new())
	# The custom multiplayer must exist before the node's _ready, which connects to its signals.
	get_tree().set_multiplayer(SceneMultiplayer.new(), NodePath("%s/%s" % [get_path(), session.name]))
	add_child(session)
	_sessions.append(session)
	return session


func after_each() -> void:
	for session: SteamSessionService in _sessions:
		session.leave_lobby()
		get_tree().set_multiplayer(null, session.get_path())
		session.queue_free()
	_sessions.clear()
	await wait_process_frames(2)


func test_local_host_and_join_connect() -> void:
	var host := _make_session(FakeSteamApi.new())
	var client := _make_session(FakeSteamApi.new())
	watch_signals(host)
	watch_signals(client)
	var connected: Array[bool] = [false]
	client.multiplayer.connected_to_server.connect(func() -> void: connected[0] = true)

	host.host_local(PORT)
	assert_signal_emitted(host, "lobby_created")
	client.join_local("127.0.0.1", PORT)
	await wait_until(func() -> bool: return connected[0], 5.0)

	assert_true(connected[0], "client got connected_to_server")
	assert_signal_emitted(client, "lobby_joined")
	assert_true(host.is_local_mode() and client.is_local_mode())
	assert_eq(host.get_lobby_id(), SteamSessionService.LOCAL_LOBBY_ID)
	assert_eq(client.get_lobby_id(), SteamSessionService.LOCAL_LOBBY_ID)
	assert_eq(host.get_local_steam_id(), 1, "local host id is 1")
	await wait_until(func() -> bool: return host.get_lobby_member_ids().size() == 2, 2.0)
	assert_eq(host.get_lobby_member_ids().size(), 2, "host sees itself and the client")


func test_host_leaving_sends_connection_lost() -> void:
	var host := _make_session(FakeSteamApi.new())
	var client := _make_session(FakeSteamApi.new())
	watch_signals(client)
	host.host_local(PORT)
	client.join_local("127.0.0.1", PORT)
	await wait_for_signal(client.lobby_joined, 5.0)

	host.leave_lobby()
	await wait_for_signal(client.connection_lost, 5.0)

	assert_signal_emitted(client, "connection_lost")
	assert_eq(client.get_lobby_id(), 0, "client is out of the lobby")
	assert_false(client.is_local_mode())


func test_is_steam_running_false_without_steam() -> void:
	var fake := FakeSteamApi.new()
	fake.steam_available = false
	var session := _make_session(fake)
	watch_signals(session)

	assert_false(session.is_steam_running())
	session.host_lobby()
	assert_signal_emitted(session, "lobby_join_failed", "Steam lobby fails politely")
	assert_eq(fake.create_lobby_calls, 0, "Steam was never asked")
	assert_null(session.get_avatar(123))
	assert_eq(session.get_persona_name(5), "Player 5")

	session.host_local(PORT)
	assert_signal_emitted(session, "lobby_created", "local mode still works")
	assert_true(session.is_local_mode())


func test_lobby_size_uses_config() -> void:
	var config := GameConfig.new()
	config.max_players = 8
	var fake := FakeSteamApi.new()
	fake.steam_available = true
	var session := _make_session(fake, config)

	session.host_lobby()

	assert_eq(fake.create_lobby_calls, 1)
	assert_eq(fake.created_lobby_max_members, 8)


func test_second_host_while_in_lobby_is_refused() -> void:
	var session := _make_session(FakeSteamApi.new())
	watch_signals(session)
	session.host_local(PORT)
	session.host_local(PORT + 1)
	assert_signal_emit_count(session, "lobby_created", 1)
	assert_signal_emitted(session, "lobby_join_failed")


func test_connect_lobby_launch_argument() -> void:
	var args := PackedStringArray(["--foo", "+connect_lobby", "109775241000000001"])
	assert_eq(SteamSessionService.find_connect_lobby(args), 109775241000000001)
	assert_eq(SteamSessionService.find_connect_lobby(PackedStringArray(["+connect_lobby"])), 0)


func test_rich_presence_follows_floors() -> void:
	var fake := FakeSteamApi.new()
	fake.steam_available = true
	_make_session(fake)
	EventBus.floor_ready.emit(3, &"department_does_not_exist")
	var on_floor: String = fake.presence.get("status", "")
	assert_eq(on_floor, "department_does_not_exist, floor 3")
	EventBus.run_ended.emit(&"wiped")
	var after_run: String = fake.presence.get("status", "")
	assert_eq(after_run, SteamSessionService.PRESENCE_BREAK_ROOM)


func test_leaving_leaves_an_offline_peer() -> void:
	var session := _make_session(FakeSteamApi.new())
	session.host_local(PORT)
	session.leave_lobby()
	assert_not_null(session.multiplayer.multiplayer_peer, "never left with no peer (get_unique_id would error)")
	assert_true(session.multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	assert_eq(session.multiplayer.get_unique_id(), 1)


func test_client_leaving_is_noticed_by_host() -> void:
	var host := _make_session(FakeSteamApi.new())
	var client := _make_session(FakeSteamApi.new())
	host.host_local(PORT)
	client.join_local("127.0.0.1", PORT)
	await wait_for_signal(client.lobby_joined, 5.0)
	await wait_until(func() -> bool: return host.multiplayer.get_peers().size() == 1, 2.0)

	client.leave_lobby()
	await wait_until(func() -> bool: return host.multiplayer.get_peers().is_empty(), 2.0)

	assert_eq(host.multiplayer.get_peers().size(), 0, "host sees the client go straight away")
