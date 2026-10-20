extends GutTest
## Tests for enemies (docs/systems/enemies.md). Solo tests: this PC is the host, with a floor, an
## EnemySpawner and a player body in a test world. The network test uses two "PCs" over real ENet.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const RAT_SCENE: PackedScene = preload("res://systems/enemies/scenes/rat.tscn")
const PORT: int = 18160
const WAIT: float = 5.0

var _world: Node3D
var _spawner: EnemySpawner
var _pcs: Array[Node] = []


func before_each() -> void:
	Perception.players_invisible = false
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_box(_world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_spawner = EnemySpawner.new()
	_spawner.name = "TestEnemies"
	_world.add_child(_spawner)


func after_each() -> void:
	Perception.players_invisible = false
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


func _add_box(parent: Node, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)
	return body


func _player(at: Vector3, player_id: int = 0) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = player_id if player_id != 0 else Net.local_player_id()
	body.name = str(body.player_id)
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	return body


func _spawn(enemy_id: StringName, at: Vector3, health_multiplier: float = 1.0) -> Enemy:
	return _spawner.spawn(enemy_id, Transform3D(Basis.IDENTITY, at), health_multiplier)


func _pool(entries: Dictionary[StringName, float]) -> Array[WeightedIdData]:
	var pool: Array[WeightedIdData] = []
	for id: StringName in entries:
		var entry := WeightedIdData.new()
		entry.content_id = id
		entry.weight = entries[id]
		pool.append(entry)
	return pool


func test_state_machine_transitions() -> void:
	Perception.players_invisible = true
	_player(Vector3(0, 0, -4))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_physics_frames(3)
	assert_true(rat.get_state() in [&"idle", &"patrol"], "nobody to chase: idle or patrol")
	Perception.players_invisible = false
	await wait_until(func() -> bool: return rat.get_state() == &"swarm" or rat.get_state() == &"attack_melee", WAIT)
	assert_true(rat.get_state() in [&"swarm", &"attack_melee"], "a rat goes after you as a pack (swarm)")
	await wait_until(func() -> bool: return rat.get_state() == &"attack_melee", WAIT)
	assert_eq(rat.get_state(), &"attack_melee", "close enough: it attacks")


func test_chase_when_player_visible() -> void:
	var player := _player(Vector3(0, 0, -8))
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(0, 0.1, 0))
	await wait_until(func() -> bool: return kangaroo.get_state() == &"chase", WAIT)
	assert_eq(kangaroo.get_state(), &"chase")
	assert_eq(kangaroo.get_target(), player)


func test_walls_block_sight() -> void:
	_player(Vector3(0, 0, -8))
	_add_box(_world, Vector3(0, 2, -4), Vector3(10, 4, 0.5))
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(0, 0.1, 0))
	await wait_seconds(0.6)
	assert_null(kangaroo.get_target(), "it can't see through the wall")


func test_attack_hurts_the_player() -> void:
	var player := _player(Vector3(0, 0, -0.8))
	_spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_until(func() -> bool: return HealthComponent.of(player).get_current() < Config.game.player_max_health, WAIT)
	assert_eq(HealthComponent.of(player).get_current(), Config.game.player_max_health - 5.0, "a rat bite does 5")


func test_flee_at_low_health() -> void:
	_player(Vector3(0, 0, -5))
	var bat := _spawn(&"enemy_bat", Vector3(0, 2.5, 0))
	await wait_until(func() -> bool: return bat.get_target() != null, WAIT)
	bat.get_health().apply_damage(DamageInfo.make(16.0, &"blunt"))
	await wait_until(func() -> bool: return bat.get_state() == &"flee", WAIT)
	assert_eq(bat.get_state(), &"flee", "at 20% health the bat flees")
	await wait_until(func() -> bool: return bat.get_state() in [&"chase", &"attack_melee"], WAIT)
	assert_true(bat.get_state() in [&"chase", &"attack_melee"], "then it comes back for you")
	bat.get_health().apply_damage(DamageInfo.make(1.0, &"blunt"))
	await wait_seconds(0.5)
	assert_ne(bat.get_state(), &"flee", "it only runs away once")


func test_flying_enemies_hover() -> void:
	var bat := _spawn(&"enemy_bat", Vector3(0, 0.5, 0))
	await wait_seconds(1.5)
	assert_gt(bat.global_position.y, 1.5, "it flies up to its hover height (no falling)")


func test_spawner_spends_budget() -> void:
	var rng := SeededRng.make(5, &"enemy_spawns", 1)
	var plan: Array[StringName] = EnemiesService.plan_spawns(_pool({&"enemy_rat": 1.0, &"enemy_bat": 1.0}), 1, 9, rng)
	var spent: int = 0
	for id: StringName in plan:
		spent += (ContentRegistry.get_content(id) as EnemyData).spawn_cost
	assert_eq(spent, 9, "the whole budget is spent")


func test_budget_scales_with_players() -> void:
	var one: int = RunDifficulty.enemy_budget(1, 1)
	var four: int = RunDifficulty.enemy_budget(1, 4)
	var eight: int = RunDifficulty.enemy_budget(1, 8)
	assert_gt(four, one)
	assert_gt(eight, four)
	assert_gt(RunDifficulty.enemy_health_multiplier(4), RunDifficulty.enemy_health_multiplier(1), "and tougher")


func test_min_floor_respected() -> void:
	var rng := SeededRng.make(9, &"enemy_spawns", 1)
	var plan: Array[StringName] = EnemiesService.plan_spawns(_pool({&"enemy_kangaroo": 5.0, &"enemy_rat": 1.0}), 1, 20, rng)
	assert_false(plan.has(&"enemy_kangaroo"), "kangaroos start on floor 2")
	var deeper: Array[StringName] = EnemiesService.plan_spawns(_pool({&"enemy_kangaroo": 5.0, &"enemy_rat": 1.0}), 2, 20,
		SeededRng.make(9, &"enemy_spawns", 2))
	assert_true(deeper.has(&"enemy_kangaroo"))


func test_same_seed_same_spawns() -> void:
	var pool: Array[WeightedIdData] = _pool({&"enemy_rat": 1.0, &"enemy_bat": 1.0, &"enemy_fly": 1.0})
	var first: Array[StringName] = EnemiesService.plan_spawns(pool, 1, 12, SeededRng.make(42, &"enemy_spawns", 3))
	var second: Array[StringName] = EnemiesService.plan_spawns(pool, 1, 12, SeededRng.make(42, &"enemy_spawns", 3))
	assert_eq(first, second)


func test_health_scaled_for_players() -> void:
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 5), 1.5)
	assert_eq(rat.get_health().get_max(), 22.5, "15 x 1.5")


func test_enemy_killed_emitted_with_killer() -> void:
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 5))
	watch_signals(EventBus)
	var info := DamageInfo.make(100.0, &"blunt")
	info.source_player_id = 77
	rat.get_health().apply_damage(info)
	assert_signal_emitted(EventBus, "enemy_killed")
	var params: Array = get_signal_parameters(EventBus, "enemy_killed")
	assert_eq(params[0], &"enemy_rat")
	assert_eq(params[2], 77, "the killer gets the credit")
	assert_true(rat.is_dead())
	var body: WeakRef = weakref(rat)
	rat = null
	await wait_until(func() -> bool: return body.get_ref() == null, WAIT)
	assert_null(body.get_ref(), "the body is removed after a moment")


func test_new_enemy_file_spawns_without_code() -> void:
	var data := EnemyData.new()
	data.id = &"enemy_test_big_rat"
	data.display_name = "Big rat"
	data.scene = RAT_SCENE
	data.max_health = 99.0
	if not ContentRegistry.has_content(data.id):
		ContentRegistry.register_content(data)
	var big := _spawn(&"enemy_test_big_rat", Vector3(3, 0.1, 3))
	assert_not_null(big)
	assert_eq(big.get_health().get_max(), 99.0)


func test_navigation_goes_around_walls() -> void:
	_add_box(_world, Vector3(0, 1.5, 0), Vector3(8, 3, 0.5))
	await wait_physics_frames(2)
	Enemies.bake_navigation(_world)
	await wait_physics_frames(3)
	var map: RID = _world.get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(0, 0, -3), Vector3(0, 0, 3), true)
	assert_gt(path.size(), 2, "there is a path")
	var length: float = 0.0
	for index: int in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	assert_gt(length, 7.0, "it goes around the wall (straight through would be 6 m)")


func test_enemies_move_the_same_on_host_and_client() -> void:
	var host := _make_pc(true)
	var client := _make_pc(false)
	await wait_until(func() -> bool: return client.multiplayer.get_unique_id() > 1 \
		and host.multiplayer.get_peers().size() == 1, WAIT)
	var host_spawner := host.get_node("Enemies") as EnemySpawner
	var client_spawner := client.get_node("Enemies") as EnemySpawner
	var rat: Enemy = host_spawner.spawn(&"enemy_rat", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
	await wait_until(func() -> bool: return client_spawner.get_alive().size() == 1, WAIT)
	var copy: Enemy = client_spawner.get_alive()[0]
	rat.global_position = Vector3(3, 0.1, 2)
	await wait_until(func() -> bool: return copy.global_position.distance_to(rat.global_position) < 0.2, WAIT)
	assert_lt(copy.global_position.distance_to(rat.global_position), 0.2, "the client's copy follows the host")
	rat.get_health().apply_damage(DamageInfo.make(100.0, &"blunt"))
	await wait_until(func() -> bool: return copy.is_dead(), WAIT)
	assert_true(copy.is_dead(), "and dies on the client too")


func _make_pc(hosting: bool) -> Node:
	var pc := SubViewport.new()
	pc.own_world_3d = true
	pc.name = "Pc%d" % _pcs.size()
	add_child(pc)
	get_tree().set_multiplayer(SceneMultiplayer.new(), pc.get_path())
	var world := Node3D.new()
	world.name = "World"
	pc.add_child(world)
	_add_box(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var spawner := EnemySpawner.new()
	spawner.name = "Enemies"
	pc.add_child(spawner)
	var peer := ENetMultiplayerPeer.new()
	if hosting:
		assert_eq(peer.create_server(PORT, 32), OK)
	else:
		peer.create_client("127.0.0.1", PORT)
	pc.multiplayer.multiplayer_peer = peer
	_pcs.append(pc)
	return pc
