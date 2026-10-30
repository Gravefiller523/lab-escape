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
	AttackTickets.clear()
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
	var region: NavigationRegion3D = Enemies.bake_navigation(_world)
	assert_true(Enemies.is_baking_navigation(), "it bakes in the background (no freeze)")
	await wait_for_signal(Enemies.navigation_baked, WAIT)
	assert_not_null(region.navigation_mesh)
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


# --- HL2 feel step 3 (NEW 2026-10-30) ------------------------------------------------------------

func test_missed_attack_does_not_use_up_the_cooldown() -> void:
	var player := _player(Vector3(0, 0, -8))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_physics_frames(2)
	rat.set_target(player)
	assert_false(rat.try_attack(), "too far to bite")
	assert_true(rat.attack_ready(), "and the miss didn't use up its cooldown")


func test_chases_to_where_it_last_saw_you_not_through_walls() -> void:
	var player := _player(Vector3(0, 0, -8))
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(0, 0.1, 0))
	await wait_until(func() -> bool: return kangaroo.get_state() == &"chase", WAIT)
	var seen_at: Vector3 = player.global_position
	# Duck behind a wall far to the side.
	_add_box(_world, Vector3(5, 2, -6), Vector3(0.5, 4, 14))
	player.global_position = Vector3(12, 0, -8)
	await wait_seconds(0.5)
	assert_false(kangaroo.can_see_target(), "it can't see you behind the wall")
	assert_lt(kangaroo.last_known_position.distance_to(seen_at), 2.0, "it still thinks you're where it saw you")
	assert_lt(kangaroo.chase_point().distance_to(seen_at), 2.0, "and runs there, not to where you really are")
	await wait_until(func() -> bool: return kangaroo.get_state() == &"search", WAIT)
	assert_eq(kangaroo.get_state(), &"search", "you're gone: it looks around there")
	assert_null(kangaroo.get_target())
	await wait_until(func() -> bool: return kangaroo.get_state() == &"idle", WAIT)
	assert_eq(kangaroo.get_state(), &"idle", "then it gives up")


func test_cannot_see_players_behind_it() -> void:
	# Rats look along -Z when spawned; their view cone is 140 degrees.
	var player := _player(Vector3(0, 0, 6))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_seconds(1.0)
	assert_null(rat.get_target(), "behind it: unseen")
	player.global_position = Vector3(0, 0, -6)
	await wait_until(func() -> bool: return rat.get_target() != null, WAIT)
	assert_eq(rat.get_target(), player, "in front: seen")


func test_noticing_takes_a_moment_and_squeaks() -> void:
	var player := _player(Vector3(0, 0, -7))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	watch_signals(rat)
	await wait_physics_frames(2)
	rat.get_perception().refresh()
	assert_eq(rat.get_perception().get_visible_players().size(), 1, "it can see you...")
	assert_null(rat.update_target(), "...but hasn't noticed you yet")
	await wait_until(func() -> bool: return rat.get_target() != null, WAIT)
	assert_eq(rat.get_target(), player, "a moment later it has")
	assert_signal_emit_count(rat, "noticed", 1, "with one squeak")


func test_players_right_behind_it_are_noticed_at_once() -> void:
	var player := _player(Vector3(0, 0, 1.5))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_physics_frames(2)
	rat.get_perception().refresh()
	assert_eq(rat.update_target(), player, "too close to sneak past, even from behind")


func test_noise_brings_calm_enemies_to_look() -> void:
	Perception.players_invisible = true
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	var far_rat := _spawn(&"enemy_rat", Vector3(-15, 0.1, 0))
	await wait_physics_frames(3)
	EventBus.noise_made.emit(Vector3(6, 0, 0), 10.0, 0)
	assert_eq(rat.get_state(), &"search", "it heard the noise and goes to look")
	assert_ne(far_rat.get_state(), &"search", "too far away to hear it")
	await wait_until(func() -> bool: return rat.flat_distance_to(Vector3(6, 0, 0)) < 1.5, WAIT)
	assert_lt(rat.flat_distance_to(Vector3(6, 0, 0)), 1.5, "it walked over there")


func test_footsteps_are_noises_crouching_quietest() -> void:
	var ai: AiTuning = Config.feel.ai
	assert_lt(ai.noise_crouch_step, ai.noise_step)
	assert_lt(ai.noise_step, ai.noise_sprint_step)
	var player := _player(Vector3(0, 0.1, 0))
	var heard: Array[float] = []
	var listen := func(_at: Vector3, radius: float, _source: int) -> void: heard.append(radius)
	EventBus.noise_made.connect(listen)
	var input := PlayerInputState.new()
	input.move = Vector2(0, -1)
	player.set_input_override(input)
	await wait_seconds(1.2)
	EventBus.noise_made.disconnect(listen)
	assert_gt(heard.size(), 0, "walking makes noise")
	assert_true(heard.has(ai.noise_step), "a walking step carries noise_step metres")


func test_a_rat_that_spots_you_alerts_its_pack() -> void:
	var player := _player(Vector3(0, 0, 10))
	var spotter := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	var packmate := _spawn(&"enemy_rat", Vector3(2, 0.1, 0))
	var far_rat := _spawn(&"enemy_rat", Vector3(-20, 0.1, 0))
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(-2, 0.1, 0))
	await wait_physics_frames(3)
	assert_null(packmate.get_target(), "nobody has seen you (you're behind them)")
	spotter.on_hurt_by(player)
	assert_eq(spotter.get_target(), player, "hurt: it turns on you")
	assert_eq(packmate.get_target(), player, "and its packmate knows too")
	assert_null(far_rat.get_target(), "a rat far away doesn't")
	assert_null(kangaroo.get_target(), "other kinds of enemy don't")


func test_enemies_spread_over_the_team() -> void:
	var near := _player(Vector3(0, 0, -4), 101)
	var other := _player(Vector3(3, 0, -4), 102)
	var busy := _spawn(&"enemy_rat", Vector3(-1, 0.1, 0))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	Perception.players_invisible = true
	await wait_physics_frames(2)
	busy.set_target(near)
	Perception.players_invisible = false
	rat.get_perception().know(near)
	rat.get_perception().know(other)
	rat.get_perception().refresh()
	assert_eq(rat.get_perception().get_noticed_players().size(), 2)
	assert_eq(rat.get_perception().choose_target(null, 0.0), other,
		"the nearest player already has a rat on them, so it goes for the other one")


func test_only_two_attack_tickets_per_player() -> void:
	Perception.players_invisible = true
	var player := _player(Vector3(0, 0, -6))
	var first := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	var second := _spawn(&"enemy_rat", Vector3(1, 0.1, 0))
	var third := _spawn(&"enemy_rat", Vector3(2, 0.1, 0))
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(-2, 0.1, 0))
	await wait_physics_frames(2)
	assert_true(AttackTickets.claim(first, player), "the first rat gets a ticket")
	assert_false(AttackTickets.claim(second, player), "not straight after another one")
	await wait_seconds(Config.feel.ai.ticket_grant_gap + 0.05)
	assert_true(AttackTickets.claim(second, player), "a moment later the second does")
	await wait_seconds(Config.feel.ai.ticket_grant_gap + 0.05)
	assert_false(AttackTickets.claim(third, player), "two is the limit: the third circles")
	AttackTickets.release(first)
	assert_false(AttackTickets.claim(kangaroo, player), "a kangaroo needs both tickets")
	assert_true(AttackTickets.claim(third, player), "the first rat is done: the third gets its turn")


func test_only_two_rats_bite_at_once() -> void:
	var player := _player(Vector3(0, 0, -2))
	HealthComponent.of(player).invulnerable = true
	for index: int in 5:
		_spawn(&"enemy_rat", Vector3(float(index) - 2.0, 0.1, 0))
	var most: int = 0
	for frame: int in 180:
		await wait_physics_frames(1)
		var attacking: int = 0
		for enemy: Enemy in _spawner.get_alive():
			if enemy.get_state() == &"attack_melee":
				attacking += 1
		most = maxi(most, attacking)
	assert_between(most, 1, 2, "never more than two at once (most: %d)" % most)


func test_attacks_wind_up_before_they_hit() -> void:
	var player := _player(Vector3(0, 0, -0.8))
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	var health: HealthComponent = HealthComponent.of(player)
	await wait_until(func() -> bool: return rat.get_state() == &"attack_melee", WAIT)
	var started: int = Time.get_ticks_msec()
	await wait_until(func() -> bool: return health.get_current() < health.get_max(), WAIT)
	var waited: float = (Time.get_ticks_msec() - started) / 1000.0
	assert_gt(waited, Config.feel.ai.attack_windup - 0.1, "the bite came after its wind-up (%.2f s)" % waited)


func test_kangaroo_jumps_aside_from_a_heavy_throw() -> void:
	Perception.players_invisible = true
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(0, 0.1, 0))
	kangaroo.data = kangaroo.data.duplicate() as EnemyData
	kangaroo.data.dodge_chance = 1.0
	await wait_seconds(0.5)
	assert_false(kangaroo.consider_dodge(1, Vector3(4, 1, -6), Vector3(0, 0, 15)), "a throw that misses by far: no dodge")
	assert_true(kangaroo.consider_dodge(2, Vector3(0, 1, -6), Vector3(0, 0, 15)), "one coming straight at it: it jumps aside")
	assert_true(kangaroo.is_dodging())
	assert_gt(absf(kangaroo.velocity.x), 3.0, "sideways")
	assert_false(kangaroo.consider_dodge(3, Vector3(0, 1, -6), Vector3(0, 0, 15)), "not again straight away")


func test_dead_enemy_leaves_a_tumbling_body() -> void:
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	await wait_physics_frames(2)
	var before: int = Enemy.count_corpses()
	var level: Node = rat.corpse_parent()
	var info := DamageInfo.make(100.0, &"blunt")
	info.knockback = Vector3(4, 0, 0)
	rat.get_health().apply_damage(info)
	assert_eq(Enemy.count_corpses(), before + 1, "a body appears")
	var body := level.get_node_or_null(NodePath("%sBody" % rat.name)) as RigidBody3D
	assert_not_null(body, "a loose physics body")
	if body != null:
		var start: Vector3 = body.global_position
		await wait_seconds(0.3)
		assert_gt(body.global_position.distance_to(start), 0.2, "that tumbles away from the hit")


func test_walking_enemies_make_room_for_each_other() -> void:
	Perception.players_invisible = true
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, 0))
	var other := _spawn(&"enemy_rat", Vector3(0.3, 0.1, 0))
	var kangaroo := _spawn(&"enemy_kangaroo", Vector3(-3, 0.1, 0))
	await wait_physics_frames(3)
	EventBus.noise_made.emit(Vector3(0, 0, -8), 12.0, 0)
	await wait_seconds(1.0)
	var apart: float = rat.flat_distance_to(other.global_position)
	assert_gt(apart, 0.6, "two rats heading the same way spread out (%.2f m apart)" % apart)
	rat.global_position = kangaroo.global_position + Vector3(0.4, 0, 0)
	await wait_seconds(0.3)
	assert_gt(rat.get_spacing_push().length(), kangaroo.get_spacing_push().length(),
		"a rat makes more room for a kangaroo than the kangaroo does for it")



## NEW 2026-10-30 (doors): a wall across z = 0 (x -10..10, 3 m high) with a 1.2 m doorway at x -0.6..0.6 and a
## door in it (hinge at x = -0.6). Going round the wall instead is about 21 m.
func _door_wall(locked: bool = false) -> WorldDoor:
	_add_box(_world, Vector3(-5.3, 1.5, 0), Vector3(9.4, 3, 0.2))
	_add_box(_world, Vector3(5.3, 1.5, 0), Vector3(9.4, 3, 0.2))
	var door := WorldDoor.new()
	door.name = "Door"
	door.locked = locked
	door.position = Vector3(-0.6, 0, 0)
	_world.add_child(door)
	return door


## How long the navigation path from `from` to `to` is (INF if it doesn't get there).
func _path_length(from: Vector3, to: Vector3) -> float:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_world.get_world_3d().navigation_map, from, to, true)
	if path.size() < 2 or path[path.size() - 1].distance_to(to) > 1.0:
		return INF
	var length: float = 0.0
	for index: int in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func test_enemies_path_through_doors_they_can_open_but_not_locked_ones() -> void:
	var door := _door_wall()
	await wait_physics_frames(2)
	Enemies.bake_navigation(_world, true)
	await wait_physics_frames(3)
	var from := Vector3(0, 0, -3)
	var to := Vector3(0, 0, 3)
	var through: float = _path_length(from, to)
	assert_lt(through, 8.0, "a shut door they can open doesn't block the path (%.1f m)" % through)
	door.receive(&"lock")
	Enemies.update_navigation(true)
	await wait_physics_frames(3)
	var around: float = _path_length(from, to)
	assert_between(around, 15.0, 40.0, "locked, the path goes round the wall (%.1f m)" % around)
	door.receive(&"unlock")
	await wait_for_signal(Enemies.navigation_baked, WAIT)
	await wait_physics_frames(3)
	through = _path_length(from, to)
	assert_lt(through, 8.0, "unlocking it bakes the navigation again by itself (%.1f m)" % through)


func test_an_enemy_walking_into_a_door_pushes_it_open() -> void:
	Perception.players_invisible = true
	var door := _door_wall()
	await wait_physics_frames(2)
	Enemies.bake_navigation(_world, true)
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, -4))
	await wait_physics_frames(3)
	var spot := Vector3(0, 0, 4)
	EventBus.noise_made.emit(spot, 12.0, 0)
	assert_eq(rat.get_state(), &"search", "it heard the noise behind the door")
	await wait_until(func() -> bool: return door.get_target_angle() != 0.0, WAIT)
	assert_lt(door.get_target_angle(), 0.0, "the door swings away from the rat (towards +Z)")
	await wait_until(func() -> bool: return rat.flat_distance_to(spot) < 1.5, WAIT)
	assert_lt(rat.flat_distance_to(spot), 1.5, "and the rat walked through to where the noise was")


func test_enemies_dont_open_locked_doors_or_doors_they_only_stand_by() -> void:
	Perception.players_invisible = true
	var locked := _door_wall(true)
	var rat := _spawn(&"enemy_rat", Vector3(0, 0.1, -0.6))
	await wait_physics_frames(3)
	await wait_seconds(0.5)
	assert_eq(rat.get_walk_intent(), Vector3.ZERO, "an idle rat isn't walking anywhere")
	locked.receive(&"unlock")
	await wait_seconds(0.5)
	assert_eq(locked.get_target_angle(), 0.0, "a rat just standing by the door doesn't open it")
	locked.receive(&"lock")
	rat.search_point = Vector3(0, 0, 4)
	rat.interrupt(&"search")
	await wait_seconds(1.0)
	assert_ne(rat.get_walk_intent(), Vector3.ZERO, "it tries to walk through")
	assert_eq(locked.get_target_angle(), 0.0, "but it can't open a locked door")
	locked.enemies_can_open = false
	locked.receive(&"unlock")
	await wait_seconds(0.5)
	assert_eq(locked.get_target_angle(), 0.0, "nor one that enemies_can_open is off for")
	locked.enemies_can_open = true
	await wait_until(func() -> bool: return locked.get_target_angle() != 0.0, WAIT)
	assert_ne(locked.get_target_angle(), 0.0, "otherwise it pushes it open")

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
