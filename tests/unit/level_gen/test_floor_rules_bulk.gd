extends GutTest
## NEW 2026-11-10 (floor generation step 4f, plan section 13): the bulk test. `seeds` floors per department (floors
## 1 to 12 in turn (CHANGED 2026-11-13: runs are 12 floors; was 1 to 15); 30 here, 500 in the slow group: tests_slow/level_gen/test_floor_rules_bulk_500.gd), every one checked against the plan's 8 rules from the outside (not with the generator's own
## checks): carry paths, locks openable in some order, required rooms, no overlaps, every join face to face, the
## start, parts and keys reachable, the part rules, and a part in a calm room. Also how often the fallback is needed.

## Floors per department (the slow group sets 500 in before_all).
var seeds: int = 30
const FLOORS: int = 12
const DEPARTMENTS: Array[StringName] = [&"department_robotics", &"department_botany", &"department_zoology"]


func _unit() -> float:
	return Config.floor_gen.grid_unit


func _room(layout: FloorLayout, index: int) -> RoomData:
	return ContentRegistry.get_content(layout.placements[index].room_id) as RoomData


func test_every_floor_keeps_the_rules() -> void:
	var tuning: FloorGenTuning = Config.floor_gen
	var started: int = Time.get_ticks_msec()
	var fallbacks: int = 0
	var extra_attempts: int = 0
	var floors: int = 0
	for department_id: StringName in DEPARTMENTS:
		var department := ContentRegistry.get_content(department_id) as DepartmentData
		assert_not_null(department, "%s exists" % department_id)
		for index: int in seeds:
			var floor_number: int = 1 + index % FLOORS
			var layout: FloorLayout = FloorGenerator.generate_from_seed(department, floor_number, 50000 + index * 7919, tuning)
			floors += 1
			extra_attempts += layout.attempt
			if layout.is_fallback:
				fallbacks += 1
			var problem: String = _broken_rule(layout, department, tuning)
			if not problem.is_empty():
				fail_test("%s floor %d seed %d: %s" % [department_id, floor_number, layout.floor_seed, problem])
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	gut.p("bulk: %d floors in %.1f s, %d extra attempts, %d fallbacks" % [floors, seconds, extra_attempts, fallbacks])
	assert_eq(fallbacks, 0, "no floor needed the fallback")
	assert_lt(float(extra_attempts) / float(floors), 0.5, "retries stay rare (%d in %d floors)" % [extra_attempts, floors])


## The first of the 8 rules a floor breaks, or "".
func _broken_rule(layout: FloorLayout, department: DepartmentData, tuning: FloorGenTuning) -> String:
	var joins: Dictionary[int, Array] = {}
	var links: Array[Dictionary] = LevelGenerator.doorway_links(layout, _unit())
	# 5. Every join is face to face, between two tiles, of the same kind.
	for link: Dictionary in links:
		if not link["connected"]:
			continue
		var next: Vector2i = (link["cell"] as Vector2i) + (link["dir"] as Vector2i)
		var partner: Dictionary = {}
		for other: Dictionary in links:
			if other["cell"] == next and other["dir"] == -(link["dir"] as Vector2i):
				partner = other
		if partner.is_empty():
			return "5: a joined doorway has nothing facing it"
		if partner["placement"] == link["placement"]:
			return "5: a tile joins itself"
		if partner.get("connection", RoomDoorway.CONNECTION_DOOR) != link.get("connection", RoomDoorway.CONNECTION_DOOR):
			return "5: a door joins a non-door"
		var from: int = link["placement"]
		if not joins.has(from):
			joins[from] = []
		joins[from].append(int(partner["placement"]))
	# 4. No overlaps.
	var cells: Dictionary[Vector2i, bool] = {}
	for index: int in layout.placements.size():
		var placement: RoomPlacement = layout.placements[index]
		var size: Vector2i = RoomShape.of(_room(layout, index), _unit()).rotated_size(placement.rotation_steps)
		for x: int in size.x:
			for z: int in size.y:
				var cell := Vector2i(placement.cell.x + x, placement.cell.z + z)
				if cells.has(cell):
					return "4: two tiles overlap at %s" % cell
				cells[cell] = true
	# 3. Required rooms.
	var kinds: Dictionary[StringName, bool] = {}
	for index: int in layout.placements.size():
		kinds[_room(layout, index).room_kind] = true
	for kind_text: String in department.required_room_kinds:
		var kind := StringName(kind_text)
		if kind == &"start" or kind == &"lift" or not _has_tile(department, kind):
			continue
		if not kinds.has(kind):
			return "3: no %s room" % kind
	# 2. Locks open in some order, each with what it needs found without it.
	var locks: Array[int] = []
	for door: int in layout.doors.size():
		var type: int = layout.doors[door][3]
		if type == FloorGenerator.DOOR_PRY or type == FloorGenerator.DOOR_POWER or type == FloorGenerator.DOOR_KEYCARD:
			locks.append(door)
	var opened: Dictionary[int, bool] = {}
	var progress: bool = true
	while progress:
		progress = false
		var reach: Dictionary[int, bool] = _reach(layout, joins, locks, opened)
		for door: int in locks:
			if not opened.has(door) and _opens(layout, door, reach):
				opened[door] = true
				progress = true
	for door: int in locks:
		if not opened.has(door):
			return "2: the %s door into %s can't be opened" % [FloorGenerator.DOOR_NAMES[layout.doors[door][3]],
				_room(layout, layout.doors[door][0]).id]
	# 6. With every lock open: the start, the security room, every part and every key.
	var all_open: Dictionary[int, bool] = _reach(layout, joins, locks, opened)
	var needed: Array[int] = [0, 1]
	for part: Array in layout.lift_parts:
		needed.append(int(part[2]))
	for item: Array in layout.door_items:
		needed.append(str(item[1]).get_slice("/", 0).to_int())
	for index: int in needed:
		if not all_open.has(index):
			return "6: %s can't be reached" % _room(layout, index).id
	# 1. Carry paths: from the part's room through joined tiles to the elevator, never through a collapse.
	if layout.lift_parts.is_empty():
		return "1: no lift parts"
	for part_index: int in layout.lift_parts.size():
		var path: PackedInt32Array = layout.lift_part_paths[part_index]
		if path.is_empty() or path[0] != int(layout.lift_parts[part_index][2]) or path[path.size() - 1] != 0:
			return "1: the %s has no carry path" % str(layout.lift_parts[part_index][0])
		for step: int in range(1, path.size()):
			if not (joins.get(path[step - 1], []) as Array).has(path[step]) or layout.collapsed.has(path[step]):
				return "1: the %s's carry path is broken" % str(layout.lift_parts[part_index][0])
	# 7. Part rules: in rooms, not too many behind keycard doors.
	var keycards: Array[int] = []
	for door: int in locks:
		if layout.doors[door][3] == FloorGenerator.DOOR_KEYCARD:
			keycards.append(door)
	var without_cards: Dictionary[int, bool] = opened.duplicate()
	for door: int in keycards:
		without_cards.erase(door)
	var outside: Dictionary[int, bool] = _reach(layout, joins, locks, without_cards)
	var behind: int = 0
	for part: Array in layout.lift_parts:
		if _room(layout, int(part[2])).tile_role != TileStandards.ROLE_ROOM:
			return "7: the %s isn't in a room" % str(part[0])
		if not outside.has(int(part[2])):
			behind += 1
	if behind > tuning.by_bracket(tuning.parts_behind_keycards_max_by_bracket, layout.floor_number):
		return "7: %d parts behind keycard doors" % behind
	# 8. A part in a calm room.
	var hazards: Dictionary[int, bool] = {}
	for key: String in layout.active_markers.get(&"hazard", PackedStringArray()):
		hazards[key.get_slice("/", 0).to_int()] = true
	var calm: bool = false
	for part: Array in layout.lift_parts:
		var room: int = part[2]
		calm = calm or (not _room(layout, room).is_combat_room and not hazards.has(room))
	if not calm:
		return "8: every part is in a combat or hazard room"
	return ""


func _has_tile(department: DepartmentData, kind: StringName) -> bool:
	for room: RoomData in FloorGenerator.tile_pool(department):
		if room.room_kind == kind and room.tile_role == TileStandards.ROLE_ROOM:
			return true
	return false


## Tiles reachable from the elevator, not through collapses or locks still shut.
func _reach(layout: FloorLayout, joins: Dictionary[int, Array], locks: Array[int], opened: Dictionary[int, bool]) -> Dictionary[int, bool]:
	var shut: Dictionary[String, bool] = {}
	for door: int in locks:
		if not opened.has(door):
			var a: int = layout.doors[door][0]
			var b: int = layout.doors[door][2]
			shut["%d,%d" % [mini(a, b), maxi(a, b)]] = true
	var reached: Dictionary[int, bool] = {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var at: int = queue.pop_back()
		for next: int in joins.get(at, []):
			if reached.has(next) or layout.collapsed.has(next) or shut.has("%d,%d" % [mini(at, next), maxi(at, next)]):
				continue
			reached[next] = true
			queue.append(next)
	return reached


## Can this lock be opened by a team that reaches these tiles?
func _opens(layout: FloorLayout, door: int, reach: Dictionary[int, bool]) -> bool:
	var entry: Array = layout.doors[door]
	# CHANGED 2026-11-13: only from the approach side (the reader, breaker and pry point are there).
	if not reach.has(int(entry[2])):
		return false
	var type: int = entry[3]
	if type == FloorGenerator.DOOR_POWER and int(entry[4]) != 1:
		return reach.has(int(entry[2]))
	for item: Array in layout.door_items:
		var kind: String = item[0]
		var room: int = str(item[1]).get_slice("/", 0).to_int()
		var fits: bool = kind == "crowbar" if type == FloorGenerator.DOOR_PRY else int(item[2]) == door
		if fits and reach.has(room):
			return true
	return false
