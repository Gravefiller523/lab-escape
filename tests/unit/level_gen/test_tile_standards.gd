extends GutTest
## Tests for the floor generation tile standards (docs/systems/level_gen.md, "Tile standards"): every 3 m
## tile in content/rooms follows the grid, socket, size, marker and damage overlay rules, in every turn.

## How close (metres) a socket must be to where the standard puts it.
const CLOSE: float = 0.01


func _tiles() -> Array[RoomData]:
	var tiles: Array[RoomData] = []
	for content: ContentData in ContentRegistry.get_all(&"room", true):
		var room := content as RoomData
		if room != null and room.grid == RoomData.GRID_TILE:
			tiles.append(room)
	return tiles


func _unit() -> float:
	return Config.floor_gen.grid_unit


func _footprint(room: RoomData) -> Vector2i:
	return Vector2i(room.size_cells.x, room.size_cells.z)


## Builds a tile in a world of its own, so its walls never touch other tests' physics.
func _add_in_own_world(tile: Node3D) -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	viewport.add_child(tile)


func _sockets(root: Node) -> Array[RoomDoorway]:
	var found: Array[RoomDoorway] = []
	for node: Node in RoomShape.all_children(root):
		var socket := node as RoomDoorway
		if socket != null:
			found.append(socket)
	return found


func test_the_step_2_tiles_exist() -> void:
	var roles: Dictionary[StringName, int] = {}
	var sizes: Dictionary[StringName, int] = {}
	for room: RoomData in _tiles():
		roles[room.tile_role] = roles.get(room.tile_role, 0) + 1
		if room.tile_role == TileStandards.ROLE_ROOM:
			sizes[room.size_category] = sizes.get(room.size_category, 0) + 1
	assert_gte(_tiles().size(), 23, "about 20 blockout tiles")
	assert_eq(roles.get(TileStandards.ROLE_TEMPLATE, 0), 2, "the elevator and the welcome center")
	assert_eq(roles.get(TileStandards.ROLE_MAIN_HALL, 0), 6, "main hallway: straight, long, filler, corner, T, end")
	assert_eq(roles.get(TileStandards.ROLE_SECONDARY_HALL, 0), 7, "secondary hallway: straight, long, filler, corner, T, cross, end")
	for category: StringName in TileStandards.SIZE_CATEGORIES:
		assert_gt(sizes.get(category, 0), 0, "at least one %s room" % category)


func test_footprint_matches_data() -> void:
	for room: RoomData in _tiles():
		assert_true(TileStandards.ROLES.has(room.tile_role), "%s: known tile_role '%s'" % [room.id, room.tile_role])
		assert_eq(room.size_cells.y, 1, "%s: one storey" % room.id)
		var root: Node = room.scene.instantiate()
		var tile := root as BlockoutTile
		assert_not_null(tile, "%s: the scene root is a BlockoutTile" % room.id)
		if tile != null:
			assert_eq(tile.size_units, _footprint(room), "%s: scene and RoomData agree on the footprint" % room.id)
		root.free()


func test_sockets_follow_the_standard() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	var unit: float = _unit()
	for room: RoomData in _tiles():
		var length := Vector2(_footprint(room)) * unit
		var root: Node = room.scene.instantiate()
		var sockets: Array[RoomDoorway] = _sockets(root)
		assert_gt(sockets.size(), 0, "%s has sockets" % room.id)
		for socket: RoomDoorway in sockets:
			var label: String = "%s/%s" % [room.id, socket.name]
			assert_eq(socket.get_parent(), root, "%s is a direct child of the tile root" % label)
			assert_almost_eq(socket.width, tuning.doorway_width, CLOSE, "%s is the standard width" % label)
			assert_almost_eq(socket.height, tuning.doorway_height, CLOSE, "%s is the standard height" % label)
			assert_eq(socket.connection, RoomDoorway.CONNECTION_DOOR, "%s is a door" % label)
			assert_almost_eq(socket.position.y, 0.0, CLOSE, "%s is at floor height" % label)
			var p: Vector3 = socket.position
			var on_x_edge: bool = absf(p.x) < CLOSE or absf(p.x - length.x) < CLOSE
			var on_z_edge: bool = absf(p.z) < CLOSE or absf(p.z - length.y) < CLOSE
			assert_true(on_x_edge != on_z_edge, "%s is on exactly one footprint edge (%s)" % [label, p])
			var along: float = p.z if on_x_edge else p.x
			var edge_length: float = length.y if on_x_edge else length.x
			var units_along: float = along / unit - 0.5
			assert_almost_eq(units_along, roundf(units_along), CLOSE, "%s is centred on a grid unit's edge" % label)
			assert_between(along, 0.0, edge_length, "%s is inside its edge" % label)
		root.free()
		assert_eq(RoomShape.of(room, unit).bad_doorways, PackedStringArray(), "%s: RoomShape finds every socket on an edge" % room.id)


func test_rooms_have_a_socket_on_every_side() -> void:
	for room: RoomData in _tiles():
		if room.tile_role != TileStandards.ROLE_ROOM:
			continue
		var sides: Dictionary[Vector2i, bool] = {}
		for doorway: Dictionary in RoomShape.of(room, _unit()).doorways:
			sides[doorway["dir"] as Vector2i] = true
		assert_eq(sides.size(), 4, "%s has a socket on each of its 4 sides" % room.id)


func test_size_category_matches_footprint() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	for room: RoomData in _tiles():
		var size: Vector2i = _footprint(room)
		match room.tile_role:
			TileStandards.ROLE_ROOM:
				assert_true(TileStandards.SIZE_CATEGORIES.has(room.size_category), "%s has a size category" % room.id)
				assert_eq(tuning.size_category_for(size), room.size_category, "%s: %s matches the footprint table" % [room.id, size])
			TileStandards.ROLE_MAIN_HALL:
				assert_eq(size.x, 2, "%s: main hallway pieces are 2 units wide (across x; they run along z)" % room.id)
			TileStandards.ROLE_SECONDARY_HALL:
				assert_eq(size.x, 1, "%s: secondary hallway pieces are 1 unit wide (across x; they run along z)" % room.id)
		if room.tile_role != TileStandards.ROLE_ROOM:
			assert_eq(room.size_category, &"", "%s: only rooms have a size category" % room.id)
	var elevator := ContentRegistry.get_content(&"room_tile_elevator") as RoomData
	assert_eq(_footprint(elevator), tuning.elevator_size_units, "the elevator's footprint")
	var welcome := ContentRegistry.get_content(&"room_tile_welcome_center") as RoomData
	assert_eq(_footprint(welcome), tuning.welcome_center_size_units, "the welcome center's footprint")
	assert_eq(tuning.size_category_for(Vector2i(3, 2)), &"small", "either way round counts")
	assert_eq(tuning.size_category_for(Vector2i(7, 7)), &"", "sizes outside the table have no category")


func test_every_tile_has_damage_overlays() -> void:
	for room: RoomData in _tiles():
		assert_true(room.damage_levels.has("pristine") and room.damage_levels.has("light"),
			"%s lists at least pristine and light" % room.id)
		var root: Node = room.scene.instantiate()
		assert_not_null(root.get_node_or_null("Damage/Light"), "%s has Damage/Light" % room.id)
		for level: String in room.damage_levels:
			assert_true(TileStandards.DAMAGE_LEVELS.has(StringName(level)), "%s: known damage level '%s'" % [room.id, level])
			if level == "pristine":
				continue
			var overlay: Node3D = TileStandards.overlay_of(root, StringName(level))
			assert_not_null(overlay, "%s has an overlay for %s" % [room.id, level])
			if overlay != null:
				assert_false(overlay.visible, "%s: the %s overlay is hidden until the floor picks it" % [room.id, level])
		root.free()


func test_markers_use_known_kinds() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	for room: RoomData in _tiles():
		var length := Vector2(_footprint(room)) * _unit()
		var root: Node = room.scene.instantiate()
		var count: int = 0
		for node: Node in RoomShape.all_children(root):
			var marker := node as RoomMarker
			if marker == null:
				continue
			count += 1
			var label: String = "%s/%s" % [room.id, marker.name]
			assert_true(TileStandards.MARKER_KINDS.has(marker.kind), "%s: known marker kind '%s'" % [label, marker.kind])
			var p: Vector3 = (marker.get_parent() as Node3D).transform * marker.position if marker.get_parent() != root \
				else marker.position
			assert_between(p.x, 0.0, length.x, "%s is inside the footprint (x)" % label)
			assert_between(p.z, 0.0, length.y, "%s is inside the footprint (z)" % label)
			assert_between(p.y, 0.0, tuning.ceiling_height, "%s is between floor and ceiling" % label)
			if marker.kind == &"lift_part":
				assert_true(TileStandards.PART_SIZES.has(StringName(str(marker.params.get("max_size", "")))),
					"%s says the biggest part it fits" % label)
		assert_gt(count, 0, "%s has markers" % room.id)
		root.free()


func test_every_tile_turns_cleanly() -> void:
	var unit: float = _unit()
	for room: RoomData in _tiles():
		var shape: RoomShape = RoomShape.of(room, unit)
		var root: Node = room.scene.instantiate()
		var positions: Dictionary[String, Vector3] = {}
		for socket: RoomDoorway in _sockets(root):
			positions[String(socket.name)] = socket.position
		root.free()
		assert_eq(shape.doorways.size(), positions.size(), "%s: RoomShape reads every socket" % room.id)
		for steps: int in 4:
			var size: Vector2i = shape.rotated_size(steps)
			var placement := RoomPlacement.make(room.id, Vector3i.ZERO, steps)
			var xform: Transform3D = shape.placement_transform(placement, unit)
			var seen: Dictionary[String, bool] = {}
			for doorway: Dictionary in shape.rotated_doorways(steps):
				var cell: Vector2i = doorway["cell"]
				var dir: Vector2i = doorway["dir"]
				var label: String = "%s/%s turned %d" % [room.id, doorway["name"], steps]
				assert_true(cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y, "%s: its cell is inside" % label)
				var outside: Vector2i = cell + dir
				assert_true(outside.x < 0 or outside.y < 0 or outside.x >= size.x or outside.y >= size.y,
					"%s: it faces out of the footprint" % label)
				var key: String = "%s|%s" % [cell, dir]
				assert_false(seen.has(key), "%s: no two sockets on one grid unit edge" % label)
				seen[key] = true
				var expected := Vector3((float(cell.x) + 0.5 + float(dir.x) * 0.5) * unit, 0.0,
					(float(cell.y) + 0.5 + float(dir.y) * 0.5) * unit)
				var actual: Vector3 = xform * positions[String(doorway["name"])]
				assert_almost_eq(actual, expected, Vector3.ONE * CLOSE, "%s: the scene's socket is where the grid says" % label)


func test_elevator_gate_faces_the_welcome_center() -> void:
	var unit: float = _unit()
	var elevator := ContentRegistry.get_content(&"room_tile_elevator") as RoomData
	var welcome := ContentRegistry.get_content(&"room_tile_welcome_center") as RoomData
	var root: Node = elevator.scene.instantiate()
	var lifts: Array[RoomMarker] = []
	for node: Node in RoomShape.all_children(root):
		var marker := node as RoomMarker
		if marker != null and marker.kind == &"lift":
			lifts.append(marker)
	assert_eq(lifts.size(), 1, "the elevator has one lift marker")
	var gate := Vector3.ZERO
	if lifts.size() == 1:
		# The cargo lift's gate is on its -z side, and the floor is lined up so the marker is the lift.
		gate = -(lifts[0].transform.basis.z)
	root.free()
	var openings: int = 0
	for doorway: Dictionary in RoomShape.of(elevator, unit).doorways:
		var dir: Vector2i = doorway["dir"]
		if doorway["open_edge"]:
			openings += 1
			assert_almost_eq(Vector3(dir.x, 0, dir.y), gate, Vector3.ONE * CLOSE, "the lift's gate faces the open side")
	assert_gt(openings, 0, "the elevator opens to the welcome center")
	var facing_back: int = 0
	var connectors: Dictionary[Vector2i, int] = {}
	for doorway: Dictionary in RoomShape.of(welcome, unit).doorways:
		var dir: Vector2i = doorway["dir"]
		if not doorway["open_edge"]:
			continue
		if Vector3(dir.x, 0, dir.y).is_equal_approx(-gate):
			facing_back += 1
		else:
			connectors[dir] = connectors.get(dir, 0) + 1
	assert_eq(facing_back, openings, "the welcome center has an opening for each of the elevator's")
	assert_eq(connectors.size(), 2, "main hallway connectors on the left and the right")
	for dir: Vector2i in connectors:
		assert_eq(connectors[dir], 2, "each connector is 2 units wide (main hallway width)")
	var kinds: Array[StringName] = []
	var welcome_root: Node = welcome.scene.instantiate()
	for node: Node in RoomShape.all_children(welcome_root):
		var marker := node as RoomMarker
		if marker != null:
			kinds.append(marker.kind)
	welcome_root.free()
	for kind: StringName in [&"printer", &"cart", &"security_map", &"security_monitor", &"sign"]:
		assert_true(kinds.has(kind), "the welcome center has a %s marker" % kind)


func test_old_generator_never_uses_tiles() -> void:
	var department := DepartmentData.new()
	department.id = &"department_test_tiles"
	department.required_room_kinds = PackedStringArray(["lift"])
	for room: RoomData in LevelGenerator.room_pool(department, 1000):
		assert_eq(room.grid, RoomData.GRID_LEGACY, "%s is an old 12 m room" % room.id)
	for run_seed: int in 10:
		for placement: RoomPlacement in LevelGenerator.generate(department, 1, 1, run_seed, 1).placements:
			var room := ContentRegistry.get_content(placement.room_id) as RoomData
			assert_eq(room.grid, RoomData.GRID_LEGACY, "seed %d: %s is an old 12 m room" % [run_seed, room.id])


func test_tiles_are_solid_world_geometry() -> void:
	# The office (3 x 4 units): sockets in the middle of each side, so the north wall's west part is solid.
	var office := ContentRegistry.get_content(&"room_tile_office") as RoomData
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var tile := office.scene.instantiate() as Node3D
	viewport.add_child(tile)
	await wait_process_frames(2)
	await wait_physics_frames(3)
	var space: PhysicsDirectSpaceState3D = tile.get_world_3d().direct_space_state
	var mask: int = PhysicsLayers.bit(PhysicsLayers.WORLD)
	var through_wall := PhysicsRayQueryParameters3D.create(Vector3(1.5, 1.5, 1.5), Vector3(1.5, 1.5, -1.5), mask)
	assert_false(space.intersect_ray(through_wall).is_empty(), "a wall blocks (players, voices, navigation)")
	var through_door := PhysicsRayQueryParameters3D.create(Vector3(4.5, 1.5, 1.5), Vector3(4.5, 1.5, -1.5), mask)
	assert_true(space.intersect_ray(through_door).is_empty(), "the doorway is open")
	var above_door := PhysicsRayQueryParameters3D.create(Vector3(4.5, 3.2, 1.5), Vector3(4.5, 3.2, -1.5), mask)
	assert_false(space.intersect_ray(above_door).is_empty(), "the wall goes on above the 2.8 m doorway")
	var down := PhysicsRayQueryParameters3D.create(Vector3(4.5, 1.0, 6.0), Vector3(4.5, -1.0, 6.0), mask)
	var floor_hit: Dictionary = space.intersect_ray(down)
	assert_false(floor_hit.is_empty(), "there is a floor")
	if not floor_hit.is_empty():
		assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, CLOSE, "the floor is at height 0")
	var up := PhysicsRayQueryParameters3D.create(Vector3(4.5, 1.0, 6.0), Vector3(4.5, 5.0, 6.0), mask)
	var ceiling_hit: Dictionary = space.intersect_ray(up)
	assert_false(ceiling_hit.is_empty(), "there is a ceiling")
	if not ceiling_hit.is_empty():
		assert_almost_eq((ceiling_hit["position"] as Vector3).y, Config.floor_gen.ceiling_height, CLOSE, "at the standard height")
	var lights: int = 0
	for node: Node in RoomShape.all_children(tile):
		if node.is_in_group(TileStandards.LIGHT_GROUP):
			lights += 1
	assert_gt(lights, 0, "the tile has lights in the tile_light group")
	var placeholder: Node = tile.get_node_or_null("Damage/Heavy/%s" % BlockoutTile.PLACEHOLDER_NAME)
	assert_not_null(placeholder, "an empty overlay gets placeholder boxes")


func test_damage_levels_switch_overlays() -> void:
	var tile := (ContentRegistry.get_content(&"room_tile_storage_small") as RoomData).scene.instantiate() as Node3D
	_add_in_own_world(tile)
	TileStandards.show_damage(tile, &"heavy")
	assert_true(TileStandards.overlay_of(tile, &"heavy").visible)
	assert_false(TileStandards.overlay_of(tile, &"light").visible, "one level at a time")
	TileStandards.show_damage(tile, &"pristine")
	for level: StringName in [&"light", &"heavy", &"destroyed"]:
		assert_false(TileStandards.overlay_of(tile, level).visible, "pristine shows no overlay")


func test_palette_fills_material_slots() -> void:
	var tile := (ContentRegistry.get_content(&"room_tile_janitor_closet") as RoomData).scene.instantiate() as Node3D
	_add_in_own_world(tile)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	TileStandards.apply_palette(tile, {"wall": red})
	var walls: int = 0
	for node: Node in RoomShape.all_children(tile):
		if node.has_meta(TileStandards.MATERIAL_SLOT_META):
			var slot := StringName(str(node.get_meta(TileStandards.MATERIAL_SLOT_META)))
			assert_true(TileStandards.MATERIAL_SLOTS.has(slot), "%s uses a known slot" % node.name)
			if slot == &"wall" and node is CSGBox3D:
				walls += 1
				assert_eq((node as CSGBox3D).material, red, "%s got the palette's wall material" % node.name)
	assert_gt(walls, 0)


func test_tuning_patterns() -> void:
	var tuning := FloorGenTuning.new()
	assert_eq(tuning.bracket_index(1), 0)
	assert_eq(tuning.bracket_index(3), 0)
	assert_eq(tuning.bracket_index(4), 1)
	assert_eq(tuning.bracket_index(12), 2)
	assert_eq(tuning.by_bracket(tuning.parts_max_by_bracket, 9), 5, "floors 8+: up to 5 parts")
	assert_almost_eq(FloorGenTuning.grown(0.35, 0.06, 1.0, 1), 0.35, 0.001, "floor 1 is the base")
	assert_almost_eq(FloorGenTuning.grown(0.35, 0.06, 1.0, 30), 1.0, 0.001, "never above the cap")
	assert_not_null(Config.floor_gen, "Config.floor_gen is loaded from config/floor_gen_tuning.tres")


## NEW 2026-10-30 (Zachary): hallways are walled, with few side doorways, centred on the long sides.
func test_hallway_pieces_are_walled() -> void:
	# Doorways (not open edges) per piece; "main" and "hall" pieces follow the same rule.
	var expected: Dictionary[String, int] = {"straight": 2, "straight_long": 4, "filler": 0, "corner": 0, "t": 0,
		"cross": 0, "end": 1}
	var unit: float = _unit()
	var checked: int = 0
	for room: RoomData in _tiles():
		if room.tile_role != TileStandards.ROLE_MAIN_HALL and room.tile_role != TileStandards.ROLE_SECONDARY_HALL:
			continue
		var piece: String = String(room.id).trim_prefix("room_tile_main_").trim_prefix("room_tile_hall_")
		if not expected.has(piece):
			continue
		checked += 1
		var doors: Array[Dictionary] = []
		for doorway: Dictionary in RoomShape.of(room, unit).doorways:
			if not doorway["open_edge"]:
				doors.append(doorway)
		assert_eq(doors.size(), expected[piece], "%s has %d doorways" % [room.id, expected[piece]])
		if piece.begins_with("straight"):
			var length: int = room.size_cells.z
			assert_true(length == 3 or length == 5, "%s is 3 or 5 units long" % room.id)
			var per_side: Dictionary[Vector2i, Array] = {}
			for doorway: Dictionary in doors:
				var dir: Vector2i = doorway["dir"]
				assert_eq(dir.y, 0, "%s: doorways only on the long sides" % room.id)
				if not per_side.has(dir):
					per_side[dir] = []
				per_side[dir].append((doorway["cell"] as Vector2i).y)
			for dir: Vector2i in per_side:
				var units: Array = per_side[dir]
				units.sort()
				# Evenly spaced and centred: unit 1 of 3, units 1 and 3 of 5 (counting from 0).
				assert_eq(units, [1] if length == 3 else [1, 3], "%s: side doorways evenly spaced" % room.id)
	assert_eq(checked, 13, "every main and secondary hallway piece was checked")


## NEW 2026-10-30 (Zachary): damage lighting per level.
func test_damage_lighting() -> void:
	var tile := (ContentRegistry.get_content(&"room_tile_storage_large") as RoomData).scene.instantiate() as Node3D
	_add_in_own_world(tile)
	var flicker := TileLightFlicker.new()
	tile.add_child(flicker)
	var tuning := FloorGenTuning.new()
	var lights: Array[Light3D] = _lights_in(tile, TileStandards.LIGHT_GROUP)
	var emergency: Array[Light3D] = _lights_in(tile, TileStandards.EMERGENCY_LIGHT_GROUP)
	assert_gt(lights.size(), 1, "the tile has ceiling lights")
	assert_eq(emergency.size(), 2, "heavy and destroyed overlays each have a red emergency light")

	flicker.setup(tile, &"pristine", tuning)
	flicker.step(5.0)
	assert_eq(_lit_share(lights), 1.0, "pristine: every light on")

	# Heavy: lights spend most of their time dark, but they do flicker.
	tuning.heavy_dead_share = 0.0
	flicker.setup(tile, &"heavy", tuning)
	var heavy_on: float = _average_lit_share(flicker, lights, 30.0)
	assert_between(heavy_on, 0.01, 0.4, "heavy: mostly dark, with flickers (lit %.2f of the time)" % heavy_on)
	var light_on: float = 0.0
	flicker.setup(tile, &"light", tuning)
	light_on = _average_lit_share(flicker, lights, 30.0)
	assert_gt(light_on, heavy_on, "light damage is brighter than heavy (%.2f vs %.2f)" % [light_on, heavy_on])

	# Destroyed: the remaining lights are dark nearly all the time; dead ones never come on.
	tuning.destroyed_dead_share = 1.0
	flicker.setup(tile, &"destroyed", tuning)
	assert_eq(_average_lit_share(flicker, lights, 30.0), 0.0, "destroyed with every light dead: all dark")
	tuning.destroyed_dead_share = 0.0
	flicker.setup(tile, &"destroyed", tuning)
	var destroyed_on: float = _average_lit_share(flicker, lights, 60.0)
	assert_lt(destroyed_on, heavy_on, "destroyed flickers less than heavy (%.2f vs %.2f)" % [destroyed_on, heavy_on])
	var red_on: float = _average_lit_share(flicker, emergency, 60.0)
	assert_gt(red_on, 0.8, "the red emergency light is on most of the time (%.2f)" % red_on)


func test_damage_lighting_is_the_same_every_time() -> void:
	var tile := (ContentRegistry.get_content(&"room_tile_office") as RoomData).scene.instantiate() as Node3D
	_add_in_own_world(tile)
	var flicker := TileLightFlicker.new()
	tile.add_child(flicker)
	var lights: Array[Light3D] = _lights_in(tile, TileStandards.LIGHT_GROUP)
	var runs: Array[PackedStringArray] = []
	for attempt: int in 2:
		flicker.setup(tile, &"heavy", FloorGenTuning.new())
		var pattern := PackedStringArray()
		for frame: int in 300:
			flicker.step(0.05)
			pattern.append(str(_lit_share(lights)))
		runs.append(pattern)
	assert_eq(runs[0], runs[1], "the same tile and level flicker the same way (seeded by each light's path)")


func _lights_in(root: Node, group: StringName) -> Array[Light3D]:
	var found: Array[Light3D] = []
	for node: Node in RoomShape.all_children(root):
		if node is Light3D and node.is_in_group(group):
			found.append(node as Light3D)
	return found


func _lit_share(lights: Array[Light3D]) -> float:
	var lit: int = 0
	for light: Light3D in lights:
		if light.visible:
			lit += 1
	return float(lit) / float(maxi(lights.size(), 1))


## Steps the flicker for this many seconds and returns the average share of lights that were on.
func _average_lit_share(flicker: TileLightFlicker, lights: Array[Light3D], seconds: float) -> float:
	var total: float = 0.0
	var frames: int = int(seconds / 0.05)
	for frame: int in frames:
		flicker.step(0.05)
		total += _lit_share(lights)
	return total / float(frames)


## NEW 2026-10-31 (Zachary: "way more random"): lights in one room don't share a rhythm, flashes vary in
## brightness, and the gaps between flickers vary a lot.
func test_flicker_is_irregular() -> void:
	var tile := (ContentRegistry.get_content(&"room_tile_cafeteria") as RoomData).scene.instantiate() as Node3D
	_add_in_own_world(tile)
	var flicker := TileLightFlicker.new()
	tile.add_child(flicker)
	var tuning := FloorGenTuning.new()
	tuning.heavy_dead_share = 0.0
	flicker.setup(tile, &"heavy", tuning)
	var lights: Array[Light3D] = _lights_in(tile, TileStandards.LIGHT_GROUP)
	var patterns: Dictionary[String, bool] = {}
	var brightness: Dictionary[float, bool] = {}
	var dark_runs: Array[int] = []
	for light: Light3D in lights:
		var pattern: String = ""
		var run: int = 0
		for frame: int in 1200:
			flicker.step(0.05)
			pattern += "1" if light.visible else "0"
			if light.visible:
				brightness[snappedf(light.light_energy, 0.01)] = true
				if run > 0:
					dark_runs.append(run)
				run = 0
			else:
				run += 1
		patterns[pattern] = true
	assert_eq(patterns.size(), lights.size(), "every light has its own pattern")
	assert_gt(brightness.size(), 5, "flashes come in many brightnesses")
	dark_runs.sort()
	assert_gt(dark_runs.size(), 10, "lights do come on now and then")
	if dark_runs.size() > 10:
		assert_gt(dark_runs[-1], dark_runs[0] * 10, "some dark spells are much longer than others")
