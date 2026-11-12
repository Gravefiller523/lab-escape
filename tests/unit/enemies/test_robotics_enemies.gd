extends GutTest
## Robotics' own enemies (NEW 2026-11-12, roadmap WP11): the roomba, turret, drone and flock camera. Solo: this PC
## is the host, with a floor, an EnemySpawner and a player body.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const WAIT: float = 8.0
const ROBOTICS_ENEMIES: Array[StringName] = [&"enemy_roomba", &"enemy_turret", &"enemy_drone", &"enemy_flock_camera"]

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
	Perception.players_invisible = false
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


func _spawn(enemy_id: StringName, at: Vector3, facing: Vector3 = Vector3.FORWARD) -> Enemy:
	var xform := Transform3D(Basis.looking_at(facing), at)
	return _spawner.spawn(enemy_id, xform, 1.0)


func test_robotics_has_its_own_enemies_loot_and_stock() -> void:
	var robotics := ContentRegistry.get_content(&"department_robotics") as DepartmentData
	var spawns: Array[StringName] = []
	for entry: WeightedIdData in robotics.enemy_spawns:
		spawns.append(entry.content_id)
	assert_eq(spawns, ROBOTICS_ENEMIES, "only Robotics' four enemies")
	assert_eq(robotics.loot_id, &"loot_robotics_small")
	assert_eq(robotics.stock_id, &"stock_robotics_vending")
	for enemy_id: StringName in ROBOTICS_ENEMIES:
		assert_not_null(_spawn(enemy_id, Vector3(0, 0.1, 0)), "%s spawns" % enemy_id)


func test_the_turret_stays_put_and_shoots() -> void:
	var player := _player(Vector3(0, 0, -10))
	var turret := _spawn(&"enemy_turret", Vector3(0, 0.1, 0))
	await wait_physics_frames(10)
	var start: Vector3 = turret.global_position
	var health: HealthComponent = HealthComponent.of(player)
	await wait_until(func() -> bool: return health.get_current() < 100.0, WAIT)
	assert_lt(health.get_current(), 100.0, "its laser bolts hit you")
	assert_lt(Vector2(turret.global_position.x - start.x, turret.global_position.z - start.z).length(), 0.05,
		"and it never moved")


func test_the_drone_flies_and_shoots() -> void:
	var player := _player(Vector3(0, 0, -10))
	var drone := _spawn(&"enemy_drone", Vector3(0, 0.1, 0))
	var health: HealthComponent = HealthComponent.of(player)
	await wait_until(func() -> bool: return health.get_current() < 100.0, WAIT)
	assert_lt(health.get_current(), 100.0, "it zaps you")
	assert_gt(drone.global_position.y, 1.0, "from the air")


func test_the_flock_camera_calls_every_robot_near_it() -> void:
	Perception.players_invisible = true
	var player := _player(Vector3(0, 0, -6))
	var camera := _spawn(&"enemy_flock_camera", Vector3(0, 0.1, 0))
	var roomba := _spawn(&"enemy_roomba", Vector3(8, 0.1, 6), Vector3.BACK)
	var far := _spawn(&"enemy_roomba", Vector3(25, 0.1, 25), Vector3.BACK)
	await wait_physics_frames(3)
	var alarm := camera.get_node(^"Behaviour") as AlarmBehaviour
	var told: int = alarm.sound_alarm(camera, player)
	assert_eq(told, 1, "one robot close enough to hear it")
	assert_eq(roomba.get_target(), player, "the near roomba comes for you")
	assert_null(far.get_target(), "the far one doesn't hear it")
	var health: HealthComponent = HealthComponent.of(player)
	await wait_seconds(1.0)
	assert_eq(health.get_current(), 100.0, "the camera itself never hurts you")
