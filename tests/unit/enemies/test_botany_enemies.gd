extends GutTest
## Botany's own enemies (NEW 2026-11-12, roadmap WP10): the flytrap, spore shooter, vine creeper and mushroom zombie.
## Solo: this PC is the host, with a floor, an EnemySpawner and a player body.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 8.0
const BOTANY_ENEMIES: Array[StringName] = [&"enemy_mushroom_zombie", &"enemy_flytrap", &"enemy_spore_shooter",
	&"enemy_vine_creeper"]

var _world: Node3D
var _spawner: EnemySpawner


func before_each() -> void:
	Perception.players_invisible = false
	AttackTickets.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	_spawner = EnemySpawner.new()
	_spawner.name = "TestEnemies"
	_world.add_child(_spawner)


func after_each() -> void:
	for shot: EnemyProjectile in Enemies.get_projectiles():
		shot.queue_free()
	await wait_physics_frames(1)


func _player(at: Vector3) -> PlayerCharacter:
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	body.name = str(body.player_id)
	body.position = at
	_world.add_child(body)
	body.set_input_override(PlayerInputState.new())
	DamageService.give_components(body, 100.0)
	return body


func _spawn(enemy_id: StringName, at: Vector3) -> Enemy:
	return _spawner.spawn(enemy_id, Transform3D(Basis.IDENTITY, at), 1.0)


func test_botany_has_its_own_enemies_loot_and_stock() -> void:
	var botany := ContentRegistry.get_content(&"department_botany") as DepartmentData
	var spawns: Array[StringName] = []
	for entry: WeightedIdData in botany.enemy_spawns:
		spawns.append(entry.content_id)
	assert_eq(spawns, BOTANY_ENEMIES, "only Botany's four enemies")
	assert_eq(botany.loot_id, &"loot_botany_small")
	assert_eq(botany.stock_id, &"stock_botany_vending")
	for enemy_id: StringName in BOTANY_ENEMIES:
		assert_not_null(_spawn(enemy_id, Vector3(0, 0.1, 0)), "%s spawns" % enemy_id)


func test_the_flytrap_stays_put_and_bites_when_you_come_close() -> void:
	var player := _player(Vector3(0, 0, -4))
	var flytrap := _spawn(&"enemy_flytrap", Vector3(0, 0.1, 0))
	await wait_physics_frames(10)
	var start: Vector3 = flytrap.global_position
	var health: HealthComponent = HealthComponent.of(player)
	await wait_seconds(1.0)
	assert_eq(health.get_current(), 100.0, "too far: it doesn't reach you")
	assert_lt(flytrap.global_position.distance_to(start), 0.05, "and it never moves")
	player.global_position = Vector3(0, 0, -1.2)
	await wait_until(func() -> bool: return health.get_current() < 100.0, WAIT)
	assert_lt(health.get_current(), 100.0, "close: it snaps at you")
	assert_lt(flytrap.global_position.distance_to(start), 0.05, "without moving")


func test_the_vine_creeper_drags_you_in() -> void:
	var player := _player(Vector3(0, 0, -2.6))
	var creeper := _spawn(&"enemy_vine_creeper", Vector3(0, 0.1, 0))
	var health: HealthComponent = HealthComponent.of(player)
	await wait_until(func() -> bool: return health.get_current() < 100.0, WAIT)
	assert_lt(health.get_current(), 100.0, "its lash reaches you")
	var before: float = player.global_position.distance_to(creeper.global_position)
	await wait_physics_frames(10)
	assert_lt(player.global_position.distance_to(creeper.global_position), before, "and pulls you towards it")


func test_the_spore_shooter_gives_you_spores() -> void:
	var player := _player(Vector3(0, 0, -9))
	_spawn(&"enemy_spore_shooter", Vector3(0, 0.1, 0))
	var statuses: StatusEffectComponent = StatusEffectComponent.of(player)
	await wait_until(func() -> bool: return statuses.has_status(&"status_spores"), WAIT * 2.0)
	assert_true(statuses.has_status(&"status_spores"), "its puffball makes you cough spores")
