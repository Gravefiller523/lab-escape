extends GutTest
## Tests for cargo_lift (docs/systems/cargo_lift.md). Each "PC" is a SubViewport with its own
## physics, multiplayer and Net, a floor, a player spawner, a prop spawner and the lift at the origin.

const PORT: int = 18100
const WAIT: float = 5.0
const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")

var _pcs: Array[Node] = []


func _config() -> GameConfig:
	var config := GameConfig.new()
	config.afk_force_start_after = 0.3
	return config


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
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var lift := LIFT_SCENE.instantiate() as CargoLift
	lift.use_net(net, config)
	world.add_child(lift)
	var players := PlayerSpawner.new()
	players.name = "PlayerSpawner"
	players.use_net(net)
	players.spawn_points = lift.get_spawn_points()
	world.add_child(players)
	var props := PropSpawner.new()
	props.name = "Props"
	props.use_net(net, config)
	world.add_child(props)
	_pcs.append(pc)
	return pc


func _lift(pc: Node) -> CargoLift:
	return pc.get_node("World/CargoLift") as CargoLift


func _props(pc: Node) -> PropSpawner:
	return pc.get_node("World/Props") as PropSpawner


func _net(pc: Node) -> NetService:
	return pc.get_node("Net") as NetService


func _body(pc: Node, player_id: int) -> PlayerCharacter:
	return pc.get_node_or_null("World/%d" % player_id) as PlayerCharacter


func _my_body(pc: Node) -> PlayerCharacter:
	return _body(pc, _net(pc).local_player_id())


func _host_and_client() -> Array[Node]:
	var host := _make_pc()
	var server := ENetMultiplayerPeer.new()
	assert_eq(server.create_server(PORT, 4), OK)
	host.multiplayer.multiplayer_peer = server
	var client := _make_pc()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	client.multiplayer.multiplayer_peer = peer
	await wait_until(func() -> bool: return _my_body(client) != null and _net(host).get_player_ids().size() == 2, WAIT)
	await wait_until(func() -> bool: return _body(host, _net(client).local_player_id()) != null, WAIT)
	return [host, client] as Array[Node]


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


## Where to drop a part so it lands in a slot.
func _slot_drop_point(pc: Node, slot: StringName) -> Vector3:
	var socket := pc.get_node("World/CargoLift/Slot_%s/Socket" % slot) as Area3D
	return socket.global_position + Vector3.UP * 0.2


func test_there_is_a_slot_for_every_kind_of_part() -> void:
	var pc := _make_pc()
	var slots: Array[StringName] = _lift(pc).get_slot_names()
	for slot: StringName in [&"gear", &"fuse", &"light", &"button", &"counterweight", &"vacuum_tube",
			&"cable_spool", &"battery", &"lever"]:
		assert_true(slots.has(slot), "the lift has a %s slot" % slot)
	assert_eq(_lift(pc).get_slot_part(&"gear").id, &"prop_lift_gear")


func test_part_in_its_slot_counts() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var lift: CargoLift = _lift(pc)
	lift.arrive(9, false)
	assert_true(lift.get_broken_slots().has(&"gear"), "everything broke")
	assert_string_contains(lift.depart_blocker(), "gear")
	watch_signals(EventBus)
	var gear: NetProp = _props(pc).spawn_prop(&"prop_lift_gear", Transform3D(Basis.IDENTITY, _slot_drop_point(pc, &"gear")))
	await wait_until(func() -> bool: return not lift.get_broken_slots().has(&"gear"), WAIT)
	assert_false(lift.get_broken_slots().has(&"gear"), "the gear fixed the gear slot")
	assert_eq(lift.get_parts_delivered(), 1)
	assert_signal_emitted(EventBus, "lift_part_delivered")
	await wait_physics_frames(2)
	assert_false(is_instance_valid(gear) and gear.is_inside_tree(), "the part is used up")


func test_wrong_part_or_crate_doesnt_fit() -> void:
	var pc := _make_pc()
	var lift: CargoLift = _lift(pc)
	lift.arrive(9, false)
	_props(pc).spawn_prop(&"prop_lift_gear", Transform3D(Basis.IDENTITY, _slot_drop_point(pc, &"fuse")))
	_props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, _slot_drop_point(pc, &"lever")))
	await wait_physics_frames(30)
	assert_true(lift.get_broken_slots().has(&"fuse"), "a gear doesn't fix the fuse slot")
	assert_true(lift.get_broken_slots().has(&"lever"), "a crate doesn't fix anything")


func test_flat_battery_doesnt_fit() -> void:
	var pc := _make_pc()
	var lift: CargoLift = _lift(pc)
	lift.arrive(9, false)
	_props(pc).spawn_prop(&"prop_lift_battery", Transform3D(Basis.IDENTITY, _slot_drop_point(pc, &"battery")))
	await wait_physics_frames(30)
	assert_true(lift.get_broken_slots().has(&"battery"), "it must be charged first")


func test_the_same_run_breaks_the_same_slots() -> void:
	var pc := _make_pc()
	var lift: CargoLift = _lift(pc)
	lift.arrive(3, false)
	var first: Array[StringName] = lift.get_broken_slots()
	assert_eq(first.size(), 3, "three slots broke")
	lift.arrive(3, false)
	assert_eq(lift.get_broken_slots(), first, "same seed and floor: the same slots")
	lift.arrive(0, true)
	assert_false(lift.is_broken(), "nothing breaks in the Break Room")


func test_depart_needs_all_players() -> void:
	var pcs: Array[Node] = await _host_and_client()
	var host: Node = pcs[0]
	var client: Node = pcs[1]
	var lift: CargoLift = _lift(host)
	lift.arrive(0, false)
	var client_id: int = _net(client).local_player_id()
	# The host moves the client out of the lift (a big jump by the client itself would be undone by the
	# host's speed check).
	_body(host, client_id).teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -8)))
	await wait_until(func() -> bool: return lift.get_zone().get_missing_players().has(client_id), WAIT)
	assert_string_contains(lift.depart_blocker(), "Waiting for", "refuses while someone is outside")
	_body(host, client_id).teleport(Transform3D(Basis.IDENTITY, Vector3(1, 0.1, 0)))
	await wait_until(func() -> bool: return lift.depart_blocker().is_empty(), WAIT)
	assert_eq(lift.depart_blocker(), "", "everyone inside: it can go")


func test_go_departs_and_every_pc_sees_it() -> void:
	var pcs: Array[Node] = await _host_and_client()
	var host: Node = pcs[0]
	var client: Node = pcs[1]
	_lift(host).arrive(0, false)
	await wait_until(func() -> bool: return _lift(host).depart_blocker().is_empty(), WAIT)
	watch_signals(EventBus)
	_lift(client).request_depart()
	await wait_until(func() -> bool: return _lift(client).is_riding(), WAIT)
	assert_true(_lift(host).is_riding(), "the host decided")
	assert_true(_lift(client).is_riding(), "and the client rides too")
	assert_signal_emitted(EventBus, "lift_departed")
	_lift(host).arrive(1, false)
	await wait_until(func() -> bool: return not _lift(client).is_riding(), WAIT)
	assert_true(_lift(client).is_broken(), "it arrives broken on the next floor")


func test_props_inside_are_found() -> void:
	var pc := _make_pc()
	var inside: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(-1, 0.5, 1)))
	var outside: NetProp = _props(pc).spawn_prop(&"prop_crate", Transform3D(Basis.IDENTITY, Vector3(0, 0.5, -8)))
	await wait_physics_frames(10)
	var found: Array[NetProp] = _lift(pc).get_zone().get_props_inside()
	assert_true(found.has(inside), "a crate in the lift rides along")
	assert_false(found.has(outside), "one outside doesn't")


func test_boss_floor_waits_for_the_boss() -> void:
	var pc := _make_pc()
	await wait_until(func() -> bool: return _my_body(pc) != null, WAIT)
	var lift: CargoLift = _lift(pc)
	lift.arrive(0, false, true)
	assert_eq(lift.depart_blocker(), CargoLift.MSG_BOSS)
	EventBus.boss_defeated.emit(&"boss_test")
	await wait_physics_frames(2)
	await wait_until(func() -> bool: return lift.depart_blocker().is_empty(), WAIT)
	assert_eq(lift.depart_blocker(), "", "beating the boss fixes it")


func test_force_start_after_the_timer() -> void:
	var pcs: Array[Node] = await _host_and_client()
	var host: Node = pcs[0]
	var client: Node = pcs[1]
	var lift: CargoLift = _lift(host)
	lift.arrive(0, true)
	_body(host, _net(client).local_player_id()).teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -8)))
	await wait_physics_frames(5)
	assert_false(lift.can_force_start(), "not before the timer")
	await wait_seconds(0.5)
	assert_true(lift.can_force_start(), "the host may start anyway after it")
	assert_false(_lift(client).can_force_start(), "clients never may")
