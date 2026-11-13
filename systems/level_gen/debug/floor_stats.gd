class_name FloorStats
extends RefCounted
## NEW 2026-11-13 (floor generation step 6c): numbers about generated floors, for tuning
## config/floor_gen_tuning.tres from data instead of guesses. measure() turns one FloorLayout into one row of
## numbers; to_csv() and summary() turn many rows into a CSV file and a short markdown summary (averages per
## floor number, per department and overall, and the checks against the plan's intent). The runner scene
## systems/level_gen/test/floor_stats_runner.tscn generates the floors and writes the files. Debug only: no
## game system uses it.

## The CSV's columns, in order (every row from measure() has these keys).
const COLUMNS: PackedStringArray = ["department", "floor", "seed", "boss_floor", "attempt", "fallback", "tiles",
	"rooms", "hall_tiles", "longest_path_m", "branch_depth", "loops", "parts", "part_path_min_m", "part_path_mean_m",
	"part_path_max_m", "part_path_min_share", "doors", "door_broken", "door_pry", "door_power", "door_debris",
	"door_keycard", "locks", "keycards", "enemies", "enemies_per_room", "enemy_budget", "enemies_spawned",
	"enemies_spawned_per_room", "hazards", "damaged_share", "heavy_share", "cameras", "cameras_broken", "plan_ms", "build_ms"]
## Columns averaged in the summary tables.
const SUMMARY_COLUMNS: PackedStringArray = ["rooms", "tiles", "longest_path_m", "parts", "part_path_mean_m",
	"part_path_min_share", "locks", "door_pry", "door_power", "door_debris", "door_keycard", "keycards", "enemies",
	"enemies_per_room", "enemies_spawned", "enemies_spawned_per_room", "hazards", "damaged_share", "heavy_share",
	"cameras", "loops", "attempt", "plan_ms", "build_ms"]


## One floor's numbers. plan_ms and build_ms are filled in by whoever timed them (-1 = not measured).
## `player_count` sets the enemy budget; `budget_from_run_floor` false works the budget out from the floor's place in
## its department block, as the spawner did before step 6c (for "before" numbers).
static func measure(layout: FloorLayout, tuning: FloorGenTuning, player_count: int = 1,
		budget_from_run_floor: bool = true) -> Dictionary:
	var row: Dictionary = {}
	row["department"] = String(layout.department_id)
	row["floor"] = layout.floor_number
	row["seed"] = layout.floor_seed
	row["boss_floor"] = 1 if _is_boss_floor(layout.floor_number) else 0
	row["attempt"] = layout.attempt
	row["fallback"] = 1 if layout.is_fallback else 0
	row["tiles"] = layout.placements.size()
	var rooms: int = 0
	var halls: int = 0
	for placement: RoomPlacement in layout.placements:
		var room := ContentRegistry.get_content(placement.room_id) as RoomData
		if room == null:
			continue
		if room.tile_role == TileStandards.ROLE_ROOM:
			rooms += 1
		elif room.tile_role in [TileStandards.ROLE_MAIN_HALL, TileStandards.ROLE_SECONDARY_HALL]:
			halls += 1
	row["rooms"] = rooms
	row["hall_tiles"] = halls
	var longest: float = float(layout.stats.get("longest_path_m", 0))
	row["longest_path_m"] = longest
	row["branch_depth"] = layout.stats.get("max_depth", 0)
	row["loops"] = layout.loops.size()
	var paths: Array[float] = []
	for path: PackedInt32Array in layout.lift_part_paths:
		paths.append(path_metres(layout, path, tuning.grid_unit))
	row["parts"] = layout.lift_parts.size()
	row["part_path_min_m"] = _min(paths)
	row["part_path_mean_m"] = _mean(paths)
	row["part_path_max_m"] = _max(paths)
	row["part_path_min_share"] = _min(paths) / longest if longest > 0.0 and not paths.is_empty() else 0.0
	var by_type: Dictionary[int, int] = {}
	for door: Array in layout.doors:
		var door_type: int = door[3]
		by_type[door_type] = by_type.get(door_type, 0) + 1
	row["doors"] = layout.doors.size()
	row["door_broken"] = by_type.get(FloorGenerator.DOOR_BROKEN, 0)
	row["door_pry"] = by_type.get(FloorGenerator.DOOR_PRY, 0)
	row["door_power"] = by_type.get(FloorGenerator.DOOR_POWER, 0)
	row["door_debris"] = by_type.get(FloorGenerator.DOOR_DEBRIS, 0)
	row["door_keycard"] = by_type.get(FloorGenerator.DOOR_KEYCARD, 0)
	row["locks"] = int(row["door_pry"]) + int(row["door_power"]) + int(row["door_debris"]) + int(row["door_keycard"])
	var keycards: int = 0
	for item: Array in layout.door_items:
		if str(item[0]).begins_with("keycard"):
			keycards += 1
	row["keycards"] = keycards
	var enemies: int = layout.active_markers.get(&"enemy_spawn", PackedStringArray()).size()
	row["enemies"] = enemies
	row["enemies_per_room"] = float(enemies) / float(rooms) if rooms > 0 else 0.0
	var spawned: Array[int] = spawned_enemies(layout, player_count, budget_from_run_floor)
	row["enemy_budget"] = spawned[0]
	row["enemies_spawned"] = spawned[1]
	row["enemies_spawned_per_room"] = float(spawned[1]) / float(rooms) if rooms > 0 else 0.0
	row["hazards"] = layout.active_markers.get(&"hazard", PackedStringArray()).size()
	var damaged: int = 0
	var heavy: int = 0
	for level: int in layout.damage:
		if level >= 1:
			damaged += 1
		if level >= 2:
			heavy += 1
	var count: float = float(maxi(layout.damage.size(), 1))
	row["damaged_share"] = float(damaged) / count
	row["heavy_share"] = float(heavy) / count
	var broken: int = 0
	for camera: Array in layout.cameras:
		if camera[2] as bool:
			broken += 1
	row["cameras"] = layout.cameras.size()
	row["cameras_broken"] = broken
	row["plan_ms"] = -1.0
	row["build_ms"] = -1.0
	return row


## The enemies the spawner would put on this floor, worked out the way it does (Enemies.spawn_floor on floor_ready):
## [budget, how many enemies]. The enemy types allowed follow the floor's place in its department block.
static func spawned_enemies(layout: FloorLayout, player_count: int, budget_from_run_floor: bool = true) -> Array[int]:
	var block: int = Config.game.boss_every_floors
	var floor_in_department: int = (layout.floor_number - 1) % block + 1 if block > 0 else layout.floor_number
	var budget_floor: int = layout.floor_number if budget_from_run_floor else floor_in_department
	var budget: int = RunDifficulty.enemy_budget(budget_floor, player_count)
	var department := ContentRegistry.get_content(layout.department_id) as DepartmentData
	var rng: RandomNumberGenerator = SeededRng.make(layout.floor_seed, &"enemy_spawns", floor_in_department)
	var plan: Array[StringName] = EnemiesService.plan_spawns(EnemiesService.pool_for(department), floor_in_department,
		budget, rng)
	var result: Array[int] = [budget, plan.size()]
	return result


## Walking distance (metres) along a path of placements, through the tiles' centres (as the generator measures).
static func path_metres(layout: FloorLayout, path: PackedInt32Array, unit: float) -> float:
	var total: float = 0.0
	for step: int in range(1, path.size()):
		total += _centre(layout, path[step - 1], unit).distance_to(_centre(layout, path[step], unit))
	return total


## The rows as CSV text (a header line, then one line per row).
static func to_csv(rows: Array[Dictionary]) -> String:
	var lines := PackedStringArray([",".join(COLUMNS)])
	for row: Dictionary in rows:
		var cells := PackedStringArray()
		for column: String in COLUMNS:
			cells.append(_cell(row.get(column, "")))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


## Averages of `columns` over the rows, grouped by the value of `key` (e.g. "floor"), as a markdown table.
static func table(rows: Array[Dictionary], key: String, columns: PackedStringArray = SUMMARY_COLUMNS) -> String:
	var groups: Dictionary[String, Array] = {}
	var order: Array[String] = []
	for row: Dictionary in rows:
		var group: String = str(row.get(key, ""))
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append(row)
	var lines := PackedStringArray()
	lines.append("| %s | n | %s |" % [key, " | ".join(columns)])
	var rule := PackedStringArray(["---", "---"])
	for column: String in columns:
		rule.append("---")
	lines.append("| %s |" % " | ".join(rule))
	for group: String in order:
		var cells := PackedStringArray([group, str(groups[group].size())])
		for column: String in columns:
			cells.append(_cell(average(groups[group], column)))
		lines.append("| %s |" % " | ".join(cells))
	return "\n".join(lines)


## The average of one column over rows (-1 values, "not measured", are left out).
static func average(rows: Array, column: String) -> float:
	var total: float = 0.0
	var count: int = 0
	for row: Variant in rows:
		var value: float = float((row as Dictionary).get(column, -1.0))
		if value < 0.0:
			continue
		total += value
		count += 1
	return total / float(count) if count > 0 else -1.0


## How many rows match a test (for the checks in the summary).
static func count_where(rows: Array[Dictionary], test: Callable) -> int:
	var found: int = 0
	for row: Dictionary in rows:
		if test.call(row):
			found += 1
	return found


static func _is_boss_floor(floor_number: int) -> bool:
	var every: int = Config.game.boss_every_floors if Config.game != null else 0
	return every > 0 and floor_number % every == 0


static func _centre(layout: FloorLayout, index: int, unit: float) -> Vector2:
	var placement: RoomPlacement = layout.placements[index]
	var room := ContentRegistry.get_content(placement.room_id) as RoomData
	var size := Vector2i.ONE
	if room != null:
		size = RoomShape.of(room, unit).rotated_size(placement.rotation_steps)
	return (Vector2(placement.cell.x, placement.cell.z) + Vector2(size) / 2.0) * unit


static func _cell(value: Variant) -> String:
	if value is float:
		return "%.2f" % (value as float)
	return str(value)


static func _min(values: Array[float]) -> float:
	return values.min() if not values.is_empty() else 0.0


static func _max(values: Array[float]) -> float:
	return values.max() if not values.is_empty() else 0.0


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())
