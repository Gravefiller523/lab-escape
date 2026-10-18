extends GutTest
## Spawning player bodies over real ENet (docs/systems/player.md). Each "PC" is a node with its own
## multiplayer, its own Net and a Players container with a PlayerSpawner, so node paths match.

const PORT: int = 17900
const WAIT: float = 5.0
const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")

var _pcs: Array[Node] = []


func _make_pc(max_players: int = 8) -> Node:
	# A SubViewport with its own 3D world gives each PC its own physics, so the host's copy of a
	# body and the client's own copy never bump into each other.
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var config := GameConfig.new()
	config.max_players = max_players
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	# A floor, so bodies stand still instead of falling forever.
	var world := Node3D.new()
	world.name = "World"
	pc.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	var players := Node3D.new()
	players.name = "Players"
	pc.add_child(players)
	var spawner := PlayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.use_net(net)
	players.add_child(spawner)
	_pcs.append(pc)
	return pc


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _bodies(pc: Node) -> Array[PlayerCharacter]:
	var bodies: Array[PlayerCharacter] = []
	for child: Node in pc.get_node("Players").get_children():
		var body := child as PlayerCharacter
		if body != null and not body.is_queued_for_deletion():
			bodies.append(body)
	return bodies


func _body_count_is(pc: Node, count: int) -> Callable:
	return func() -> bool: return _bodies(pc).size() == count


func _host() -> Node:
	var pc := _make_pc()
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_server(PORT, 32), OK)
	pc.multiplayer.multiplayer_peer = peer
	return pc


func _client() -> Node:
	var pc := _make_pc()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	pc.multiplayer.multiplayer_peer = peer
	return pc


## Leaves politely (like quitting the game), so the host notices straight away.
func _leave(pc: Node) -> void:
	var enet := pc.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		for other: ENetPacketPeer in enet.host.get_peers():
			other.peer_disconnect()
		for attempt: int in 5:
			if enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				break
			enet.poll()
			OS.delay_msec(10)
	pc.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func after_each() -> void:
	# Remove the whole PCs (bodies included) first, then their connections.
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
	EventBus.run_ended.emit(&"abandoned")
	await wait_process_frames(2)


func test_solo_spawns_own_body() -> void:
	var pc := _make_pc()
	await wait_until(_body_count_is(pc, 1), WAIT)
	var bodies: Array[PlayerCharacter] = _bodies(pc)
	assert_eq(bodies.size(), 1)
	assert_true(bodies[0].is_local())
	assert_eq(bodies[0].player_id, _net(pc).local_player_id())


func test_joining_player_gets_a_body_on_every_pc() -> void:
	var host := _host()
	var client := _client()
	await wait_until(_body_count_is(host, 2), WAIT)
	await wait_until(_body_count_is(client, 2), WAIT)
	assert_eq(_bodies(host).size(), 2)
	assert_eq(_bodies(client).size(), 2, "client sees both bodies")
	var client_id: int = _net(client).local_player_id()
	var on_client := client.get_node("Players/%d" % client_id) as PlayerCharacter
	var on_host := host.get_node("Players/%d" % client_id) as PlayerCharacter
	assert_true(on_client.is_local(), "the client controls its own body")
	assert_false(on_host.is_local(), "the host doesn't control the client's body")


func test_client_movement_reaches_host() -> void:
	var host := _host()
	var client := _client()
	await wait_until(_body_count_is(host, 2), WAIT)
	await wait_until(_body_count_is(client, 2), WAIT)
	var client_id: int = _net(client).local_player_id()
	var on_client := client.get_node("Players/%d" % client_id) as PlayerCharacter
	var on_host := host.get_node("Players/%d" % client_id) as PlayerCharacter
	on_client.global_position += Vector3(1.0, 0.0, 0.0)
	await wait_until(func() -> bool: return on_host.global_position.distance_to(on_client.global_position) < 0.1, WAIT)
	assert_almost_eq(on_host.global_position.x, on_client.global_position.x, 0.1, "host copy follows smoothly")


func test_host_pulls_back_impossible_moves() -> void:
	var host := _host()
	var client := _client()
	await wait_until(_body_count_is(host, 2), WAIT)
	await wait_until(_body_count_is(client, 2), WAIT)
	var client_id: int = _net(client).local_player_id()
	var on_client := client.get_node("Players/%d" % client_id) as PlayerCharacter
	await wait_physics_frames(10)
	var start: Vector3 = on_client.global_position
	on_client.global_position += Vector3(50.0, 0.0, 0.0)
	await wait_until(func() -> bool: return on_client.global_position.distance_to(start) < 2.0, WAIT)
	assert_lt(on_client.global_position.distance_to(start), 2.0, "teleported back by the host")


func test_leaving_player_body_is_removed() -> void:
	var host := _host()
	var client := _client()
	await wait_until(_body_count_is(host, 2), WAIT)
	_leave(client)
	await wait_until(_body_count_is(host, 1), WAIT)
	assert_eq(_bodies(host).size(), 1)


func test_mid_run_joiner_spawns_on_next_floor() -> void:
	var host := _host()
	await wait_until(_body_count_is(host, 1), WAIT)
	EventBus.run_started.emit(99)
	var client := _client()
	await wait_until(func() -> bool: return _net(host).get_player_count() == 2, WAIT)
	await wait_process_frames(10)
	assert_eq(_bodies(host).size(), 1, "waiting player has no body yet")
	await wait_until(_body_count_is(client, 1), WAIT)
	assert_eq(_bodies(client).size(), 1, "the waiting player still sees the host's body")

	EventBus.floor_loading.emit(2, &"department_zoology")
	EventBus.floor_ready.emit(2, &"department_zoology")
	await wait_until(_body_count_is(host, 2), WAIT)
	assert_eq(_bodies(host).size(), 2, "spawned with everyone on the next floor")
	await wait_until(_body_count_is(client, 2), WAIT)
	assert_eq(_bodies(client).size(), 2)


func test_eight_bodies_can_spawn() -> void:
	var pc := _make_pc()
	await wait_until(_body_count_is(pc, 1), WAIT)
	var spawner := pc.get_node("Players/PlayerSpawner") as PlayerSpawner
	# Seven more bodies next to ours (in solo every body belongs to this PC).
	var players := pc.get_node("Players") as Node3D
	for index: int in 7:
		var body := PLAYER_SCENE.instantiate() as PlayerCharacter
		body.player_id = 1000 + index
		body.name = str(body.player_id)
		body.position = Vector3(float(index) * 2.0, 0.0, 5.0)
		players.add_child(body)
	await wait_physics_frames(5)
	assert_eq(_bodies(pc).size(), 8)
	assert_not_null(spawner.get_body(1006))


func test_unloaded_level_spawns_nobody() -> void:
	# Like when the host leaves: the level is taken out of the tree while Net resets to solo.
	var pc := _make_pc()
	await wait_until(_body_count_is(pc, 1), WAIT)
	var players: Node = pc.get_node("Players")
	pc.remove_child(players)
	EventBus.player_joined.emit(_net(pc).local_player_id())
	assert_eq(players.get_child_count(), 2, "nothing new was spawned (the spawner and the old body only)")
	players.free()
