extends GutTest
## Tests for break_room (docs/systems/break_room.md). Each "PC" is a SubViewport with its own
## multiplayer, physics and Net, the Break Room, a player spawner (at the room's spawn points) and a
## prop spawner, connected over real ENet. (CHANGED 2026-10-19: starting a run is the cargo lift's job;
## those tests are in tests/unit/cargo_lift.)

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
	var props := PropSpawner.new()
	props.name = "Props"
	props.use_net(net, config)
	pc.add_child(props)
	var room := BREAK_ROOM_SCENE.instantiate() as BreakRoom
	room.use_net(net, config, props)
	pc.add_child(room)
	var players := PlayerSpawner.new()
	players.name = "PlayerSpawner"
	players.use_net(net)
	players.spawn_points = room.get_spawn_points()
	room.add_child(players)
	_pcs.append(pc)
	return pc


func _config(max_players: int = 4) -> GameConfig:
	var config := GameConfig.new()
	config.max_players = max_players
	return config


func _room(pc: Node) -> BreakRoom:
	return pc.get_node("BreakRoom") as BreakRoom


func _props(pc: Node) -> PropSpawner:
	return pc.get_node("Props") as PropSpawner


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


func test_the_lift_bay_fits_the_cargo_lift() -> void:
	var pc := _make_pc(_config())
	await wait_physics_frames(3)
	var spot: Node3D = _room(pc).get_lift_spot()
	assert_not_null(spot)
	# The lift's gate is on its -z side: it must face into the room (towards +z).
	assert_gt((-spot.global_basis.z).z, 0.9, "the lift's doors face the room")
	var space: PhysicsDirectSpaceState3D = _room(pc).get_world_3d().direct_space_state
	var middle: Vector3 = spot.global_position + Vector3.UP * 1.5
	for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
		var query := PhysicsRayQueryParameters3D.create(middle, middle + direction * 10.0,
			PhysicsLayers.bit(PhysicsLayers.WORLD))
		var hit: Dictionary = space.intersect_ray(query)
		assert_false(hit.is_empty(), "the bay has a wall that way")
		var wall_at: Vector3 = hit["position"]
		assert_gt(middle.distance_to(wall_at), CargoLift.INSIDE.x / 2.0 + CargoLift.WALL, "room for the lift")


func test_closet_note_goes_to_whoever_used_it() -> void:
	var host := _host(_config())
	var client := _client(_config())
	var host_id: int = _net(host).local_player_id()
	await wait_until(func() -> bool: return _body(client, _net(client).local_player_id()) != null, WAIT)
	await wait_until(func() -> bool: return _body(host, host_id) != null, WAIT)
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
	await wait_until(func() -> bool: return _props(pc).get_props().size() > 0, WAIT)
	assert_eq(_props(pc).get_props().size(), 4, "one prop per FunProps marker")
	assert_eq(_props(pc).get_props(&"prop_crate_heavy").size(), 1)
