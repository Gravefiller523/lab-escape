extends GutTest
## Tests for physics_props (docs/systems/physics_props.md). Each "PC" is a SubViewport with its own
## physics, multiplayer, Net, player spawner and prop spawner, so two can talk over real ENet.

const PORT: int = 18030
const WAIT: float = 5.0

var _pcs: Array[Node] = []


func _config() -> GameConfig:
	return GameConfig.new()


func _make_pc(config: GameConfig = null) -> Node:
	if config == null:
		config = _config()
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var net := NetService.new()
	net.name = "Net"
	net.use_config(config)
	pc.add_child(net)
	var level := Node3D.new()
	level.name = "Level"
	pc.add_child(level)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var players := Node3D.new()
	players.name = "Players"
	level.add_child(players)
	var player_spawner := PlayerSpawner.new()
	player_spawner.name = "PlayerSpawner"
	player_spawner.use_net(net)
	players.add_child(player_spawner)
	var props := PropSpawner.new()
	props.name = "Props"
	props.use_net(net, config)
	level.add_child(props)
	_pcs.append(pc)
	return pc


func _props(pc: Node) -> PropSpawner:
	return pc.get_node("Level/Props") as PropSpawner


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _body(pc: Node, player_id: int) -> PlayerCharacter:
	return pc.get_node_or_null("Level/Players/%d" % player_id) as PlayerCharacter


func _my_body(pc: Node) -> PlayerCharacter:
	return _body(pc, _net(pc).local_player_id())


## A prop right in front of a body's eyes, within reach.
func _in_front_of(body: PlayerCharacter) -> Transform3D:
	return Transform3D(Basis.IDENTITY, body.get_aim_origin() + body.get_aim_direction() * 1.4 + Vector3(0, -0.4, 0))


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


func test_spawn_assigns_unique_net_id() -> void:
	var pc := _make_pc()
	var a: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	var b: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(1, 1, -3)))
	var c: NetProp = _props(pc).spawn_prop(&"prop_lift_part_zoology", Transform3D(Basis.IDENTITY, Vector3(2, 1, -3)))
	assert_ne(a.net_id, b.net_id)
	assert_ne(b.net_id, c.net_id)
	assert_eq(_props(pc).get_prop(b.net_id), b)
	assert_eq(_props(pc).get_props(&"prop_crate").size(), 2)
	assert_almost_eq(a.mass, 10.0, 0.01, "mass comes from the content file")


func test_nothing_is_too_heavy() -> void:
	var pc := _make_pc()
	var heavy: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	heavy.mass = 300.0
	var refusal: Array[String] = []
	assert_eq(_props(pc).decide_grab(heavy, 1, refusal), [1] as Array[int], "even 300 kg can be grabbed")
	assert_true(refusal.is_empty())
	heavy.apply_holders([1] as Array[int], 1)
	assert_almost_eq(heavy.get_support(), 0.1, 0.001, "one person: 30 of 300 kg, it barely moves")


func test_walking_into_props_pushes_them_by_weight() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var body: PlayerCharacter = _my_body(pc)
	var moved: Array[float] = []
	for prop_id: StringName in [&"prop_crate", &"prop_crate_heavy"]:
		var crate: NetProp = _props(pc).spawn_prop(prop_id, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, -8)))
		await wait_physics_frames(10)
		var start: Vector3 = crate.global_position
		body.global_position = start + Vector3(0, -0.4, 1.5)
		body.rotation = Vector3.ZERO
		var walk := PlayerInputState.new()
		walk.move = Vector2(0, 1)
		body.set_input_override(walk)
		await wait_physics_frames(60)
		body.set_input_override(PlayerInputState.new())
		moved.append(start.distance_to(crate.global_position))
		_props(pc).despawn(crate)
		await wait_physics_frames(2)
	assert_gt(moved[0], 0.5, "a light crate gets pushed along")
	assert_gt(moved[1], 0.05, "the heavy crate moves a little")
	assert_lt(moved[1], moved[0], "but much less than the light one")


func test_newest_grab_takes_normal_prop() -> void:
	var pc := _make_pc()
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	var refusal: Array[String] = []
	crate.apply_holders(_props(pc).decide_grab(crate, 1, refusal), 1)
	assert_eq(crate.get_holder_ids(), [1] as Array[int])
	crate.apply_holders(_props(pc).decide_grab(crate, 2, refusal), 2)
	assert_eq(crate.get_holder_ids(), [2] as Array[int], "player 2 took it from player 1")
	assert_true(refusal.is_empty())


func test_every_grab_helps_lift_heavy_prop() -> void:
	var pc := _make_pc()
	var heavy: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	var refusal: Array[String] = []
	for player_id: int in [1, 2, 3, 4]:
		heavy.apply_holders(_props(pc).decide_grab(heavy, player_id, refusal), player_id)
	assert_eq(heavy.get_holder_ids(), [1, 2, 3, 4] as Array[int], "no limit on helpers")
	assert_true(refusal.is_empty())


func test_each_helper_carries_more_of_the_weight() -> void:
	var pc := _make_pc()
	var config: GameConfig = _props(pc).get_config()
	var heavy: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	heavy.apply_holders([1] as Array[int], 1)
	var one: float = heavy.get_support()
	assert_almost_eq(one, config.heavy_lift_per_holder / heavy.mass, 0.001, "1 person: a little")
	assert_false(heavy.is_lifted(), "1 person only drags it")
	heavy.apply_holders([1, 2] as Array[int], 2)
	var two: float = heavy.get_support()
	assert_gt(two, one, "2 people: more")
	heavy.apply_holders([1, 2, 3] as Array[int], 3)
	assert_true(heavy.is_lifted(), "3 people x 30 kg >= 80 kg: fully lifted")
	assert_almost_eq(heavy.gravity_scale, 0.0, 0.001)


func test_heavy_prop_moves_faster_with_more_helpers() -> void:
	var config: GameConfig = _config()
	var pc := _make_pc(config)
	var speeds: Array[float] = []
	for holders: int in [1, 2, 3]:
		var heavy: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(float(holders) * 4.0, 0.41, -3)))
		await wait_physics_frames(2)
		var ids: Array[int] = []
		for index: int in holders:
			ids.append(100 + index)
		heavy.apply_holders(ids, ids[0])
		var start: Vector3 = heavy.global_position
		for player_id: int in ids:
			heavy.set_hold_target(player_id, start + Vector3(0, 1.0, -5.0))
		await wait_physics_frames(20)
		speeds.append(heavy.global_position.distance_to(start))
		heavy.apply_holders([] as Array[int], 0)
	assert_lt(speeds[0], speeds[1], "2 people move it further than 1")
	assert_lt(speeds[1], speeds[2], "3 people move it further than 2")


func test_key_object_respawns_at_safe_spot() -> void:
	var pc := _make_pc()
	var start := Vector3(3, 1, -3)
	var part: NetProp = _props(pc).spawn_prop(&"prop_lift_part_zoology", Transform3D(Basis.IDENTITY, start))
	await wait_physics_frames(2)
	watch_signals(EventBus)
	part.global_position = Vector3(3, -80, -3)
	await wait_physics_frames(3)
	assert_gt(part.global_position.y, -10.0, "back in the level")
	assert_lt(part.global_position.distance_to(start), 2.0, "at its last safe spot")
	assert_signal_emitted(EventBus, "key_object_respawned")


func test_sleeping_props_not_sent() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 0.31, -3)))
	await wait_until(func() -> bool: return crate.sleeping, WAIT)
	assert_true(crate.sleeping, "it went to sleep")
	assert_eq(_props(pc).get_snapshot_batch(true).size(), 0, "sleeping props cost nothing")
	crate.apply_central_impulse(Vector3(0, 30, 0))
	await wait_physics_frames(2)
	assert_eq(_props(pc).get_snapshot_batch(true).size(), 1, "a moving prop is sent")


func test_attach_freezes_detach_restores() -> void:
	var pc := _make_pc()
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 1, -3)))
	var anchor := Node3D.new()
	pc.get_node("Level").add_child(anchor)
	anchor.global_position = Vector3(5, 2, -5)
	crate.attach_to(anchor)
	await wait_physics_frames(3)
	assert_true(crate.freeze)
	assert_true(crate.is_attached())
	assert_almost_eq(crate.global_position.distance_to(anchor.global_position), 0.0, 0.01, "follows the anchor")
	crate.detach()
	assert_false(crate.freeze)
	assert_false(crate.is_attached())


func test_grab_carries_and_throw_sets_last_holder() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var body: PlayerCharacter = _my_body(pc)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(10)
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate", _in_front_of(body))
	var grab: GrabController = PropsService.grab_of(body)
	grab.try_grab(crate)
	assert_eq(crate.get_holder_ids(), [body.player_id] as Array[int], "the host (us) confirmed the grab")
	await wait_physics_frames(30)
	var hold_point: Vector3 = body.get_aim_origin() + body.get_aim_direction() * _props(pc).get_config().hold_distance
	assert_lt(crate.global_position.distance_to(hold_point), 0.5, "carried at the hold point")
	grab.throw()
	await wait_physics_frames(2)
	assert_false(crate.is_held())
	assert_eq(crate.last_holder_id, body.player_id)
	assert_gt(crate.linear_velocity.length(), 1.0, "it flew")


func test_client_grab_goes_through_host_and_newest_grab_wins() -> void:
	var host := _make_pc()
	var client := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _my_body(client) != null and _body(host, _net(client).local_player_id()) != null, WAIT)
	var client_body: PlayerCharacter = _my_body(client)
	client_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(15)
	var crate_on_host: NetProp = _props(host).spawn_prop(&"prop_crate", _in_front_of(client_body))
	await wait_until(func() -> bool: return _props(client).get_prop(crate_on_host.net_id) != null, WAIT)
	var crate_on_client: NetProp = _props(client).get_prop(crate_on_host.net_id)

	PropsService.grab_of(client_body).try_grab(crate_on_client)
	await wait_until(func() -> bool: return crate_on_host.get_holder_ids().has(client_body.player_id), WAIT)
	assert_eq(crate_on_host.get_holder_ids(), [client_body.player_id] as Array[int], "the host gave it to the client")

	# The host player grabs the same crate: the newest grab takes it.
	var host_body: PlayerCharacter = _my_body(host)
	host_body.global_position = client_body.global_position + Vector3(1, 0, 0)
	await wait_physics_frames(2)
	PropsService.grab_of(host_body).try_grab(crate_on_host)
	assert_eq(crate_on_host.get_holder_ids(), [host_body.player_id] as Array[int])
	await wait_until(func() -> bool: return PropsService.grab_of(client_body).get_held() == null, WAIT)
	assert_null(PropsService.grab_of(client_body).get_held(), "the client let go")


func test_players_can_stand_on_props_and_bump_into_them() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var body: PlayerCharacter = _my_body(pc)
	body.set_input_override(PlayerInputState.new())
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(0, 0.41, -6)))
	await wait_physics_frames(10)
	# Drop the player onto the crate.
	body.global_position = crate.global_position + Vector3(0, 1.5, 0)
	await wait_physics_frames(40)
	assert_gt(body.global_position.y, crate.global_position.y + 0.3, "standing on top of it")

	# Walk into it from the side: blocked, not passing through.
	body.global_position = crate.global_position + Vector3(0, 0, 2.0)
	body.rotation = Vector3.ZERO
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	body.set_input_override(walk)
	await wait_physics_frames(60)
	assert_gt(body.global_position.z, crate.global_position.z, "the crate stopped the player")


func test_held_prop_stays_solid_but_standing_on_it_drops_it() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var body: PlayerCharacter = _my_body(pc)
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(5)
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate", _in_front_of(body))
	var grab: GrabController = PropsService.grab_of(body)
	grab.try_grab(crate)
	assert_false(crate.get_collision_exceptions().has(body), "a held prop still collides with its holder")
	# Put the player on top of the crate they hold: they drop it.
	body.global_position = crate.global_position + Vector3(0, 0.35, 0)
	await wait_until(func() -> bool: return grab.get_held() == null, WAIT)
	assert_null(grab.get_held(), "standing on what you hold makes you drop it")


func test_client_throw_flies_as_far_as_a_host_throw() -> void:
	var host := _make_pc()
	var client := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT + 4, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT + 4)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _my_body(client) != null, WAIT)
	var client_body: PlayerCharacter = _my_body(client)
	client_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(10)
	var crate_on_host: NetProp = _props(host).spawn_prop(&"prop_crate", _in_front_of(client_body))
	await wait_until(func() -> bool: return _props(client).get_prop(crate_on_host.net_id) != null, WAIT)
	var crate: NetProp = _props(client).get_prop(crate_on_host.net_id)
	PropsService.grab_of(client_body).try_grab(crate)
	await wait_until(func() -> bool: return crate.is_simulated_here(), WAIT)
	await wait_physics_frames(20)
	PropsService.grab_of(client_body).throw()
	await wait_physics_frames(3)
	var expected: float = _props(client).throw_strength(crate) / crate.mass
	assert_gt(crate.linear_velocity.length(), expected * 0.7, "full throw speed, not held back")


func test_client_push_moves_its_copy_at_once_and_the_host_follows() -> void:
	var host := _make_pc()
	var client := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT + 1, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT + 1)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _my_body(client) != null, WAIT)
	var client_body: PlayerCharacter = _my_body(client)
	client_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(10)
	# A crate on the floor just in front of the client (moving the client there instead would
	# look like cheating to the host's speed check).
	var ahead: Vector3 = client_body.global_position - client_body.global_basis.z * 1.3
	var crate_on_host: NetProp = _props(host).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(ahead.x, 0.31, ahead.z)))
	await wait_until(func() -> bool: return _props(client).get_prop(crate_on_host.net_id) != null, WAIT)
	await wait_physics_frames(30)
	var crate_on_client: NetProp = _props(client).get_prop(crate_on_host.net_id)
	var start: Vector3 = crate_on_host.global_position
	var walk := PlayerInputState.new()
	walk.move = Vector2(0, 1)
	client_body.set_input_override(walk)
	await wait_physics_frames(20)
	assert_gt(start.distance_to(crate_on_client.global_position), 0.3, "the client's copy moved right away")
	await wait_physics_frames(20)
	assert_gt(start.distance_to(crate_on_host.global_position), 0.3, "the host's real crate followed")
	client_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(60)
	assert_lt(crate_on_client.global_position.distance_to(crate_on_host.global_position), 0.5,
		"once pushing stops, both PCs agree where it is")


func test_client_grab_hands_physics_to_the_client_and_back() -> void:
	var host := _make_pc()
	var client := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT + 3, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT + 3)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _my_body(client) != null, WAIT)
	var client_body: PlayerCharacter = _my_body(client)
	client_body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(10)
	var crate_on_host: NetProp = _props(host).spawn_prop(&"prop_crate", _in_front_of(client_body))
	await wait_until(func() -> bool: return _props(client).get_prop(crate_on_host.net_id) != null, WAIT)
	var crate_on_client: NetProp = _props(client).get_prop(crate_on_host.net_id)

	PropsService.grab_of(client_body).try_grab(crate_on_client)
	await wait_until(func() -> bool: return crate_on_client.is_simulated_here(), WAIT)
	assert_true(crate_on_client.is_simulated_here(), "the client's PC runs the crate it holds")
	assert_false(crate_on_client.freeze)
	assert_eq(crate_on_host.get_owner_peer(), client_body.get_multiplayer_authority())
	await wait_physics_frames(20)
	var hold_point: Vector3 = client_body.get_aim_origin() + client_body.get_aim_direction() * _props(client).get_config().hold_distance
	assert_lt(crate_on_client.global_position.distance_to(hold_point), 0.5, "in the client's hands, no delay")
	await wait_until(func() -> bool: return crate_on_host.global_position.distance_to(crate_on_client.global_position) < 0.5, WAIT)
	assert_lt(crate_on_host.global_position.distance_to(crate_on_client.global_position), 0.5, "the host's copy follows")

	PropsService.grab_of(client_body).drop()
	await wait_until(func() -> bool: return crate_on_host.get_owner_peer() == 1, WAIT)
	assert_eq(crate_on_host.get_owner_peer(), 1, "once it settled, the host runs it again")
	assert_false(crate_on_host.freeze)


func test_standing_on_a_prop_does_not_push_it() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var body: PlayerCharacter = _my_body(pc)
	var crate: NetProp = _props(pc).spawn_prop(&"prop_crate_heavy", Transform3D(Basis.IDENTITY, Vector3(0, 0.41, -8)))
	await wait_physics_frames(10)
	var start: Vector3 = crate.global_position
	body.global_position = start + Vector3(0, 0.5, 0)
	body.rotation = Vector3.ZERO
	body.set_input_override(PlayerInputState.new())
	await wait_physics_frames(20)
	var walk := PlayerInputState.new()
	walk.move = Vector2(0.3, 0.0)
	body.set_input_override(walk)
	await wait_physics_frames(15)
	assert_lt(start.distance_to(crate.global_position), 0.05, "walking about on top doesn't move it")
