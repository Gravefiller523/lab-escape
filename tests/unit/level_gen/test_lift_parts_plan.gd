extends GutTest
## NEW 2026-11-10 (floor generation step 4d): the plan's broken lift parts (FloorGenerator step 8): how many,
## where, their carry paths, the keycard limit, the incident rule, and the cargo lift reading the plan.

const LIFT_SCENE: PackedScene = preload("res://systems/cargo_lift/cargo_lift.tscn")
const WAIT: float = 5.0
const SEEDS_PER_FLOOR: int = 3


func _tuning() -> FloorGenTuning:
	return Config.floor_gen


func _robotics() -> DepartmentData:
	return ContentRegistry.get_content(&"department_robotics") as DepartmentData


func _room(layout: FloorLayout, index: int) -> RoomData:
	return ContentRegistry.get_content(layout.placements[index].room_id) as RoomData


func _logged(layout: FloorLayout, text: String) -> bool:
	for line: String in layout.log_lines:
		if line.contains(text):
			return true
	return false


## Which tiles are joined (through door connections): placement -> joined placements.
func _joins(layout: FloorLayout) -> Dictionary[int, Array]:
	var links: Array[Dictionary] = LevelGenerator.doorway_links(layout, _tuning().grid_unit)
	var joins: Dictionary[int, Array] = {}
	for link: Dictionary in links:
		if not link["connected"] or link.get("connection", RoomDoorway.CONNECTION_DOOR) != RoomDoorway.CONNECTION_DOOR:
			continue
		var next: Vector2i = (link["cell"] as Vector2i) + (link["dir"] as Vector2i)
		for other: Dictionary in links:
			if other["cell"] == next and other["dir"] == -(link["dir"] as Vector2i):
				var from: int = link["placement"]
				if not joins.has(from):
					joins[from] = []
				joins[from].append(int(other["placement"]))
	return joins


## Tiles reachable from the elevator, not through collapsed tiles or the given doors.
func _reach(layout: FloorLayout, joins: Dictionary[int, Array], shut: Array[int]) -> Dictionary[int, bool]:
	var blocked: Dictionary[String, bool] = {}
	for door: int in shut:
		var a: int = layout.doors[door][0]
		var b: int = layout.doors[door][2]
		blocked["%d,%d" % [mini(a, b), maxi(a, b)]] = true
	var reached: Dictionary[int, bool] = {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var at: int = queue.pop_back()
		for next: int in joins.get(at, []):
			if reached.has(next) or layout.collapsed.has(next) or blocked.has("%d,%d" % [mini(at, next), maxi(at, next)]):
				continue
			reached[next] = true
			queue.append(next)
	return reached


## Walking distance (through tile centres) from one tile to every tile.
func _distances(layout: FloorLayout, joins: Dictionary[int, Array], from: int) -> Dictionary[int, float]:
	var unit: float = _tuning().grid_unit
	var centres: Array[Vector2] = []
	for index: int in layout.placements.size():
		var placement: RoomPlacement = layout.placements[index]
		var size: Vector3i = _room(layout, index).size_cells
		var turned := Vector2(size.x, size.z) if placement.rotation_steps % 2 == 0 else Vector2(size.z, size.x)
		centres.append((Vector2(placement.cell.x, placement.cell.z) + turned / 2.0) * unit)
	var best: Dictionary[int, float] = {from: 0.0}
	var open: Array[int] = [from]
	while not open.is_empty():
		var at: int = open.pop_front()
		for next: int in joins.get(at, []):
			if layout.collapsed.has(next):
				continue
			var length: float = best[at] + centres[at].distance_to(centres[next])
			if not best.has(next) or length < best[next] - 0.001:
				best[next] = length
				open.append(next)
	return best


func test_every_part_kind_has_a_size_and_category() -> void:
	var slots: Dictionary[StringName, bool] = {}
	for content: ContentData in ContentRegistry.get_all(&"prop"):
		var prop := content as PropData
		if prop == null or prop.lift_slot == &"":
			continue
		slots[prop.lift_slot] = true
		assert_true(TileStandards.PART_SIZES.has(prop.part_size), "%s has a part size" % prop.id)
		assert_ne(prop.part_category, &"", "%s has a part category" % prop.id)
	for slot: StringName in [&"motor", &"control_board", &"brake_assembly"]:
		assert_true(slots.has(slot), "the new %s part exists (Q3)" % slot)
	assert_gte(slots.size(), 12, "the 9 old parts and the 3 new ones")


func test_parts_follow_the_rules_on_every_floor() -> void:
	var tuning: FloorGenTuning = _tuning()
	var floors: int = 0
	for floor_number: int in range(1, 13):
		for attempt: int in SEEDS_PER_FLOOR:
			var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, 7000 + floor_number * 31 + attempt, tuning)
			floors += 1
			_check_floor(layout, tuning)
	assert_eq(floors, 12 * SEEDS_PER_FLOOR)


func _check_floor(layout: FloorLayout, tuning: FloorGenTuning) -> void:
	var label: String = "floor %d seed %d" % [layout.floor_number, layout.floor_seed]
	var lo: int = tuning.by_bracket(tuning.parts_min_by_bracket, layout.floor_number)
	var hi: int = tuning.by_bracket(tuning.parts_max_by_bracket, layout.floor_number)
	var count: int = layout.lift_parts.size()
	assert_lte(count, hi, "%s: at most %d parts" % [label, hi])
	assert_true(count >= lo or _logged(layout, "parts placed"), "%s: at least %d parts (%d), or it says why" % [label, lo, count])
	assert_gt(count, 0, "%s: some part is broken" % label)
	assert_eq(layout.lift_part_paths.size(), count, "%s: a carry path per part" % label)
	assert_eq(layout.lift_part_backups.size(), count, "%s: backup spots per part" % label)
	var joins: Dictionary[int, Array] = _joins(layout)
	var from_start: Dictionary[int, float] = _distances(layout, joins, 0)
	var farthest: float = 0.0
	for index: int in from_start:
		if _room(layout, index).tile_role == TileStandards.ROLE_ROOM:
			farthest = maxf(farthest, from_start[index])
	var keycard_doors: Array[int] = []
	for door: int in layout.doors.size():
		if layout.doors[door][3] == FloorGenerator.DOOR_KEYCARD:
			keycard_doors.append(door)
	var outside_keycards: Dictionary[int, bool] = _reach(layout, joins, keycard_doors)
	var hazard_rooms: Dictionary[int, bool] = {}
	for key: String in layout.active_markers.get(&"hazard", PackedStringArray()):
		hazard_rooms[key.get_slice("/", 0).to_int()] = true
	var from_origin: Dictionary[int, float] = {}
	if layout.origin >= 0:
		from_origin = _distances(layout, joins, layout.origin)
	var rooms: Dictionary[int, bool] = {}
	var behind_keycards: int = 0
	var near: bool = false
	var calm: bool = false
	for part_index: int in count:
		var part: Array = layout.lift_parts[part_index]
		var data := ContentRegistry.get_content(StringName(str(part[0]))) as PropData
		var room_index: int = part[2]
		var room: RoomData = _room(layout, room_index)
		assert_not_null(data, "%s: part %s exists" % [label, part[0]])
		assert_eq(room.tile_role, TileStandards.ROLE_ROOM, "%s: %s is in a room (not a hallway or the start)" % [label, part[0]])
		assert_eq(str(part[1]).get_slice("/", 0).to_int(), room_index, "%s: its marker is in its room" % label)
		assert_false(rooms.has(room_index), "%s: one part per room" % label)
		rooms[room_index] = true
		var marker: Dictionary = {}
		for candidate: Dictionary in RoomShape.of(room, _tuning().grid_unit).markers:
			if FloorLayout.marker_key(room_index, candidate["path"]) == str(part[1]):
				marker = candidate
		assert_eq(marker.get("kind", &""), &"lift_part", "%s: %s is on a lift_part marker" % [label, part[0]])
		if data != null and not marker.is_empty():
			var fits: StringName = StringName(str((marker["params"] as Dictionary).get("max_size", "medium")))
			assert_lte(TileStandards.PART_SIZES.find(data.part_size), TileStandards.PART_SIZES.find(fits),
				"%s: the %s fits its marker" % [label, part[0]])
		# The carry path: from its room, tile to joined tile, back to the elevator, never through a collapse.
		var path: PackedInt32Array = layout.lift_part_paths[part_index]
		assert_eq(path[0], room_index, "%s: the path starts in the part's room" % label)
		assert_eq(path[path.size() - 1], 0, "%s: the path ends at the elevator" % label)
		for step: int in range(1, path.size()):
			assert_true((joins.get(path[step - 1], []) as Array).has(path[step]), "%s: the path goes through doorways" % label)
			assert_false(layout.collapsed.has(path[step]), "%s: the path avoids collapsed hallways" % label)
		assert_true(from_start.get(room_index, 0.0) >= farthest * tuning.part_min_distance_share - 0.01
			or _logged(layout, "closer to the elevator"), "%s: far enough, or it says why" % label)
		if not outside_keycards.has(room_index):
			behind_keycards += 1
		var level: int = layout.damage[room_index] if room_index < layout.damage.size() else 0
		near = near or level >= 2 or from_origin.get(room_index, INF) <= tuning.part_near_incident_metres
		calm = calm or (not room.is_combat_room and not hazard_rooms.has(room_index))
	assert_lte(behind_keycards, tuning.by_bracket(tuning.parts_behind_keycards_max_by_bracket, layout.floor_number),
		"%s: not too many parts behind keycard doors (V9)" % label)
	if layout.floor_number >= tuning.part_near_incident_from_floor and layout.origin >= 0:
		assert_true(near or _logged(layout, "near the incident"), "%s: a part near the incident, or it says why (Q14)" % label)
	assert_true(calm, "%s: not every part in a combat or hazard room (Q15)" % label)


func test_parts_are_the_same_on_every_pc() -> void:
	for floor_number: int in [1, 5, 12]:
		var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, 4040 + floor_number, _tuning())
		var again: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), floor_number, 4040 + floor_number, _tuning())
		assert_eq(again.lift_parts, layout.lift_parts, "floor %d: the same seed places the same parts" % floor_number)
		var client: FloorLayout = FloorLayout.from_dict(layout.to_dict())
		assert_eq(client.lift_parts, layout.lift_parts, "floor %d: other PCs get the parts" % floor_number)
		assert_eq(client.lift_part_paths, layout.lift_part_paths, "floor %d: and the carry paths" % floor_number)
		assert_eq(client.lift_part_backups, layout.lift_part_backups, "floor %d: and the backup spots" % floor_number)
		assert_eq(client.charger_marker, layout.charger_marker, "floor %d: and the charger spot" % floor_number)
		assert_eq(client.to_dict(), layout.to_dict(), "floor %d: the whole plan round-trips" % floor_number)


# --- The cargo lift reads the plan -----------------------------------------------------------------------

func test_the_lift_breaks_the_planned_parts_and_spawns_them_at_their_markers() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var props := PropSpawner.new()
	props.name = "Props"
	root.add_child(props)
	var lift := LIFT_SCENE.instantiate() as CargoLift
	root.add_child(lift)
	var layout: FloorLayout = FloorGenerator.generate_from_seed(_robotics(), 9, 5151, _tuning())
	assert_gte(layout.lift_parts.size(), 2, "floor 9 has several parts")
	# As in the game: a new floor is loading (systems drop what belonged to the last one, e.g. enemy navigation).
	EventBus.floor_loading.emit(9, layout.department_id)
	Level.build(layout, root)
	await wait_physics_frames(3)
	lift.arrive(1, false)
	var planned: Array[StringName] = []
	for part: Array in layout.lift_parts:
		planned.append((ContentRegistry.get_content(StringName(str(part[0]))) as PropData).lift_slot)
	var broken: Array[StringName] = lift.get_broken_slots()
	broken.sort()
	planned.sort()
	assert_eq(broken, planned, "the plan's parts are the broken slots (not the lift's own roll)")
	EventBus.floor_ready.emit(9, layout.department_id)
	await wait_physics_frames(3)
	for part: Array in layout.lift_parts:
		var spawned: Array[NetProp] = props.get_props(StringName(str(part[0])))
		assert_eq(spawned.size(), 1, "the %s was spawned" % part[0])
		var marker: RoomMarker = Level.get_marker_by_key(str(part[1]))
		if not spawned.is_empty() and marker != null:
			assert_lt(spawned[0].global_position.distance_to(marker.global_position), 1.5, "at its planned marker")
	# A lost part comes back at its first backup spot.
	var first: Array = layout.lift_parts[0]
	var backups: PackedStringArray = layout.lift_part_backups[0]
	props.despawn(props.get_props(StringName(str(first[0])))[0])
	await wait_until(func() -> bool: return props.get_props(StringName(str(first[0]))).size() == 1, WAIT)
	var back: Array[NetProp] = props.get_props(StringName(str(first[0])))
	assert_eq(back.size(), 1, "the lost part came back")
	if not back.is_empty() and not backups.is_empty():
		var spot: RoomMarker = Level.get_marker_by_key(backups[0])
		assert_lt(back[0].global_position.distance_to(spot.global_position), 1.5, "at its first backup spot")
	# floor_ready started the enemies' navigation bake on a background thread: let it finish before the floor goes.
	await wait_until(func() -> bool: return not Enemies.is_baking_navigation(), WAIT)
	Level.clear()
