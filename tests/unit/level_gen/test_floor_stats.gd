extends GutTest
## NEW 2026-11-13 (floor generation step 6c): the floor tuning stats tool (FloorStats) measures floors right.


func _floor(department_id: StringName, floor_number: int, floor_seed: int) -> FloorLayout:
	var department := ContentRegistry.get_content(department_id) as DepartmentData
	return FloorGenerator.generate_from_seed(department, floor_number, floor_seed, Config.floor_gen)


func test_a_floor_gives_one_row_with_every_column() -> void:
	var layout: FloorLayout = _floor(&"department_robotics", 6, 6161)
	var row: Dictionary = FloorStats.measure(layout, Config.floor_gen)
	for column: String in FloorStats.COLUMNS:
		assert_true(row.has(column), "the row has %s" % column)
	assert_eq(row["department"], "department_robotics")
	assert_eq(row["floor"], 6)
	assert_eq(row["tiles"], layout.placements.size(), "every tile counted")
	assert_gt(int(row["rooms"]), 0, "it has rooms")
	assert_lt(int(row["rooms"]) + int(row["hall_tiles"]), int(row["tiles"]) + 1, "rooms and hallways are tiles")
	assert_gt(float(row["longest_path_m"]), 0.0, "the generator records its longest walk")
	assert_eq(row["parts"], layout.lift_parts.size())
	assert_eq(row["cameras"], layout.cameras.size())


func test_part_walks_are_measured_along_their_paths() -> void:
	var layout: FloorLayout = _floor(&"department_zoology", 9, 9393)
	var row: Dictionary = FloorStats.measure(layout, Config.floor_gen)
	assert_gt(layout.lift_parts.size(), 0, "this floor has parts")
	var unit: float = Config.floor_gen.grid_unit
	for path: PackedInt32Array in layout.lift_part_paths:
		var metres: float = FloorStats.path_metres(layout, path, unit)
		assert_gt(metres, 0.0, "a part's walk back is longer than nothing")
		assert_true(metres + 0.01 >= float(row["part_path_min_m"]), "no walk is shorter than the minimum")
		assert_true(metres - 0.01 <= float(row["part_path_max_m"]), "no walk is longer than the maximum")
	assert_true(float(row["part_path_max_m"]) <= float(row["longest_path_m"]) + unit * 2.0,
		"no part is much farther than the floor's longest walk")


func test_door_counts_add_up() -> void:
	var layout: FloorLayout = _floor(&"department_botany", 11, 1111)
	var row: Dictionary = FloorStats.measure(layout, Config.floor_gen)
	var locks: int = 0
	for door: Array in layout.doors:
		if int(door[3]) in [FloorGenerator.DOOR_PRY, FloorGenerator.DOOR_POWER, FloorGenerator.DOOR_DEBRIS,
				FloorGenerator.DOOR_KEYCARD]:
			locks += 1
	assert_eq(row["locks"], locks, "locks are pry, power, debris and keycard doors")
	assert_eq(int(row["door_pry"]) + int(row["door_power"]) + int(row["door_debris"]) + int(row["door_keycard"]),
		locks)


func test_csv_and_tables() -> void:
	var rows: Array[Dictionary] = []
	for floor_number: int in [1, 2]:
		for floor_seed: int in [11, 12]:
			var row: Dictionary = FloorStats.measure(_floor(&"department_robotics", floor_number, floor_seed),
				Config.floor_gen)
			row["plan_ms"] = 10.0
			rows.append(row)
	var lines: PackedStringArray = FloorStats.to_csv(rows).strip_edges().split("\n")
	assert_eq(lines.size(), 5, "a header and one line per floor")
	assert_eq(lines[0], ",".join(FloorStats.COLUMNS), "the header is the columns")
	assert_eq(lines[1].split(",").size(), FloorStats.COLUMNS.size(), "every column filled")
	var by_floor: String = FloorStats.table(rows, "floor")
	assert_eq(by_floor.split("\n").size(), 4, "a header, a rule and one line per floor number")
	assert_almost_eq(FloorStats.average(rows, "plan_ms"), 10.0, 0.001)
	assert_eq(FloorStats.average(rows, "build_ms"), -1.0, "not measured stays out of the average")
