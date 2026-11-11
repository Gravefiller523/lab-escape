extends GutTest
## Tests for ranged attacks (NEW 2026-11-11, roadmap WP9; docs/systems/enemies.md): EnemyProjectile, the
## attack_ranged state and the test spitter. Solo: this PC is the host, with a floor, an EnemySpawner and a player.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 8.0

var _world: Node3D
var _spawner: EnemySpawner


func before_each() -> void:
	Perception.players_invisible = false
	AttackTickets.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	_spawner = EnemySpawner.new()
	_spawner.name = "TestEnemies"
	_world.add_child(_spawner)


func after_each() -> void:
	for shot: EnemyProjectile in Enemies.get_projectiles():
		shot.queue_free()
	await wait_physics_frames(1)


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_world.add_child(body)
	return body


func _player(at: Vector3) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	body.name = str(body.player_id)
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	DamageService.give_components(body, 100.0)
	return body


func _attack(damage: float = 10.0) -> RangedAttackData:
	var attack := RangedAttackData.new()
	attack.damage = damage
	attack.projectile_speed = 20.0
	attack.spread_degrees = 0.0
	return attack


func test_a_shot_hurts_the_player_it_hits() -> void:
	var player := _player(Vector3(0, 0, -6))
	await wait_physics_frames(3)
	var health: HealthComponent = HealthComponent.of(player)
	var before: float = health.get_current()
	Enemies.add_projectile(Vector3(0, 1.1, 0), Vector3(0, 0, -20), _attack(10.0), null)
	await wait_until(func() -> bool: return health.get_current() < before, WAIT)
	assert_almost_eq(health.get_current(), before - 10.0, 0.01, "10 damage")
	await wait_physics_frames(2)
	assert_eq(Enemies.get_projectiles().size(), 0, "the shot is gone once it hits")


func test_a_wall_stops_a_shot() -> void:
	var player := _player(Vector3(0, 0, -8))
	_add_box(Vector3(0, 1.5, -4), Vector3(4, 3, 0.3))
	await wait_physics_frames(3)
	var health: HealthComponent = HealthComponent.of(player)
	var before: float = health.get_current()
	Enemies.add_projectile(Vector3(0, 1.1, 0), Vector3(0, 0, -20), _attack(10.0), null)
	await wait_until(func() -> bool: return Enemies.get_projectiles().is_empty(), WAIT)
	assert_eq(Enemies.get_projectiles().size(), 0, "it stopped")
	assert_eq(health.get_current(), before, "the wall took it, not the player")


func test_the_spitter_keeps_its_distance_and_shoots() -> void:
	var player := _player(Vector3(0, 0, -10))
	var spitter: Enemy = _spawner.spawn(&"enemy_test_spitter", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 1.0)
	assert_not_null(spitter, "the test spitter spawns")
	var health: HealthComponent = HealthComponent.of(player)
	var before: float = health.get_current()
	await wait_until(func() -> bool: return spitter.get_state() == &"attack_ranged", WAIT)
	assert_eq(spitter.get_state(), &"attack_ranged", "it sees you and starts shooting")
	await wait_until(func() -> bool: return health.get_current() < before, WAIT)
	assert_lt(health.get_current(), before, "and its shots hurt")
	assert_gt(spitter.flat_distance_to_target(), spitter.data.ranged_attack.min_range - 1.0,
		"it stays back instead of running up to you")


func test_a_turret_without_chase_shoots_as_its_pursuit() -> void:
	var spitter: Enemy = _spawner.spawn(&"enemy_test_spitter", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 1.0)
	await wait_physics_frames(2)
	assert_eq(spitter.pursuit_state(), &"chase", "a walker chases")
	# A turret: the same enemy without its moving states (the states are read when it is set up).
	var scene: PackedScene = (ContentRegistry.get_content(&"enemy_test_spitter") as EnemyData).scene
	var turret := scene.instantiate() as Enemy
	turret.get_node(^"States/chase").free()
	turret.get_node(^"States/patrol").free()
	turret.setup(ContentRegistry.get_content(&"enemy_test_spitter") as EnemyData, 1.0)
	_world.add_child(turret)
	await wait_physics_frames(2)
	assert_eq(turret.pursuit_state(), &"attack_ranged", "only idle, search and attack_ranged: it pursues by shooting")
