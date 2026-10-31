extends GutTest
## Tests for the floor generator (floor generation step 3, docs/systems/level_gen.md), using the 3 m tiles in
## content/rooms.

const SEEDS: int = 30


func _department() -> DepartmentData:
	var department := DepartmentData.new()
	department.id = &"department_test_floorgen"
	return department


func _floor(floor_seed: int, floor_number: int = 1) -> FloorLayout:
	return FloorGenerator.generate_from_seed(_department(), floor_number, floor_seed, Config.floor_gen)


func _unit() -> float:
	return Config.floor_gen.grid_unit


func _room(placement: RoomPlacement) -> RoomData:
	return ContentRegistry.get_content(placement.room_id) as RoomData


## Every grid cell the floor uses -> how many tiles cover it.
func _cells(layout: FloorLayout) -> Dictionary[Vector2i, int]:
	var cells: Dictionary[Vector2i, int] = {}
	for placement: RoomPlacement in layout.placements:
		var size: Vector2i = RoomShape.of(_room(placement), _unit()).rotated_size(placement.rotation_steps)
		for x: int in size.x:
			for z: int in size.y:
				var cell := Vector2i(placement.cell.x + x, placement.cell.z + z)
				cells[cell] = cells.get(cell, 0) + 1
	return cells


func test_same_seed_same_floor() -> void:
	assert_eq(_floor(1234).to_dict(), _floor(1234).to_dict())
	assert_ne(_floor(1234).to_dict(), _floor(4321).to_dict(), "another seed, another floor")


func test_floor_starts_with_the_elevator_and_the_welcome_center() -> void:
	for floor_seed: int in SEEDS:
		var layout: FloorLayout = _floor(floor_seed)
		assert_eq(layout.grid, RoomData.GRID_TILE)
		assert_eq(_room(layout.placements[0]).room_kind, &"lift", "seed %d: the elevator first, at (0, 0)" % floor_seed)
		assert_eq(layout.placements[0].cell, Vector3i.ZERO)
		assert_eq(_room(layout.placements[1]).room_kind, &"welcome_center", "seed %d: then the welcome center" % floor_seed)
		assert_false(layout.is_fallback, "seed %d: a real floor, not the fallback (%s)" % [floor_seed,
			"\n".join(layout.log_lines)])


func test_no_overlapping_tiles() -> void:
	for floor_seed: int in SEEDS:
		var cells: Dictionary[Vector2i, int] = _cells(_floor(floor_seed, 1 + floor_seed % 15))
		for cell: Vector2i in cells:
			if cells[cell] != 1:
				fail_test("seed %d: %d tiles cover cell %s" % [floor_seed, cells[cell], cell])
				return
	pass_test("one tile per cell on every floor")


func test_both_main_hallways_exist() -> void:
	for floor_seed: int in SEEDS:
		var layout: FloorLayout = _floor(floor_seed)
		assert_eq(layout.main_halls.size(), 2, "seed %d: two main hallways" % floor_seed)
		for hall: PackedInt32Array in layout.main_halls:
			var units: int = 0
			for index: int in hall:
				var room: RoomData = _room(layout.placements[index])
				assert_eq(room.tile_role, TileStandards.ROLE_MAIN_HALL, "seed %d: main hallways are main hallway pieces" % floor_seed)
				units += room.size_cells.z
			assert_gte(units, Config.floor_gen.min_main_hall_units, "seed %d: long enough" % floor_seed)


func test_rooms_reach_their_share_of_the_target() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	for floor_number: int in [1, 5, 12]:
		for floor_seed: int in 10:
			var layout: FloorLayout = _floor(floor_seed, floor_number)
			var rooms: int = 0
			for placement: RoomPlacement in layout.placements:
				if _room(placement).tile_role == TileStandards.ROLE_ROOM:
					rooms += 1
			var target: float = FloorGenTuning.grown(float(tuning.target_rooms_base), tuning.target_rooms_per_floor,
				float(tuning.target_rooms_cap), floor_number)
			assert_gte(rooms, ceili(target * tuning.min_rooms_share), "floor %d seed %d: %d rooms" % [floor_number, floor_seed, rooms])


func test_every_socket_is_joined_or_capped_when_built() -> void:
	for floor_seed: int in 5:
		var layout: FloorLayout = _floor(floor_seed)
		var links: Array[Dictionary] = LevelGenerator.doorway_links(layout, _unit())
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		add_child_autofree(viewport)
		var parent := Node3D.new()
		viewport.add_child(parent)
		Level.build(layout, parent)
		var caps: int = 0
		for node: Node in RoomShape.all_children(parent):
			if node.name.begins_with("Plug") or node.name.begins_with("Cap"):
				caps += 1
		var open: int = links.filter(func(link: Dictionary) -> bool: return link["connected"] == false).size()
		assert_eq(caps, open, "seed %d: every socket that leads nowhere has a cap" % floor_seed)
		# Every tile can be reached from the elevator through joined sockets.
		var reached: Dictionary[int, bool] = {0: true}
		var grew: bool = true
		while grew:
			grew = false
			for link: Dictionary in links:
				var from: int = link["placement"]
				if not link["connected"] or not reached.has(from):
					continue
				var next: Vector2i = (link["cell"] as Vector2i) + (link["dir"] as Vector2i)
				for other: Dictionary in links:
					var to: int = other["placement"]
					if other["cell"] == next and other["dir"] == -(link["dir"] as Vector2i) and not reached.has(to):
						reached[to] = true
						grew = true
		assert_eq(reached.size(), layout.placements.size(), "seed %d: every tile is reachable" % floor_seed)
		Level.clear()


func test_layout_round_trips_dict() -> void:
	var layout: FloorLayout = _floor(77, 6)
	var copy: FloorLayout = FloorLayout.from_dict(layout.to_dict())
	assert_eq(copy.to_dict(), layout.to_dict())
	assert_eq(copy.wings, layout.wings)
	assert_eq(copy.main_halls.size(), 2)
	assert_lt(var_to_bytes(layout.to_dict()).size(), 16000, "small enough to send to everyone in one message")


func test_branch_depth_and_loops_within_limits() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	for floor_number: int in [1, 4, 9]:
		for floor_seed: int in 10:
			var layout: FloorLayout = _floor(floor_seed, floor_number)
			assert_lte(layout.loops.size(), tuning.by_bracket(tuning.loops_by_bracket, floor_number),
				"floor %d seed %d: loops within the limit" % [floor_number, floor_seed])
			for placement: RoomPlacement in layout.placements:
				assert_lt(placement.wing, layout.wings.size(), "wings are named")


func test_many_seeds_never_crash() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	var fallbacks: int = 0
	for floor_seed: int in 500:
		var layout: FloorLayout = _floor(floor_seed * 7919 + 13, 1 + floor_seed % 18)
		assert_gt(layout.placements.size(), 2)
		if layout.is_fallback:
			fallbacks += 1
	assert_eq(fallbacks, 0, "no floor needed the safe fallback (%d did)" % fallbacks)
	assert_gt(tuning.max_attempts, 0)


func test_branch_depth_stays_within_the_limit() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	for floor_number: int in [1, 4, 9]:
		var limit: int = tuning.by_bracket(tuning.max_branch_depth_by_bracket, floor_number)
		for floor_seed: int in 20:
			var layout: FloorLayout = _floor(floor_seed, floor_number)
			assert_lte(layout.stats.get("max_depth", 0), limit, "floor %d seed %d: secondary hallways at most %d deep" % [
				floor_number, floor_seed, limit])


func test_only_a_share_of_prop_spots_is_used() -> void:
	var layout: FloorLayout = _floor(42, 5)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(layout, parent)
	var all_spots: int = 0
	for node: Node in RoomShape.all_children(parent):
		var marker := node as RoomMarker
		if marker != null and marker.kind == &"prop_spawn":
			all_spots += 1
	var used: Array[RoomMarker] = Level.get_markers(&"prop_spawn")
	assert_eq(used.size(), layout.active_markers[&"prop_spawn"].size(), "Level returns the markers the plan switched on")
	assert_lt(used.size(), all_spots, "not every prop spot gets a prop (%d of %d)" % [used.size(), all_spots])
	assert_eq(Level.get_markers(&"lift").size(), 1, "other kinds are all on: the one lift marker")
	assert_gt(Level.get_markers(&"lift_part").size(), 2, "places for lift parts")
	assert_gt(Level.get_markers(&"charger").size(), 0, "a place for the battery charger")
	assert_eq(Level.get_room_for_position(Level.get_markers(&"lift")[0].global_position).room_kind, &"lift",
		"the room lookup works on the 3 m grid")
	Level.clear()


func test_runs_use_the_new_generator() -> void:
	var layout: FloorLayout = FloorGenerator.generate_for_run(_department(), 3, 555, 2)
	assert_eq(layout.grid, RoomData.GRID_TILE)
	assert_same(FloorGenerator.last_layout, layout, "remembered for `floorgen log`")
	assert_true(FileAccess.file_exists(FloorGenerator.LOG_PATH), "the log is saved")
	assert_true(Config.floor_gen.use_floor_generator, "on by default")
	FloorGenerator.set_next_seed(98765)
	assert_eq(FloorGenerator.generate(_department(), 3, 555).floor_seed, 98765, "F9 / `floorgen <seed>` picks the seed")
	assert_ne(FloorGenerator.generate(_department(), 3, 555).floor_seed, 98765, "only for the next floor")
	assert_eq(FloorGenerator.generate_from_seed(_department(), 3, 98765, Config.floor_gen).to_dict(),
		FloorGenerator.generate_from_seed(_department(), 3, 98765, Config.floor_gen).to_dict(), "a seed you liked comes back")


func test_hallway_pieces_are_recognised() -> void:
	var kinds: Dictionary[StringName, StringName] = {&"room_tile_main_straight": FloorGenerator.PIECE_STRAIGHT,
		&"room_tile_main_corner": FloorGenerator.PIECE_CORNER, &"room_tile_main_t": FloorGenerator.PIECE_T,
		&"room_tile_main_end": FloorGenerator.PIECE_END, &"room_tile_hall_cross": FloorGenerator.PIECE_CROSS,
		&"room_tile_hall_filler": FloorGenerator.PIECE_STRAIGHT}
	for id: StringName in kinds:
		assert_eq(FloorGenerator.piece_kind(ContentRegistry.get_content(id) as RoomData), kinds[id], String(id))


## NEW 2026-10-31 (Zachary's playtest): every floor has enough distinct places for the broken lift parts, and a
## battery charger spot (the welcome center always has one).
func test_every_floor_has_room_for_its_lift_parts_and_a_charger() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	for floor_seed: int in 60:
		var floor_number: int = 1 + floor_seed % 18
		var layout: FloorLayout = _floor(floor_seed * 31 + 7, floor_number)
		var parts: int = 0
		var chargers: int = 0
		for placement: RoomPlacement in layout.placements:
			for marker: Dictionary in RoomShape.of(_room(placement), _unit()).markers:
				if marker["kind"] == &"lift_part":
					parts += 1
				elif marker["kind"] == &"charger":
					chargers += 1
		assert_gte(parts, maxi(tuning.by_bracket(tuning.parts_max_by_bracket, floor_number), 3),
			"floor %d seed %d: a separate spot for every broken part (%d spots)" % [floor_number, floor_seed, parts])
		assert_gt(chargers, 0, "floor %d seed %d: a battery charger spot" % [floor_number, floor_seed])
