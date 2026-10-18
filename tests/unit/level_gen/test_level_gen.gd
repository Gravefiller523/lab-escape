extends GutTest
## Tests for level_gen (docs/systems/level_gen.md), using the grey-box rooms in content/rooms.

const SEEDS: int = 30


func _department() -> DepartmentData:
	var department := DepartmentData.new()
	department.id = &"department_test_levels"
	department.rooms_per_floor_min = 6
	department.rooms_per_floor_max = 10
	department.required_room_kinds = PackedStringArray(["lift"])
	return department


func _layout(run_seed: int, department: DepartmentData = null) -> FloorLayout:
	return LevelGenerator.generate(department if department != null else _department(), 1, 1, run_seed, 1)


func _kinds(layout: FloorLayout) -> Array[StringName]:
	var kinds: Array[StringName] = []
	for placement: RoomPlacement in layout.placements:
		kinds.append((ContentRegistry.get_content(placement.room_id) as RoomData).room_kind)
	return kinds


## Every grid cell a layout uses -> how many rooms cover it.
func _cells(layout: FloorLayout) -> Dictionary[Vector2i, int]:
	var cells: Dictionary[Vector2i, int] = {}
	for placement: RoomPlacement in layout.placements:
		var room := ContentRegistry.get_content(placement.room_id) as RoomData
		var size: Vector2i = RoomShape.of(room, Config.game.room_cell_size).rotated_size(placement.rotation_steps)
		for x: int in size.x:
			for z: int in size.y:
				var cell := Vector2i(placement.cell.x + x, placement.cell.z + z)
				cells[cell] = cells.get(cell, 0) + 1
	return cells


func test_same_seed_same_layout() -> void:
	assert_eq(_layout(1234).to_dict(), _layout(1234).to_dict())
	assert_ne(_layout(1234).to_dict(), _layout(4321).to_dict(), "another seed, another floor")


func test_required_rooms_always_present() -> void:
	for run_seed: int in SEEDS:
		var kinds: Array[StringName] = _kinds(_layout(run_seed))
		assert_eq(kinds[0], &"lift", "seed %d starts in the lift room (players arrive in the elevator)" % run_seed)
		assert_eq(kinds.count(&"lift"), 1)


func test_room_count_in_range() -> void:
	for run_seed: int in SEEDS:
		var count: int = _layout(run_seed).placements.size()
		assert_between(count, 6, 10, "seed %d" % run_seed)


func test_no_overlapping_rooms() -> void:
	for run_seed: int in SEEDS:
		for cell: Vector2i in _cells(_layout(run_seed)).keys():
			assert_eq(_cells(_layout(run_seed))[cell], 1, "seed %d: one room per cell" % run_seed)


func test_all_doorways_connected_or_sealed() -> void:
	for run_seed: int in 10:
		var layout: FloorLayout = _layout(run_seed)
		var links: Array[Dictionary] = LevelGenerator.doorway_links(layout, Config.game.room_cell_size)
		var parent := Node3D.new()
		add_child_autofree(parent)
		Level.build(layout, parent)
		var plugs: int = 0
		for node: Node in RoomShape.all_children(parent):
			if node.name.begins_with("Plug"):
				plugs += 1
		var unconnected: int = links.filter(func(link: Dictionary) -> bool: return link["connected"] == false).size()
		assert_eq(plugs, unconnected, "seed %d: every doorway that leads nowhere is plugged" % run_seed)
		# Every room can be reached from the start through connected doorways.
		var reached: Dictionary[int, bool] = {0: true}
		var grew: bool = true
		while grew:
			grew = false
			for link: Dictionary in links:
				var joined: bool = link["connected"]
				var from_room: int = link["placement"]
				if not joined or not reached.has(from_room):
					continue
				var next: Vector2i = (link["cell"] as Vector2i) + (link["dir"] as Vector2i)
				for other: Dictionary in links:
					var to_room: int = other["placement"]
					if other["cell"] == next and other["dir"] == -(link["dir"] as Vector2i) \
							and not reached.has(to_room):
						reached[to_room] = true
						grew = true
		assert_eq(reached.size(), layout.placements.size(), "seed %d: every room is reachable" % run_seed)
	Level.clear()


func test_layout_round_trips_dict() -> void:
	var layout: FloorLayout = _layout(77)
	var copy: FloorLayout = FloorLayout.from_dict(layout.to_dict())
	assert_eq(copy.to_dict(), layout.to_dict())
	assert_eq(copy.placements.size(), layout.placements.size())
	assert_lt(var_to_bytes(layout.to_dict()).size(), 1500, "small enough to send to everyone")


func test_markers_sorted_same_order() -> void:
	var layout: FloorLayout = _layout(5)
	var orders: Array[PackedStringArray] = []
	for attempt: int in 2:
		var parent := Node3D.new()
		add_child_autofree(parent)
		Level.build(layout, parent)
		var names := PackedStringArray()
		for marker: RoomMarker in Level.get_markers(&"prop_spawn"):
			names.append("%s/%s@%s" % [marker.get_parent().name, marker.name, marker.global_position.round()])
		orders.append(names)
	assert_eq(orders[0], orders[1], "the same floor gives the same marker order")
	assert_gt(orders[0].size(), 0)
	assert_eq(Level.get_markers(&"player_spawn").size(), 8, "the lift room has 8 player spawns")
	for marker: RoomMarker in Level.get_markers(&"player_spawn"):
		assert_eq(Level.get_room_for_position(marker.global_position).room_kind, &"lift", "players start in the elevator")
	assert_gt(Level.get_markers(&"lift_part").size(), 0, "there are places for the lift part")
	assert_eq(Level.get_markers(&"lift").size(), 1)
	assert_not_null(Level.get_room_for_position(Level.get_markers(&"lift")[0].global_position))
	assert_eq(Level.get_room_for_position(Level.get_markers(&"lift")[0].global_position).room_kind, &"lift")
	Level.clear()


func test_every_room_follows_cart_rules() -> void:
	var cell_size: float = Config.game.room_cell_size
	var rooms: Array[ContentData] = ContentRegistry.get_all(&"room", true)
	assert_gt(rooms.size(), 0)
	for content: ContentData in rooms:
		var room := content as RoomData
		var root: Node = room.scene.instantiate()
		var shape := RoomShape.new()
		shape.size = Vector2i(room.size_cells.x, room.size_cells.z)
		for node: Node in RoomShape.all_children(root):
			var doorway := node as RoomDoorway
			if doorway == null:
				continue
			assert_gte(doorway.width, Config.game.cart_width + 0.4, "%s/%s is wide enough for a cart" % [room.id, doorway.name])
			assert_almost_eq(doorway.position.y, 0.0, 0.25, "%s/%s is at floor height (no steps)" % [room.id, doorway.name])
		var greybox := root as GreyboxRoom
		if greybox != null:
			assert_eq(Vector2i(room.size_cells.x, room.size_cells.z), greybox.size_cells, "%s: scene and data agree on size" % room.id)
		root.free()
		assert_eq(RoomShape.of(room, cell_size).bad_doorways, PackedStringArray(), "%s: every doorway is on an edge" % room.id)
		if room.room_kind == &"lift":
			var area: float = float(room.size_cells.x * room.size_cells.z) * cell_size * cell_size
			assert_gt(area, float(Config.game.max_players) * 2.0 + 6.0, "%s fits a cart and every player" % room.id)


func test_boss_floor_is_the_lift_and_the_arena() -> void:
	var layout: FloorLayout = LevelGenerator.generate_boss_floor(_department(), 6, 99)
	assert_true(layout.is_boss_floor)
	assert_eq(_kinds(layout), [&"lift", &"boss_arena"] as Array[StringName], "the elevator opens into the arena")


func test_new_room_file_used_without_code() -> void:
	var room := RoomData.new()
	room.id = &"room_test_new_hall"
	room.display_name = "Test hall"
	room.scene = (ContentRegistry.get_content(&"room_hall_grey") as RoomData).scene
	room.room_kind = &"normal"
	room.department_ids = [&"department_test_levels"] as Array[StringName]
	room.weight = 1000.0
	if not ContentRegistry.has_content(room.id):
		ContentRegistry.register_content(room)
	var used: bool = false
	for run_seed: int in 5:
		for placement: RoomPlacement in _layout(run_seed).placements:
			used = used or placement.room_id == room.id
	assert_true(used, "a new RoomData is used with no code changes")
	var other := _department()
	other.id = &"department_test_other"
	for placement: RoomPlacement in _layout(1, other).placements:
		assert_ne(placement.room_id, room.id, "but only by the departments it lists")
