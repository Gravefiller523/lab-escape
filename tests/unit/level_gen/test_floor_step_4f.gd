extends GutTest
## NEW 2026-11-10 (floor generation step 4f): enemy spawn spots in the plan, the safe fallback floor, nothing
## spawning before floor_ready, and enemies' navigation through the doors of a generated floor.

const WAIT: float = 5.0


func _tuning() -> FloorGenTuning:
	return Config.floor_gen


func _robotics() -> DepartmentData:
	return ContentRegistry.get_content(&"department_robotics") as DepartmentData


func _room(layout: FloorLayout, index: int) -> RoomData:
	return ContentRegistry.get_content(layout.placements[index].room_id) as RoomData


func test_enemy_spawn_spots_follow_the_budget_and_stay_out_of_the_start() -> void:
	var tuning: FloorGenTuning = _tuning()
	for floor_number: int in [1, 5, 10, 15]:
		var one: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, 2200 + floor_number, tuning, 1)
		var four: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, 2200 + floor_number, tuning, 4)
		var label: String = "floor %d" % floor_number
		var keys: PackedStringArray = one.active_markers.get(&"enemy_spawn", PackedStringArray())
		assert_gt(keys.size(), 0, "%s: some enemy spawn spots are on" % label)
		assert_gte(four.active_markers.get(&"enemy_spawn", PackedStringArray()).size(), keys.size(),
			"%s: more players, at least as many spots" % label)
		assert_eq(FloorLayout.from_dict(one.to_dict()).active_markers.get(&"enemy_spawn"), keys,
			"%s: other PCs get the same spots" % label)
		var part_rooms: Dictionary[int, bool] = {}
		for part: Array in one.lift_parts:
			part_rooms[int(part[2])] = true
		var rooms_with_enemies: Dictionary[int, bool] = {}
		for key: String in keys:
			var room: int = key.get_slice("/", 0).to_int()
			rooms_with_enemies[room] = true
			assert_ne(_room(one, room).tile_role, TileStandards.ROLE_TEMPLATE, "%s: none in the elevator or welcome center" % label)
		var quiet: bool = false
		for room: int in part_rooms:
			quiet = quiet or not rooms_with_enemies.has(room)
		assert_true(quiet, "%s: some lift part's room has no enemies (Q15)" % label)


func test_the_fallback_floor_is_safe_and_has_what_a_floor_needs() -> void:
	FloorGenerator.debug_force_fallback = true
	var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), 6, 777, _tuning())
	FloorGenerator.debug_force_fallback = false
	assert_true(layout.is_fallback, "the console switch builds the fallback floor")
	assert_true(layout.log_lines[layout.log_lines.size() - 1].begins_with("FALLBACK"), "and says so loudly")
	assert_eq(layout.main_halls.size(), 2, "two main hallways")
	var kinds: Dictionary[StringName, bool] = {}
	for index: int in layout.placements.size():
		kinds[_room(layout, index).room_kind] = true
	for kind_text: String in _robotics().required_room_kinds:
		if kind_text == "lift" or kind_text == "start":
			continue
		assert_true(kinds.has(StringName(kind_text)), "the required %s room is there" % kind_text)
	assert_gt(layout.lift_parts.size(), 0, "it has lift parts")
	for part: Array in layout.lift_parts:
		assert_eq(_room(layout, int(part[2])).tile_role, TileStandards.ROLE_ROOM, "parts are in rooms")
	for door: Array in layout.doors:
		assert_false(door[3] in [FloorGenerator.DOOR_PRY, FloorGenerator.DOOR_POWER, FloorGenerator.DOOR_KEYCARD],
			"no locks")
	assert_true(layout.collapsed.is_empty(), "no collapses")
	for level: int in layout.damage:
		assert_eq(level, 0, "no damage")
	var normal: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), 6, 777, _tuning())
	assert_false(normal.is_fallback, "switched off again, floors are normal")


func test_nothing_spawns_before_floor_ready() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var props := PropSpawner.new()
	props.name = "Props"
	root.add_child(props)
	FloorGenerator.debug_damage = &"heavy"
	var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), 9, 9191, _tuning())
	FloorGenerator.debug_damage = &""
	assert_false(layout.door_items.is_empty(), "this floor has keys and tools to spawn")
	Level.build(layout, root)
	await wait_physics_frames(5)
	assert_eq(props.get_props().size(), 0, "building the floor spawns nothing")
	EventBus.floor_ready.emit(9, layout.department_id)
	await wait_physics_frames(3)
	assert_gt(props.get_props().size(), 0, "floor_ready spawns the floor's things")
	await wait_until(func() -> bool: return not Enemies.is_baking_navigation(), WAIT)
	Level.clear()


func test_enemies_can_walk_through_open_doors_but_not_locked_ones() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	FloorGenerator.debug_damage = &"heavy"
	var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), 9, 9191, _tuning())
	FloorGenerator.debug_damage = &""
	Level.build(layout, root)
	await wait_physics_frames(3)
	var region: NavigationRegion3D = Enemies.bake_navigation(root.get_node(LevelService.ROOMS_NODE), true)
	assert_not_null(region.navigation_mesh, "the floor's navigation is baked")
	var rooms: Array[Node3D] = Level.get_room_nodes()
	var open_seen: int = 0
	var locked_seen: int = 0
	for index: int in layout.doors.size():
		var type: int = layout.doors[index][3]
		var holder := rooms[layout.doors[index][0]].get_node_or_null("Door%d" % index) as Node3D
		if holder == null:
			continue
		var middle: Vector3 = holder.global_position
		if type == FloorGenerator.DOOR_OPEN:
			open_seen += 1
			assert_true(_covered(region, middle), "door %d (open): enemies can path through its doorway" % index)
		elif type == FloorGenerator.DOOR_KEYCARD or type == FloorGenerator.DOOR_PRY or type == FloorGenerator.DOOR_POWER:
			locked_seen += 1
			assert_false(_covered(region, middle), "door %d (%s, locked): its doorway is shut to enemies" % [index,
				FloorGenerator.DOOR_NAMES[type]])
	assert_gt(open_seen, 0, "open doors were checked")
	assert_gt(locked_seen, 0, "locked doors were checked")
	Level.clear()


## Is this point (a doorway's middle, on the floor) inside a polygon of the navigation mesh?
func _covered(region: NavigationRegion3D, point: Vector3) -> bool:
	var mesh: NavigationMesh = region.navigation_mesh
	var vertices: PackedVector3Array = mesh.get_vertices()
	var at: Vector3 = region.global_transform.affine_inverse() * point
	for polygon_index: int in mesh.get_polygon_count():
		var polygon: PackedInt32Array = mesh.get_polygon(polygon_index)
		var flat := PackedVector2Array()
		var height: float = 0.0
		for vertex: int in polygon:
			flat.append(Vector2(vertices[vertex].x, vertices[vertex].z))
			height += vertices[vertex].y
		height /= float(maxi(polygon.size(), 1))
		if absf(height - at.y) < 0.8 and Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), flat):
			return true
	return false
