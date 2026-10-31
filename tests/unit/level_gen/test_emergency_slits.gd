extends GutTest
## NEW 2026-10-31 (Zachary): the red emergency slits low on the tiles' walls (EmergencySlits): where they go
## in rooms and hallways, that they never sit in a doorway, and how damage switches them on.


func _tiles() -> Array[RoomData]:
	var tiles: Array[RoomData] = []
	for content: ContentData in ContentRegistry.get_all(&"room", true):
		var room := content as RoomData
		if room != null and room.grid == RoomData.GRID_TILE:
			tiles.append(room)
	return tiles


func _tuning() -> FloorGenTuning:
	return Config.floor_gen


## Builds a node in a world of its own, so its walls never touch other tests' physics.
func _add_in_own_world(node: Node3D) -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	viewport.add_child(node)


func _instance(room: RoomData) -> BlockoutTile:
	var tile := room.scene.instantiate() as BlockoutTile
	_add_in_own_world(tile)
	return tile


## A bare tile of this size with no sockets, furniture or markers.
func _bare_tile(size: Vector2i) -> BlockoutTile:
	var tile := BlockoutTile.new()
	tile.size_units = size
	tile.auto_lights = false
	_add_in_own_world(tile)
	return tile


func _emergency_lights(root: Node) -> Array[Light3D]:
	var found: Array[Light3D] = []
	for node: Node in RoomShape.all_children(root):
		if node is Light3D and node.is_in_group(TileStandards.EMERGENCY_LIGHT_GROUP):
			found.append(node as Light3D)
	return found


func _corners(slits: Array[Dictionary]) -> int:
	var count: int = 0
	for slit: Dictionary in slits:
		if slit.has("corner"):
			count += 1
	return count


## A glowing piece's footprint on the floor plan (x, z), in tile space.
func _footprint(tile: BlockoutTile, mesh: MeshInstance3D) -> Rect2:
	var xform: Transform3D = tile.global_transform.affine_inverse() * mesh.global_transform
	var box: AABB = xform * mesh.get_aabb()
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## Where a socket's doorway (frame included) or open edge is on the floor plan, 0.4 m deep across the wall.
func _opening(tile: BlockoutTile, socket: RoomDoorway) -> Rect2:
	var unit: float = _tuning().grid_unit
	var place: Vector2i = tile.socket_place(socket)
	var half: float = unit / 2.0 if socket.open_edge else socket.width / 2.0 + BlockoutTile.FRAME
	var p := Vector2(socket.position.x, socket.position.z)
	if place.x <= 1:
		return Rect2(p.x - half, p.y - 0.2, half * 2.0, 0.4)
	return Rect2(p.x - 0.2, p.y - half, 0.4, half * 2.0)


func test_slits_never_sit_in_a_doorway_or_an_open_edge() -> void:
	var checked: int = 0
	for room: RoomData in _tiles():
		var tile: BlockoutTile = _instance(room)
		var holder: Node = tile.get_node_or_null(EmergencySlits.NODE_NAME)
		assert_not_null(holder, "%s has its slits node" % room.id)
		if holder == null:
			continue
		for node: Node in RoomShape.all_children(holder):
			var mesh := node as MeshInstance3D
			if mesh == null or not String(mesh.name).begins_with("Glow"):
				continue
			checked += 1
			var footprint: Rect2 = _footprint(tile, mesh)
			assert_lt(mesh.get_aabb().size.y, 0.1, "%s: a slit is a thin slot" % room.id)
			for socket: RoomDoorway in tile.get_sockets():
				assert_false(footprint.intersects(_opening(tile, socket)),
					"%s: %s is clear of %s" % [room.id, mesh.get_parent().get_parent().name, socket.name])
	assert_gt(checked, 40, "slits were checked")


func test_no_ceiling_emergency_light_is_left() -> void:
	for room: RoomData in _tiles():
		var tile: BlockoutTile = _instance(room)
		for light: Light3D in _emergency_lights(tile):
			assert_true(tile.get_node(EmergencySlits.NODE_NAME).is_ancestor_of(light), "%s: %s belongs to a slit" % [room.id, light.name])
			assert_lt(light.position.y, 1.0, "%s: %s is low on a wall" % [room.id, light.name])
			assert_false(light.shadow_enabled, "%s: slit lights cast no shadows" % room.id)
			assert_false(light.visible, "%s: slits start dark (TileLightFlicker turns them on)" % room.id)
		assert_lte(_emergency_lights(tile).size(), _tuning().emergency_max_lights_per_tile, "%s: not too many" % room.id)


func test_small_rooms_light_two_corners_and_big_rooms_four() -> void:
	var tuning: FloorGenTuning = _tuning()
	var small: Array[Dictionary] = EmergencySlits.plan(_bare_tile(Vector2i(3, 3)), tuning)
	assert_eq(_corners(small), 2, "a 9 x 9 m room lights 2 corners")
	assert_eq(small.size(), 2, "and nothing else")
	var points: Array[Vector2] = []
	var tile: BlockoutTile = _bare_tile(Vector2i(3, 3))
	for slit: Dictionary in small:
		points.append(EmergencySlits.slit_point(tile, tuning, slit))
	assert_gt(absf(points[0].x - points[1].x), 8.0, "the two corners are opposite each other")
	assert_gt(absf(points[0].y - points[1].y), 8.0, "the two corners are opposite each other")
	var big: Array[Dictionary] = EmergencySlits.plan(_bare_tile(Vector2i(4, 4)), tuning)
	assert_eq(_corners(big), 4, "a 12 x 12 m room lights all 4 corners")
	assert_eq(big.size(), 4, "12 m walls aren't long enough for straight slits")
	var long_room := _bare_tile(Vector2i(5, 6))
	var long_slits: Array[Dictionary] = EmergencySlits.plan(long_room, tuning)
	assert_eq(_corners(long_slits), 4, "a 15 x 18 m room lights all 4 corners")
	assert_eq(long_slits.size(), 8, "and one straight slit on each long wall (round(L / 9) - 1)")
	for slit: Dictionary in long_slits:
		if slit.has("corner"):
			continue
		for other: Dictionary in long_slits:
			if other != slit:
				assert_gte(EmergencySlits.slit_point(long_room, tuning, slit).distance_to(
					EmergencySlits.slit_point(long_room, tuning, other)), tuning.emergency_slit_min_gap,
					"straight slits keep their distance")


func test_a_corner_next_to_a_door_or_furniture_is_skipped() -> void:
	var tuning: FloorGenTuning = _tuning()
	var tile := BlockoutTile.new()
	tile.size_units = Vector2i(4, 4)
	var door := RoomDoorway.new()
	door.name = "SocketN0"
	door.width = 2.4
	door.height = 2.8
	door.position = Vector3(1.5, 0, 0)
	tile.add_child(door)
	var shelf := CSGBox3D.new()
	shelf.name = "Shelf"
	shelf.size = Vector3(1, 2, 0.5)
	shelf.position = Vector3(11.2, 1, 11.5)
	tile.add_child(shelf)
	_add_in_own_world(tile)
	var slits: Array[Dictionary] = EmergencySlits.plan(tile, tuning)
	var corners: Array[Vector2i] = []
	for slit: Dictionary in slits:
		if slit.has("corner"):
			corners.append(slit["corner"])
	assert_false(corners.has(Vector2i(0, 2)), "north-west corner: a door is right next to it")
	assert_true(corners.has(Vector2i(0, 3)), "north-east corner is free")
	assert_false(corners.has(Vector2i(1, 3)), "south-east corner: a shelf stands in it")
	assert_true(corners.has(Vector2i(1, 2)), "south-west corner is free")
	tile.seal_socket("SocketN0")
	assert_true(_corner_list(EmergencySlits.plan(tile, tuning)).has(Vector2i(0, 2)),
		"once its doorway is sealed (plain wall), the north-west corner is lit")


func _corner_list(slits: Array[Dictionary]) -> Array[Vector2i]:
	var corners: Array[Vector2i] = []
	for slit: Dictionary in slits:
		if slit.has("corner"):
			corners.append(slit["corner"])
	return corners


func test_hallway_pieces() -> void:
	var tuning: FloorGenTuning = _tuning()
	var expected: Dictionary[StringName, int] = {&"room_tile_main_straight": 4, &"room_tile_main_straight_long": 6,
		&"room_tile_main_filler": 2, &"room_tile_main_filler_dark": 0, &"room_tile_main_corner": 1,
		&"room_tile_main_t": 0, &"room_tile_main_end": 2, &"room_tile_hall_straight": 4,
		&"room_tile_hall_straight_long": 6, &"room_tile_hall_filler": 2, &"room_tile_hall_filler_dark": 0,
		&"room_tile_hall_corner": 1, &"room_tile_hall_t": 0, &"room_tile_hall_cross": 0, &"room_tile_hall_end": 2}
	for id: StringName in expected:
		var tile: BlockoutTile = _instance(ContentRegistry.get_content(id) as RoomData)
		var slits: Array[Dictionary] = EmergencySlits.plan(tile, tuning)
		assert_eq(slits.size(), expected[id], "%s has %d slits" % [id, expected[id]])
		if String(id).contains("straight") or (String(id).ends_with("filler")):
			for slit: Dictionary in slits:
				var unit_index: int = floori(float(slit["at"]) / tuning.grid_unit)
				assert_eq(unit_index % 2, 0, "%s: lit on units 0, 2, 4" % id)
		if String(id).ends_with("corner"):
			assert_eq(slits[0].get("arms"), Vector2i(1, 1), "%s: a full L in the outside corner" % id)


func test_lit_units_alternate_along_main_hallways() -> void:
	var tuning: FloorGenTuning = _tuning()
	var department := ContentRegistry.get_content(&"department_robotics") as DepartmentData
	var lit_by_room: Dictionary[StringName, Array] = {}
	var runs: int = 0
	for floor_seed: int in 12:
		var layout: FloorLayout = FloorGenerator.generate_from_seed(department, 1 + floor_seed % 9, 900 + floor_seed, tuning)
		for hall: PackedInt32Array in layout.main_halls:
			var units: Array[bool] = []
			for index: int in hall:
				var room := ContentRegistry.get_content(layout.placements[index].room_id) as RoomData
				if FloorGenerator.piece_kind(room) != FloorGenerator.PIECE_STRAIGHT:
					runs += _check_run(units, layout.floor_seed)
					units.clear()
					continue
				if not lit_by_room.has(room.id):
					lit_by_room[room.id] = _lit_units(room, tuning)
				for lit: Variant in lit_by_room[room.id]:
					units.append(lit as bool)
			runs += _check_run(units, layout.floor_seed)
	assert_gt(runs, 10, "hallway runs were checked")


## Every other unit lit along a run of straight pieces (straight pieces are lit the same either way round).
func _check_run(units: Array[bool], floor_seed: int) -> int:
	if units.size() < 2:
		return 0
	for index: int in range(1, units.size()):
		assert_ne(units[index], units[index - 1], "seed %d: lit and dark units take turns (%s)" % [floor_seed, str(units)])
	return 1


func _lit_units(room: RoomData, tuning: FloorGenTuning) -> Array[bool]:
	var tile: BlockoutTile = _instance(room)
	var units: Array[bool] = []
	units.resize(room.size_cells.z)
	units.fill(false)
	for slit: Dictionary in EmergencySlits.plan(tile, tuning):
		units[floori(float(slit["at"]) / tuning.grid_unit)] = true
	return units


func test_destroyed_slits_are_dead_or_flickering_the_same_every_time() -> void:
	var department := ContentRegistry.get_content(&"department_robotics") as DepartmentData
	FloorGenerator.debug_damage = &"destroyed"
	var layout: FloorLayout = FloorGenerator.generate_from_seed(department, 6, 4321, _tuning())
	FloorGenerator.debug_damage = &""
	var patterns: Array[PackedStringArray] = []
	var parent := Node3D.new()
	_add_in_own_world(parent)
	for attempt: int in 2:
		Level.build(layout, parent)
		var pattern := PackedStringArray()
		for light: Light3D in _emergency_lights(parent):
			pattern.append("%s=%s" % [parent.get_path_to(light), light.visible])
		patterns.append(pattern)
		Level.clear()
	assert_gt(patterns[0].size(), 20, "a destroyed floor has many slits")
	assert_eq(patterns[0], patterns[1], "the same slits are dead each time (seeded, so every PC matches)")
	var dead: int = 0
	for entry: String in patterns[0]:
		if entry.ends_with("=false"):
			dead += 1
	var share: float = float(dead) / float(patterns[0].size())
	assert_between(share, 0.15, 0.55, "about a third are dead (%.2f)" % share)


func test_the_security_room_gets_its_own_slits() -> void:
	for id: StringName in [&"room_tile_welcome_center", &"room_tile_robotics_welcome_center"]:
		var tile: BlockoutTile = _instance(ContentRegistry.get_content(id) as RoomData)
		assert_false(tile.emergency_keep_out.is_empty(), "%s keeps the room rules out of its security room" % id)
		var room: Rect2 = tile.emergency_keep_out[0]
		var inside: Rect2 = room.grow(-0.1)
		var in_room: int = 0
		for node: Node in RoomShape.all_children(tile.get_node(EmergencySlits.NODE_NAME)):
			var mesh := node as MeshInstance3D
			if mesh == null or not String(mesh.name).begins_with("Glow"):
				continue
			var footprint: Rect2 = _footprint(tile, mesh)
			if not room.intersects(footprint):
				continue
			in_room += 1
			assert_true(inside.encloses(footprint), "%s: a security room slit lies inside the room (%s)" % [id, footprint])
		assert_eq(in_room, 4, "%s: two L slits (4 arms) in the security room's back corners" % id)
