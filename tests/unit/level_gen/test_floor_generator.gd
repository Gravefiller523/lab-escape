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


## NEW 2026-10-31 (step 4a): Robotics floors.
func _robotics() -> DepartmentData:
	return ContentRegistry.get_content(&"department_robotics") as DepartmentData


func _kinds_on(layout: FloorLayout) -> Dictionary[StringName, int]:
	var kinds: Dictionary[StringName, int] = {}
	for placement: RoomPlacement in layout.placements:
		var room: RoomData = _room(placement)
		kinds[room.room_kind] = kinds.get(room.room_kind, 0) + 1
	return kinds


func test_robotics_floors_have_their_required_rooms() -> void:
	var robotics: DepartmentData = _robotics()
	assert_not_null(robotics, "content/departments/department_robotics.tres")
	var department_rooms: int = 0
	var shared_rooms: int = 0
	for floor_seed: int in 40:
		var floor_number: int = 1 + floor_seed % 18
		var layout: FloorLayout = FloorGenerator.generate_from_seed(robotics, floor_number, floor_seed * 13 + 5, Config.floor_gen)
		assert_false(layout.is_fallback, "floor %d seed %d: a real floor\n%s" % [floor_number, floor_seed, "\n".join(layout.log_lines)])
		var kinds: Dictionary[StringName, int] = _kinds_on(layout)
		for required: String in robotics.required_room_kinds:
			if required == "lift":
				continue
			assert_eq(kinds.get(StringName(required), 0), 1, "floor %d seed %d: exactly one %s" % [floor_number, floor_seed, required])
		assert_eq(_room(layout.placements[1]).id, &"room_tile_robotics_welcome_center", "Robotics floors use its welcome center")
		for placement: RoomPlacement in layout.placements:
			var room: RoomData = _room(placement)
			if room.tile_role != TileStandards.ROLE_ROOM:
				continue
			if room.department_ids.has(robotics.id):
				department_rooms += 1
			else:
				shared_rooms += 1
	assert_gt(department_rooms, shared_rooms, "most rooms are Robotics rooms (shared share %.2f)" % Config.floor_gen.shared_room_share)
	assert_gt(shared_rooms, 0, "but offices, storage and break rooms turn up too")


func test_room_types_respect_max_per_floor() -> void:
	var robotics: DepartmentData = _robotics()
	for floor_seed: int in 20:
		var kinds: Dictionary[StringName, int] = _kinds_on(FloorGenerator.generate_from_seed(robotics, 18, floor_seed, Config.floor_gen))
		for room_type: RoomTypeData in robotics.room_types:
			if room_type.max_per_floor > 0:
				assert_lte(kinds.get(room_type.room_kind, 0), room_type.max_per_floor, "seed %d: %s" % [floor_seed, room_type.room_kind])


func test_other_departments_never_get_robotics_rooms() -> void:
	var botany := ContentRegistry.get_content(&"department_botany") as DepartmentData
	for floor_seed: int in 10:
		var layout: FloorLayout = FloorGenerator.generate_from_seed(botany, 3, floor_seed, Config.floor_gen)
		for placement: RoomPlacement in layout.placements:
			assert_false(_room(placement).department_ids.has(&"department_robotics"), "seed %d: %s" % [floor_seed, placement.room_id])


func test_robotics_floors_get_the_palette_and_room_signs() -> void:
	var robotics: DepartmentData = _robotics()
	var layout: FloorLayout = FloorGenerator.generate_from_seed(robotics, 4, 2024, Config.floor_gen)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(layout, parent)
	var wall: Material = robotics.palette["wall"]
	var painted: int = 0
	var signs: PackedStringArray = PackedStringArray()
	for node: Node in RoomShape.all_children(parent):
		if node is CSGBox3D and node.get_meta(TileStandards.MATERIAL_SLOT_META, &"") == &"wall":
			assert_eq((node as CSGBox3D).material, wall, "%s has the Robotics wall material" % node.get_path())
			painted += 1
		var label := node as Label3D
		if label != null and label.name == "Sign":
			signs.append(label.text)
	assert_gt(painted, 10, "walls take the Robotics palette")
	assert_true(signs.has("ASSEMBLY FLOOR"), "the assembly floor has its sign (%s)" % ", ".join(signs))
	assert_true(signs.has("SECURITY"), "the welcome center's security room sign")
	Level.clear()


## NEW 2026-10-31 (step 4b): incident and damage.
func _robotics_floor(floor_seed: int, floor_number: int) -> FloorLayout:
	return FloorGenerator.generate_from_seed(_robotics(), floor_number, floor_seed, Config.floor_gen)


func _links_of(layout: FloorLayout) -> Dictionary[int, Array]:
	var links: Dictionary[int, Array] = {}
	for link: Dictionary in LevelGenerator.doorway_links(layout, _unit()):
		if not link["connected"]:
			continue
		var next: Vector2i = (link["cell"] as Vector2i) + (link["dir"] as Vector2i)
		for other: Dictionary in LevelGenerator.doorway_links(layout, _unit()):
			if other["cell"] == next and other["dir"] == -(link["dir"] as Vector2i):
				var a: int = link["placement"]
				if not links.has(a):
					links[a] = []
				links[a].append(other["placement"])
	return links


func test_every_tile_gets_a_damage_level_and_the_start_stays_calm() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	var start_cap: int = TileStandards.DAMAGE_LEVELS.find(tuning.start_area_max_damage)
	var damaged: int = 0
	for floor_seed: int in 20:
		var layout: FloorLayout = _robotics_floor(floor_seed, 1 + floor_seed % 18)
		assert_eq(layout.damage.size(), layout.placements.size(), "seed %d: a level for every tile" % floor_seed)
		assert_ne(layout.incident_id, &"", "seed %d: an incident" % floor_seed)
		assert_true(layout.origin >= 0 and _room(layout.placements[layout.origin]).tile_role == TileStandards.ROLE_ROOM,
			"seed %d: it starts in a room" % floor_seed)
		assert_lte(layout.damage[0], start_cap, "seed %d: the elevator is at most %s" % [floor_seed, tuning.start_area_max_damage])
		assert_lte(layout.damage[1], start_cap, "seed %d: the welcome center and security room too" % floor_seed)
		for level: int in layout.damage:
			if level > 0:
				damaged += 1
	assert_gt(damaged, 20, "floors do get damaged")


func test_damage_is_worst_near_the_origin() -> void:
	var nearer: int = 0
	var checks: int = 0
	for floor_seed: int in 15:
		var layout: FloorLayout = _robotics_floor(floor_seed, 12)
		var origin_level: int = layout.damage[layout.origin]
		var calmest: int = 3
		for level: int in layout.damage:
			calmest = mini(calmest, level)
		checks += 1
		if origin_level > calmest:
			nearer += 1
	assert_gt(float(nearer), float(checks) * 0.8, "the incident's room is more damaged than the calmest tile (%d of %d floors)" % [nearer, checks])


func test_robotics_incidents_start_in_their_rooms() -> void:
	var robotics: DepartmentData = _robotics()
	var fitting: int = 0
	for floor_seed: int in 20:
		var layout: FloorLayout = _robotics_floor(floor_seed, 6)
		for incident: IncidentData in robotics.incidents:
			if incident.id == layout.incident_id and incident.origin_room_kinds.has(String(_room(layout.placements[layout.origin]).room_kind)):
				fitting += 1
	assert_gt(fitting, 10, "most incidents start in a room they fit (assembly floor, test bay, server room): %d of 20" % fitting)


func test_collapses_never_cut_anything_off() -> void:
	var collapses: int = 0
	for floor_seed: int in 40:
		var layout: FloorLayout = _robotics_floor(floor_seed, 18)
		for index: int in layout.collapsed:
			collapses += 1
			assert_eq(_room(layout.placements[index]).tile_role, TileStandards.ROLE_SECONDARY_HALL,
				"seed %d: only secondary hallways collapse (main hallways never)" % floor_seed)
			assert_eq(layout.damage[index], 3, "seed %d: only destroyed ones" % floor_seed)
		var links: Dictionary[int, Array] = _links_of(layout)
		var reached: Dictionary[int, bool] = {0: true}
		var queue: Array[int] = [0]
		while not queue.is_empty():
			var at: int = queue.pop_back()
			for next: Variant in links.get(at, []):
				var index: int = next
				if not reached.has(index) and not layout.collapsed.has(index):
					reached[index] = true
					queue.append(index)
		assert_eq(reached.size(), layout.placements.size() - layout.collapsed.size(),
			"seed %d: every tile but the collapsed ones can still be reached (and the security room)" % floor_seed)
	gut.p("collapsed hallway pieces over 40 floor-18 floors: %d" % collapses)


func test_hazards_only_in_badly_damaged_rooms() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	var min_level: int = TileStandards.DAMAGE_LEVELS.find(tuning.hazard_min_damage)
	var total: int = 0
	for floor_seed: int in 20:
		var floor_number: int = 1 + floor_seed % 18
		var layout: FloorLayout = _robotics_floor(floor_seed, floor_number)
		var keys: PackedStringArray = layout.active_markers.get(&"hazard", PackedStringArray())
		total += keys.size()
		assert_lte(keys.size(), int(FloorGenTuning.grown(float(tuning.hazards_max), tuning.hazards_per_floor,
			float(tuning.hazards_cap), floor_number)), "seed %d: not more than V12 allows" % floor_seed)
		for key: String in keys:
			var placement: int = key.get_slice("/", 0).to_int()
			assert_gte(layout.damage[placement], min_level, "seed %d: %s is in a %s room" % [floor_seed, key, tuning.hazard_min_damage])
			assert_true(layout.marker_params.has(key) and layout.marker_params[key].has("hazard_kind"), "%s knows its kind" % key)
	assert_gt(total, 0, "some floors have hazards")


func test_debug_origin_near_and_forced_damage() -> void:
	FloorGenerator.debug_origin = &"near"
	FloorGenerator.debug_damage = &"heavy"
	var layout: FloorLayout = _robotics_floor(99, 3)
	FloorGenerator.debug_origin = &""
	FloorGenerator.debug_damage = &""
	var normal: FloorLayout = _robotics_floor(99, 3)
	var links: Dictionary[int, Array] = _links_of(layout)
	assert_ne(layout.origin, normal.origin, "near moves the incident")
	for index: int in range(2, layout.damage.size()):
		assert_eq(layout.damage[index], 2, "forced damage on every tile but the start area")
	assert_lte(layout.damage[1], TileStandards.DAMAGE_LEVELS.find(Config.floor_gen.start_area_max_damage))
	assert_true(links.has(0), "a sane floor")


func test_built_floor_shows_its_damage() -> void:
	var layout: FloorLayout = _robotics_floor(7, 12)
	var copy: FloorLayout = FloorLayout.from_dict(layout.to_dict())
	assert_eq(copy.damage, layout.damage, "damage goes to every PC")
	assert_eq(copy.marker_params, layout.marker_params)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var parent := Node3D.new()
	viewport.add_child(parent)
	Level.build(copy, parent)
	var rooms: Array[Node3D] = Level.get_room_nodes()
	for index: int in rooms.size():
		var level: StringName = copy.damage_level(index)
		for overlay_level: StringName in TileStandards.OVERLAY_NODES:
			var overlay: Node3D = TileStandards.overlay_of(rooms[index], overlay_level)
			if overlay_level == level:
				assert_not_null(overlay, "tile %d keeps its %s overlay" % [index, level])
				if overlay != null:
					assert_true(overlay.visible)
			else:
				assert_true(overlay == null or overlay.is_queued_for_deletion(), "tile %d drops its %s overlay" % [index, overlay_level])
		assert_not_null(rooms[index].get_node_or_null("LightFlicker"), "tile %d's lights follow its damage" % index)
		if copy.collapsed.has(index):
			assert_not_null(rooms[index].get_node_or_null("CollapseRubble"), "tile %d is filled with rubble" % index)
	for key: String in copy.marker_params:
		var found: bool = false
		for marker: RoomMarker in Level.get_markers(&"prop_spawn") + Level.get_markers(&"hazard"):
			var params: Dictionary = copy.marker_params[key]
			if params.has("prop_id") and marker.params.get("prop_id", "") == params["prop_id"]:
				found = true
			if params.has("hazard_kind") and marker.params.get("hazard_kind", "") == params["hazard_kind"]:
				found = true
		assert_true(found, "%s's settings reached its marker" % key)
	Level.clear()
