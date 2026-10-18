class_name LevelGenerator
extends RefCounted
## Makes floor layouts: which rooms go where. Pure (no scene tree), so it is easy to test, and it
## only runs on the host. The same department, floor and seed always give the same layout.
##
## How a floor grows: players arrive in the elevator, so the lift room goes at cell (0, 0). Then rooms
## are added one at a time, each joined to a free doorway of a room already placed (the new room must
## have a doorway facing back, and must fit in empty cells): first "filler" rooms (normal, corridor),
## then the special rooms the department rolled (optional_room_chances), and last any other required
## rooms, as far from the lift as possible. Doorways nothing joined get a wall plug when built.
## A boss floor is the lift room with the boss arena joined to it.

## The room every floor starts in: the cargo lift (the elevator players arrive in).
const KIND_LIFT: StringName = &"lift"
## An old name for the first room: treated like "lift" in required_room_kinds.
const KIND_START: StringName = &"start"
const KIND_BOSS_ARENA: StringName = &"boss_arena"
## Room kinds used to fill a floor up to its room count.
const FILLER_KINDS: Array[StringName] = [&"normal", &"corridor"]


## The rooms a department can use on a floor: its room_ids plus every shared room (no department_ids),
## or rooms that list it, without disabled ones or ones whose min_floor is later. Sorted by id.
static func room_pool(department: DepartmentData, floor_in_department: int) -> Array[RoomData]:
	var pool: Array[RoomData] = []
	for content: ContentData in ContentRegistry.get_all(&"room"):
		var room := content as RoomData
		if room == null or room.scene == null or room.min_floor > floor_in_department:
			continue
		var allowed: bool = room.department_ids.is_empty() or room.department_ids.has(department.id) \
			or department.room_ids.has(room.id)
		if allowed:
			pool.append(room)
	return pool


static func generate(department: DepartmentData, floor_in_department: int, floor_number: int, run_seed: int,
		_player_count: int, config: GameConfig = null) -> FloorLayout:
	var game: GameConfig = config if config != null else Config.game
	var rng: RandomNumberGenerator = SeededRng.make(run_seed, &"level_layout", floor_number)
	var pool: Array[RoomData] = room_pool(department, floor_in_department)
	var layout := _new_layout(department, floor_number, run_seed, false)
	var floor_plan := _Plan.new(layout, game.room_cell_size)
	var starts: Array[RoomData] = _of_kind(pool, [KIND_LIFT])
	if starts.is_empty():
		push_warning("LevelGenerator: department '%s' has no lift room." % department.id)
		return layout
	floor_plan.place(_pick(starts, rng), Vector2i.ZERO, rng.randi_range(0, 3))

	var target: int = rng.randi_range(department.rooms_per_floor_min,
		maxi(department.rooms_per_floor_max, department.rooms_per_floor_min))
	var specials: Array[StringName] = []
	var chance_kinds: Array = department.optional_room_chances.keys()
	chance_kinds.sort()
	for kind: Variant in chance_kinds:
		var chance: float = department.optional_room_chances[kind]
		if rng.randf() < chance:
			specials.append(StringName(str(kind)))
	var required: Array[StringName] = []
	for kind: String in department.required_room_kinds:
		if StringName(kind) != KIND_START and StringName(kind) != KIND_LIFT:
			required.append(StringName(kind))

	# Fillers, joined to random free doorways.
	var fillers: Array[RoomData] = _of_kind(pool, FILLER_KINDS)
	var filler_goal: int = target - 1 - specials.size() - required.size()
	var placed_fillers: int = 0
	while placed_fillers < filler_goal and not floor_plan.open.is_empty() and not fillers.is_empty():
		var index: int = rng.randi_range(0, floor_plan.open.size() - 1)
		if floor_plan.try_place_at(floor_plan.open[index], fillers, rng):
			placed_fillers += 1
		else:
			floor_plan.open.remove_at(index)
	# Special rooms anywhere, then the required ones as far from the start as possible.
	for kind: StringName in specials:
		floor_plan.place_somewhere(_of_kind(pool, [kind]), rng, false)
	for kind: StringName in required:
		if not floor_plan.place_somewhere(_of_kind(pool, [kind]), rng, true):
			push_warning("LevelGenerator: couldn't fit a '%s' room on floor %d." % [kind, floor_number])
	return layout


## A boss floor: the lift room (players arrive in the elevator) with a boss arena joined to it.
static func generate_boss_floor(department: DepartmentData, floor_number: int, run_seed: int,
		config: GameConfig = null) -> FloorLayout:
	var game: GameConfig = config if config != null else Config.game
	var rng: RandomNumberGenerator = SeededRng.make(run_seed, &"level_layout", floor_number)
	var pool: Array[RoomData] = room_pool(department, 1000)
	var layout := _new_layout(department, floor_number, run_seed, true)
	var lifts: Array[RoomData] = _of_kind(pool, [KIND_LIFT])
	var arenas: Array[RoomData] = _of_kind(pool, [KIND_BOSS_ARENA])
	if lifts.is_empty() or arenas.is_empty():
		push_warning("LevelGenerator: department '%s' needs a lift room and a boss arena." % department.id)
		return layout
	var floor_plan := _Plan.new(layout, game.room_cell_size)
	floor_plan.place(_pick(lifts, rng), Vector2i.ZERO, rng.randi_range(0, 3))
	if not floor_plan.place_somewhere(arenas, rng, true):
		push_warning("LevelGenerator: couldn't join a boss arena to the lift room.")
	return layout


## Every doorway on a built floor, in placement order: {"placement": int, "cell": Vector2i,
## "dir": Vector2i, "width", "height", "name", "connected": bool}. Connected = the room next door has a
## doorway on the same edge; the rest get wall plugs.
static func doorway_links(layout: FloorLayout, cell_size: float) -> Array[Dictionary]:
	var floor_plan := _Plan.new(FloorLayout.new(), cell_size)
	var all: Array[Dictionary] = []
	for index: int in layout.placements.size():
		var placement: RoomPlacement = layout.placements[index]
		var room := ContentRegistry.get_content(placement.room_id) as RoomData
		if room == null:
			continue
		var corner := Vector2i(placement.cell.x, placement.cell.z)
		for doorway: Dictionary in RoomShape.of(room, cell_size).rotated_doorways(placement.rotation_steps):
			var entry: Dictionary = doorway.duplicate()
			entry["placement"] = index
			entry["cell"] = corner + (doorway["cell"] as Vector2i)
			all.append(entry)
	var edges: Dictionary[String, bool] = {}
	for entry: Dictionary in all:
		var cell: Vector2i = entry["cell"]
		var dir: Vector2i = entry["dir"]
		edges[floor_plan.edge_key(cell, dir)] = true
	for entry: Dictionary in all:
		var cell: Vector2i = entry["cell"]
		var dir: Vector2i = entry["dir"]
		entry["connected"] = edges.has(floor_plan.edge_key(cell + dir, -dir))
	return all


static func _new_layout(department: DepartmentData, floor_number: int, run_seed: int, boss: bool) -> FloorLayout:
	var layout := FloorLayout.new()
	layout.department_id = department.id
	layout.floor_number = floor_number
	layout.floor_seed = hash("%d|%d" % [run_seed, floor_number])
	layout.is_boss_floor = boss
	return layout


static func _of_kind(pool: Array[RoomData], kinds: Array[StringName]) -> Array[RoomData]:
	var rooms: Array[RoomData] = []
	for room: RoomData in pool:
		if kinds.has(room.room_kind):
			rooms.append(room)
	return rooms


## Picks a room by weight.
static func _pick(rooms: Array[RoomData], rng: RandomNumberGenerator) -> RoomData:
	var weights := PackedFloat32Array()
	for room: RoomData in rooms:
		weights.append(room.weight)
	var index: int = SeededRng.pick_weighted(rng, weights)
	return rooms[maxi(index, 0)]


## The rooms in the order to try them: picked by weight, one after another without repeats.
static func _weighted_order(rooms: Array[RoomData], rng: RandomNumberGenerator) -> Array[RoomData]:
	var left: Array[RoomData] = rooms.duplicate()
	var order: Array[RoomData] = []
	while not left.is_empty():
		var picked: RoomData = _pick(left, rng)
		order.append(picked)
		left.erase(picked)
	return order


## A floor being put together: which cells are taken and which doorways are still free.
class _Plan:
	extends RefCounted

	var layout: FloorLayout
	var cell_size: float
	## Grid cell (x, z) -> placement index.
	var occupied: Dictionary[Vector2i, int] = {}
	## Free doorways: {"cell": Vector2i, "dir": Vector2i, "placement": int}.
	var open: Array[Dictionary] = []
	var copies: Dictionary[StringName, int] = {}

	func _init(for_layout: FloorLayout, size: float) -> void:
		layout = for_layout
		cell_size = size

	func edge_key(cell: Vector2i, dir: Vector2i) -> String:
		return "%d,%d,%d,%d" % [cell.x, cell.y, dir.x, dir.y]

	func place(room: RoomData, corner: Vector2i, steps: int) -> void:
		var index: int = layout.placements.size()
		layout.placements.append(RoomPlacement.make(room.id, Vector3i(corner.x, 0, corner.y), steps))
		copies[room.id] = copies.get(room.id, 0) + 1
		var shape: RoomShape = RoomShape.of(room, cell_size)
		var size: Vector2i = shape.rotated_size(steps)
		for x: int in size.x:
			for z: int in size.y:
				occupied[corner + Vector2i(x, z)] = index
		for doorway: Dictionary in shape.rotated_doorways(steps):
			open.append({"cell": corner + (doorway["cell"] as Vector2i), "dir": doorway["dir"], "placement": index})
		# Doorways that now face a taken cell can't grow any more.
		var still_open: Array[Dictionary] = []
		for entry: Dictionary in open:
			if not occupied.has((entry["cell"] as Vector2i) + (entry["dir"] as Vector2i)):
				still_open.append(entry)
		open = still_open

	## Tries to join one of these rooms (any turn, any of its doorways) to a free doorway.
	func try_place_at(at: Dictionary, rooms: Array[RoomData], rng: RandomNumberGenerator) -> bool:
		var target: Vector2i = (at["cell"] as Vector2i) + (at["dir"] as Vector2i)
		var facing: Vector2i = -(at["dir"] as Vector2i)
		for room: RoomData in LevelGenerator._weighted_order(rooms, rng):
			if room.max_per_floor > 0 and copies.get(room.id, 0) >= room.max_per_floor:
				continue
			var shape: RoomShape = RoomShape.of(room, cell_size)
			var first_turn: int = rng.randi_range(0, 3)
			for turn: int in 4:
				var steps: int = (first_turn + turn) % 4
				for doorway: Dictionary in shape.rotated_doorways(steps):
					if doorway["dir"] != facing:
						continue
					var corner: Vector2i = target - (doorway["cell"] as Vector2i)
					if _fits(corner, shape.rotated_size(steps)):
						place(room, corner, steps)
						return true
		return false

	## Places one of these rooms at some free doorway: random, or the farthest from the start first.
	func place_somewhere(rooms: Array[RoomData], rng: RandomNumberGenerator, farthest_first: bool) -> bool:
		if rooms.is_empty():
			return false
		var tries: Array[Dictionary] = open.duplicate()
		if farthest_first:
			tries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _distance(a) > _distance(b))
		else:
			for index: int in range(tries.size() - 1, 0, -1):
				var other: int = rng.randi_range(0, index)
				var swap: Dictionary = tries[index]
				tries[index] = tries[other]
				tries[other] = swap
		for at: Dictionary in tries:
			if try_place_at(at, rooms, rng):
				return true
		return false

	func _distance(entry: Dictionary) -> int:
		var cell: Vector2i = (entry["cell"] as Vector2i) + (entry["dir"] as Vector2i)
		return absi(cell.x) + absi(cell.y)

	func _fits(corner: Vector2i, size: Vector2i) -> bool:
		for x: int in size.x:
			for z: int in size.y:
				if occupied.has(corner + Vector2i(x, z)):
					return false
		return true
