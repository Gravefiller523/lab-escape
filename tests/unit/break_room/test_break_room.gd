extends GutTest
## Tests for break_room (docs/systems/break_room.md). Each "PC" is a SubViewport with its own
## multiplayer, physics, Net and Break Room, connected over real ENet.

const PORT: int = 17950
const WAIT: float = 5.0
const BREAK_ROOM_SCENE: PackedScene = preload("res://systems/break_room/break_room.tscn")

var _pcs: Array[Node] = []


func _make_pc(config: GameConfig) -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	var room := BREAK_ROOM_SCENE.instantiate() as BreakRoom
	room.use_net(net, config)
	pc.add_child(room)
	_pcs.append(pc)
	return pc


func _config(max_players: int = 4, afk_seconds: float = 60.0) -> GameConfig:
	var config := GameConfig.new()
	config.max_players = max_players
	config.afk_force_start_after = afk_seconds
	return config


func _room(pc: Node) -> BreakRoom:
	return pc.get_node("BreakRoom") as BreakRoom


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _body(pc: Node, player_id: int) -> PlayerCharacter:
	return pc.get_node_or_null("BreakRoom/%d" % player_id) as PlayerCharacter


func _host(config: GameConfig) -> Node:
	var pc := _make_pc(config)
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_server(PORT, 32), OK)
	pc.multiplayer.multiplayer_peer = peer
	return pc


func _client(config: GameConfig) -> Node:
	var pc := _make_pc(config)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	pc.multiplayer.multiplayer_peer = peer
	return pc


## Puts a body (controlled by this PC) inside the elevator.
func _walk_into_elevator(pc: Node, player_id: int) -> void:
	var body: PlayerCharacter = _body(pc, player_id)
	var zone: Area3D = _room(pc).get_elevator_zone()
	body.global_position = Vector3(zone.global_position.x, 0.1, zone.global_position.z)


## Stands a body about a metre in front of something usable (path inside the Break Room), on the room side.
func _walk_to(pc: Node, player_id: int, use_body: String) -> void:
	var target := pc.get_node("BreakRoom/" + use_body) as Node3D
	var spot: Vector3 = target.global_position
	spot.x -= signf(spot.x) * 1.0
	_body(pc, player_id).global_position = Vector3(spot.x, 0.1, spot.z)


## What pressing E while looking at it does (through the player's InteractionController).
func _use(pc: Node, player_id: int, use_body: String) -> bool:
	var controller: InteractionController = InteractionService.controller_of(_body(pc, player_id))
	return controller.press_use(pc.get_node("BreakRoom/" + use_body) as Node3D)


func after_each() -> void:
	var paths: Array[NodePath] = []
	var peers: Array[MultiplayerPeer] = []
	for pc: Node in _pcs:
		paths.append(pc.get_path())
		peers.append(pc.multiplayer.multiplayer_peer)
		pc.free()
	for index: int in paths.size():
		if peers[index] != null:
			peers[index].close()
		get_tree().set_multiplayer(null, paths[index])
	_pcs.clear()


func test_enough_spawn_points_for_max_players() -> void:
	var pc := _make_pc(_config(8))
	assert_gte(_room(pc).get_spawn_points().size(), 8)
	var big := _make_pc(_config(12))
	assert_gte(_room(big).get_spawn_points().size(), 12, "extra points are added when max_players grows")


func test_solo_player_spawns_in_the_room() -> void:
	var pc := _make_pc(_config())
	var me: int = _net(pc).local_player_id()
	await wait_until(func() -> bool: return _body(pc, me) != null, WAIT)
	assert_not_null(_body(pc, me))


func test_start_accepted_when_all_inside() -> void:
	var pc := _make_pc(_config())
	var me: int = _net(pc).local_player_id()
	await wait_until(func() -> bool: return _body(pc, me) != null, WAIT)
	_walk_into_elevator(pc, me)
	await wait_physics_frames(5)
	watch_signals(EventBus)
	_room(pc).request_start()
	assert_signal_emitted(EventBus, "elevator_start_accepted")


func test_start_refused_if_someone_outside() -> void:
	var host := _host(_config())
	var client := _client(_config())
	var host_id: int = _net(host).local_player_id()
	await wait_until(func() -> bool: return _net(client).local_player_id() != 0 and _body(client, _net(client).local_player_id()) != null, WAIT)
	var client_id: int = _net(client).local_player_id()
	await wait_until(func() -> bool: return _body(host, client_id) != null, WAIT)
	_walk_into_elevator(host, host_id)
	await wait_physics_frames(5)

	watch_signals(EventBus)
	_room(host).request_start()
	assert_signal_not_emitted(EventBus, "elevator_start_accepted", "client is still outside")
	assert_eq(_room(host).get_elevator_zone().get_missing_players(), [client_id] as Array[int])

	_walk_into_elevator(client, client_id)
	await wait_until(func() -> bool: return _room(host).get_elevator_zone().contains_all_players(), WAIT)
	_room(host).request_start()
	assert_signal_emitted(EventBus, "elevator_start_accepted", "everyone inside now")


func test_force_start_only_after_timer_and_only_host() -> void:
	var host := _host(_config(4, 0.3))
	var client := _client(_config(4, 0.3))
	var host_id: int = _net(host).local_player_id()
	await wait_until(func() -> bool: return _body(client, _net(client).local_player_id()) != null, WAIT)
	var client_id: int = _net(client).local_player_id()
	await wait_until(func() -> bool: return _body(host, client_id) != null, WAIT)
	_walk_into_elevator(host, host_id)
	await wait_physics_frames(5)
	assert_false(_room(host).can_force_start(), "not before the timer")

	await wait_seconds(0.5)
	assert_true(_room(host).can_force_start(), "host may force start after the timer")
	assert_false(_room(client).can_force_start(), "clients never may")

	watch_signals(EventBus)
	_room(host).request_force_start()
	assert_signal_emitted(EventBus, "elevator_start_accepted")
	await wait_until(func() -> bool: return _room(host).get_elevator_zone().get_players_inside().has(client_id), WAIT)
	assert_true(_room(host).get_elevator_zone().get_players_inside().has(client_id), "the client was moved into the elevator")


func test_start_button_is_inside_the_elevator() -> void:
	var pc := _make_pc(_config())
	var me: int = _net(pc).local_player_id()
	await wait_until(func() -> bool: return _body(pc, me) != null, WAIT)
	_walk_to(pc, me, "StartButton/UseBody")
	await wait_physics_frames(5)
	assert_true(_room(pc).get_elevator_zone().get_players_inside().has(me), "next to the button = inside the elevator")
	watch_signals(EventBus)
	assert_true(_use(pc, me, "StartButton/UseBody"), "the start button is an Interactable")
	await wait_physics_frames(2)
	assert_signal_emitted(EventBus, "elevator_start_accepted", "using it there starts the elevator")


func test_start_anyway_button_is_inside_the_elevator() -> void:
	var host := _host(_config(4, 0.3))
	var client := _client(_config(4, 0.3))
	var host_id: int = _net(host).local_player_id()
	await wait_until(func() -> bool: return _body(client, _net(client).local_player_id()) != null, WAIT)
	var force_body := host.get_node("BreakRoom/ForceButton/UseBody") as CollisionObject3D
	assert_eq(force_body.collision_layer, 0, "hidden Start anyway can't be looked at")
	_walk_to(host, host_id, "ForceButton/UseBody")
	await wait_physics_frames(5)
	assert_true(_room(host).get_elevator_zone().get_players_inside().has(host_id))
	await wait_seconds(0.5)
	await wait_process_frames(2)
	assert_ne(force_body.collision_layer, 0, "it can be used once it shows")
	watch_signals(EventBus)
	_use(host, host_id, "ForceButton/UseBody")
	await wait_physics_frames(2)
	assert_signal_emitted(EventBus, "elevator_start_accepted", "host used Start anyway from inside")


func test_only_the_host_can_use_start_anyway() -> void:
	var host := _host(_config(4, 0.3))
	var client := _client(_config(4, 0.3))
	var host_id: int = _net(host).local_player_id()
	await wait_until(func() -> bool: return _body(client, _net(client).local_player_id()) != null, WAIT)
	var client_id: int = _net(client).local_player_id()
	await wait_until(func() -> bool: return _body(host, client_id) != null, WAIT)
	_walk_into_elevator(host, host_id)
	await wait_seconds(0.5)
	assert_true(_room(host).can_force_start())
	var force_use := host.get_node("BreakRoom/ForceButton/UseBody/ForceUse") as Interactable
	assert_false(force_use.allows(client_id), "a client's use is refused by the host")
	assert_true(force_use.allows(host_id))


func test_closet_note_goes_to_whoever_used_it() -> void:
	var host := _host(_config())
	var client := _client(_config())
	var host_id: int = _net(host).local_player_id()
	await wait_until(func() -> bool: return _body(client, _net(client).local_player_id()) != null, WAIT)
	_walk_to(host, host_id, "ClosetUseBody")
	await wait_physics_frames(10)
	_use(host, host_id, "ClosetUseBody")
	var host_sign := host.get_node("BreakRoom/MessageSign") as Label3D
	await wait_until(func() -> bool: return not host_sign.text.is_empty(), WAIT)
	assert_string_contains(host_sign.text, "Jacket closet")
	await wait_physics_frames(5)
	assert_eq((client.get_node("BreakRoom/MessageSign") as Label3D).text, "", "only the player who used it sees it")


func test_room_has_props_to_play_with() -> void:
	var pc := _make_pc(_config())
	await wait_until(func() -> bool: return _room(pc).get_prop_spawner().get_props().size() > 0, WAIT)
	assert_eq(_room(pc).get_prop_spawner().get_props().size(), 4, "one prop per FunProps marker")
	assert_eq(_room(pc).get_prop_spawner().get_props(&"prop_crate_heavy").size(), 1)
