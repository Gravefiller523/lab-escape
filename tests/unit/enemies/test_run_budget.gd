extends GutTest
## NEW 2026-11-13 (floor generation step 6c, Zachary: keep floor 1's crowding): the enemy budget grows across the
## whole run, not just within each department block, because floors keep getting bigger.

const DEPARTMENT_ID: StringName = &"department_robotics"
const RUN_SEED: int = 4242

var _world: Node3D


func before_each() -> void:
	Level.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	_world.add_child(body)


func after_each() -> void:
	Enemies.despawn_all()


func test_the_live_budget_grows_every_floor_of_the_run() -> void:
	var floors: int = Config.game.run_floor_count
	assert_gt(floors, Config.game.boss_every_floors, "a run has more than one department block")
	for floor_number: int in range(1, floors):
		assert_true(RunDifficulty.enemy_budget(floor_number + 1, 1) >= RunDifficulty.enemy_budget(floor_number, 1),
			"floor %d's budget is no smaller than floor %d's" % [floor_number + 1, floor_number])
	var block: int = Config.game.boss_every_floors
	assert_gt(RunDifficulty.enemy_budget(1 + block * 2, 1), RunDifficulty.enemy_budget(1 + block, 1),
		"the first floor of the third block gets more than the first floor of the second")
	assert_gt(RunDifficulty.enemy_budget(1 + block, 1), RunDifficulty.enemy_budget(1, 1),
		"the first floor of the second block gets more than floor 1")


func test_spawn_floor_spends_the_run_floors_budget() -> void:
	var department := ContentRegistry.get_content(DEPARTMENT_ID) as DepartmentData
	var markers: Array[RoomMarker] = []
	for index: int in 6:
		var marker := RoomMarker.new()
		marker.kind = &"enemy_spawn"
		marker.position = Vector3(-10.0 + 4.0 * index, 0.5, 0.0)
		_world.add_child(marker)
		markers.append(marker)
	var late_floor: int = 1 + Config.game.boss_every_floors * 2
	var old_way: int = Enemies.spawn_floor(1, department, RUN_SEED, markers).size()
	Enemies.despawn_all()
	await wait_physics_frames(2)
	var new_way: int = Enemies.spawn_floor(1, department, RUN_SEED, markers, late_floor).size()
	assert_gt(old_way, 0, "the first floor of a block gets enemies")
	assert_gt(new_way, old_way, "the same block floor deep in the run gets more enemies")
	var expected: int = EnemiesService.plan_spawns(EnemiesService.pool_for(department), 1,
		RunDifficulty.enemy_budget(late_floor, Net.get_player_count()),
		SeededRng.make(RUN_SEED, &"enemy_spawns", 1)).size()
	assert_eq(new_way, expected, "it spends the run floor's budget on the block floor's enemy types")
