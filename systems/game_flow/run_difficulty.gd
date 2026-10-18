class_name RunDifficulty
extends RefCounted
## How much harder a floor is with more players and deeper floors. Every number comes from
## Config.game (the "Difficulty" and "Floors" groups); pass a config in tests.


## How many "points" of enemies a floor spawns (enemies spend them by their cost).
static func enemy_budget(floor_number: int, player_count: int, config: GameConfig = null) -> int:
	var game: GameConfig = _game(config)
	var depth: float = 1.0 + game.enemy_budget_per_floor * float(maxi(floor_number, 1) - 1)
	var players: float = 1.0 + game.enemy_budget_per_extra_player * float(_extra_players(player_count))
	return roundi(float(game.base_enemy_budget) * depth * players)


static func enemy_health_multiplier(player_count: int, config: GameConfig = null) -> float:
	return 1.0 + _game(config).enemy_health_per_extra_player * float(_extra_players(player_count))


static func boss_health_multiplier(player_count: int, config: GameConfig = null) -> float:
	return 1.0 + _game(config).boss_health_per_extra_player * float(_extra_players(player_count))


## Co-op floor tasks on a floor: the base, plus one for every N players beyond the first 2.
static func floor_task_count(player_count: int, config: GameConfig = null) -> int:
	var game: GameConfig = _game(config)
	var extra: int = 0
	if game.extra_floor_task_every_players > 0:
		extra = floori(float(maxi(player_count - 2, 0)) / float(game.extra_floor_task_every_players))
	return game.floor_tasks_base + extra


static func _extra_players(player_count: int) -> int:
	return maxi(player_count, 1) - 1


static func _game(config: GameConfig) -> GameConfig:
	return config if config != null else Config.game
