extends GutTest
## RunState and RunDifficulty (docs/systems/game_flow.md).


func test_run_state_survives_the_network() -> void:
	var run := RunState.new()
	run.run_seed = 1234
	run.department_ids = [&"department_a", &"department_b"] as Array[StringName]
	run.floor_number = 7
	run.department_index = 1
	run.floor_in_department = 1
	run.is_boss_floor = false
	var copy: RunState = RunState.from_dict(run.to_dict())
	assert_eq(copy.run_seed, 1234)
	assert_eq(copy.department_ids, [&"department_a", &"department_b"] as Array[StringName])
	assert_eq(copy.floor_number, 7)
	assert_eq(copy.get_department_id(), &"department_b")


func test_difficulty_scales_with_player_count() -> void:
	var config := GameConfig.new()
	config.base_enemy_budget = 10
	config.enemy_budget_per_floor = 0.0
	config.enemy_budget_per_extra_player = 0.5
	config.enemy_health_per_extra_player = 0.2
	config.boss_health_per_extra_player = 0.5
	config.floor_tasks_base = 1
	config.extra_floor_task_every_players = 3
	assert_eq(RunDifficulty.enemy_budget(1, 1, config), 10, "solo: the base")
	assert_eq(RunDifficulty.enemy_budget(1, 4, config), 25, "4 players: +50% each extra")
	assert_eq(RunDifficulty.enemy_budget(1, 8, config), 45)
	assert_almost_eq(RunDifficulty.enemy_health_multiplier(1, config), 1.0, 0.001)
	assert_almost_eq(RunDifficulty.enemy_health_multiplier(4, config), 1.6, 0.001)
	assert_almost_eq(RunDifficulty.boss_health_multiplier(8, config), 4.5, 0.001)
	assert_eq(RunDifficulty.floor_task_count(1, config), 1)
	assert_eq(RunDifficulty.floor_task_count(4, config), 1)
	assert_eq(RunDifficulty.floor_task_count(5, config), 2, "one extra task at 2 + 3 players")
	assert_eq(RunDifficulty.floor_task_count(8, config), 3)


func test_deeper_floors_have_bigger_budgets() -> void:
	var config := GameConfig.new()
	config.base_enemy_budget = 10
	config.enemy_budget_per_floor = 0.1
	assert_eq(RunDifficulty.enemy_budget(1, 1, config), 10)
	assert_eq(RunDifficulty.enemy_budget(6, 1, config), 15)
