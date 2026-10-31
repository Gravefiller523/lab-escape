class_name FloorGenerator
extends RefCounted
## NEW 2026-10-31 (floor generation step 3): makes floor layouts from the 3 m tiles. Pure (no scene tree:
## it only does bookkeeping on a grid), so it is easy to test, and it only runs on the host. The same
## department, floor and seed always give the same layout. Plan: docs/design/floor-generation-plan.md.
##
## How a floor grows (section 5 of the plan, steps 1 to 4 and a simple step 5):
## 1. The elevator at cell (0, 0), its open side facing -z; the welcome center joined to that open side.
## 2. A main hallway (2 units wide) grows out of each of the welcome center's two connectors: walled
##    straight pieces (3 or 5 long, 1-long fillers to hit the length), now and then a corner, then an end.
## 3. Branches: at each side doorway (in a shuffled order) a room, a cluster of rooms, a secondary hallway
##    (1 wide, which branches again up to the depth limit and ends in a room) or nothing. Each branch off a
##    main hallway is a wing ("West wing B"). Growth stops at the floor's target room count.
## 4. Loops: a few short hallways between free doorways of different wings that face each other.
## 5. (simple, for now) every room is a shared room (offices, storage...) picked when it is placed.
## Sockets nothing joined get a cap when the floor is built (Level.build). Markers: a share of the
## "prop_spawn" markers is switched on (FloorLayout.active_markers).
## If an attempt fails the checks, the next attempt (a new seed from the same floor seed) is tried; after
## Config.floor_gen.max_attempts it builds the safe fallback floor and says so loudly.

## Piece kinds, read from each hallway tile's open sides (see piece_kind()).
const PIECE_STRAIGHT: StringName = &"straight"
const PIECE_CORNER: StringName = &"corner"
const PIECE_T: StringName = &"t"
const PIECE_CROSS: StringName = &"cross"
const PIECE_END: StringName = &"end"
const DIRECTION_NAMES: Dictionary[Vector2i, String] = {Vector2i(-1, 0): "West", Vector2i(1, 0): "East",
	Vector2i(0, -1): "North", Vector2i(0, 1): "South"}
const LOG_PATH: String = "user://floorgen/last_floor.log"

## Host, debug: the next floor generated uses this floor seed instead of the run's (0 = none).
static var _next_seed_override: int = 0
## The last floor this PC generated for a run (for `floorgen log`).
static var last_layout: FloorLayout


## Debug (F9, `floorgen <seed>`): the next generated floor uses this seed.
static func set_next_seed(floor_seed: int) -> void:
	_next_seed_override = floor_seed


## Makes a floor. floor_number counts across the run (1 = the first floor). player_count isn't used yet.
static func generate(department: DepartmentData, floor_number: int, run_seed: int, _player_count: int = 1,
		tuning: FloorGenTuning = null) -> FloorLayout:
	var numbers: FloorGenTuning = tuning if tuning != null else Config.floor_gen
	var floor_seed: int = hash("%d|%d" % [run_seed, floor_number])
	if _next_seed_override != 0:
		floor_seed = _next_seed_override
		_next_seed_override = 0
	return generate_from_seed(department, floor_number, floor_seed, numbers)


## Makes a floor from a floor seed (what F9 and `floorgen <seed>` set), trying again on failure.
static func generate_from_seed(department: DepartmentData, floor_number: int, floor_seed: int,
		numbers: FloorGenTuning) -> FloorLayout:
	var log_lines := PackedStringArray()
	var department_id: StringName = department.id if department != null else &""
	for attempt: int in maxi(numbers.max_attempts, 1):
		var builder := _Builder.new(department, floor_number, floor_seed, attempt, numbers)
		var layout: FloorLayout = builder.build()
		log_lines.append_array(builder.log_lines)
		if builder.problem.is_empty():
			log_lines.append("floor %d %s seed %d attempt %d: OK (%d tiles, %d rooms, %d wings, %d loops)" % [
				floor_number, department_id, floor_seed, attempt, layout.placements.size(), builder.rooms,
				layout.wings.size(), layout.loops.size()])
			layout.log_lines = log_lines
			return layout
		log_lines.append("floor %d seed %d attempt %d failed: %s" % [floor_number, floor_seed, attempt, builder.problem])
	var fallback := _Builder.new(department, floor_number, floor_seed, numbers.max_attempts, numbers)
	var safe: FloorLayout = fallback.build_fallback()
	log_lines.append_array(fallback.log_lines)
	log_lines.append("FALLBACK: floor %d seed %d: every attempt failed, built the safe fallback floor." % [
		floor_number, floor_seed])
	push_warning("FloorGenerator: floor %d seed %d used the safe fallback floor (see the log)." % [floor_number, floor_seed])
	safe.log_lines = log_lines
	return safe


## Host, in a run: makes the floor, prints its log to the Output panel and saves it to LOG_PATH.
static func generate_for_run(department: DepartmentData, floor_number: int, run_seed: int,
		player_count: int) -> FloorLayout:
	var layout: FloorLayout = generate(department, floor_number, run_seed, player_count)
	report(layout)
	return layout


## Prints a layout's log ("[floorgen] ..." lines) and saves it to LOG_PATH; remembers it as last_layout.
static func report(layout: FloorLayout) -> void:
	last_layout = layout
	for line: String in layout.log_lines:
		print("[floorgen] %s" % line)
	DirAccess.make_dir_recursive_absolute(LOG_PATH.get_base_dir())
	var file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(layout.log_lines) + "\n")
		file.close()


## Every 3 m tile a department can use (shared ones plus its own), enabled, sorted by id.
static func tile_pool(department: DepartmentData) -> Array[RoomData]:
	var pool: Array[RoomData] = []
	for content: ContentData in ContentRegistry.get_all(&"room"):
		var room := content as RoomData
		if room == null or room.scene == null or room.grid != RoomData.GRID_TILE:
			continue
		var department_id: StringName = department.id if department != null else &""
		if room.department_ids.is_empty() or room.department_ids.has(department_id):
			pool.append(room)
	pool.sort_custom(func(a: RoomData, b: RoomData) -> bool: return String(a.id) < String(b.id))
	return pool


## What a hallway tile is, from its open sides (unturned): 2 opposite = straight, 2 next to each other =
## corner, 3 = T, 4 = cross, 1 = end. So a new hallway piece needs no code, only the right open sides.
static func piece_kind(room: RoomData) -> StringName:
	var sides: Dictionary[Vector2i, bool] = {}
	for doorway: Dictionary in RoomShape.of(room, Config.floor_gen.grid_unit).doorways:
		if doorway["open_edge"]:
			sides[doorway["dir"] as Vector2i] = true
	match sides.size():
		1:
			return PIECE_END
		2:
			var dirs: Array[Vector2i] = sides.keys()
			return PIECE_STRAIGHT if dirs[0] == -dirs[1] else PIECE_CORNER
		3:
			return PIECE_T
		4:
			return PIECE_CROSS
	return &""


## A floor being put together: which cells are taken, every socket, wings and the log.
class _Builder:
	extends RefCounted

	var department: DepartmentData
	var floor_number: int
	var floor_seed: int
	var attempt: int
	var tuning: FloorGenTuning
	var unit: float
	var layout := FloorLayout.new()
	var log_lines := PackedStringArray()
	var problem: String = ""
	var rooms: int = 0
	var target_rooms: int = 0
	## Grid cell -> placement index.
	var occupied: Dictionary[Vector2i, int] = {}
	## Edge key -> socket {"placement", "cell", "dir", "open", "name"}.
	var sockets: Dictionary[String, Dictionary] = {}
	## Each placement's sockets (the same dictionaries).
	var placement_sockets: Array[Array] = []
	## Tiles sorted by what they are.
	var elevators: Array[RoomData] = []
	var welcome_centers: Array[RoomData] = []
	var main_pieces: Dictionary[StringName, Array] = {}
	var hall_pieces: Dictionary[StringName, Array] = {}
	var shared_rooms: Array[RoomData] = []
	var wing_counts: Dictionary[int, int] = {}

	func _init(for_department: DepartmentData, number: int, seed_value: int, attempt_index: int,
			numbers: FloorGenTuning) -> void:
		department = for_department
		floor_number = number
		floor_seed = seed_value
		attempt = attempt_index
		tuning = numbers
		unit = numbers.grid_unit
		layout.department_id = department.id if department != null else &""
		layout.floor_number = floor_number
		layout.floor_seed = floor_seed
		layout.grid = RoomData.GRID_TILE
		layout.attempt = attempt
		_sort_tiles()

	func _rng(step: StringName) -> RandomNumberGenerator:
		return SeededRng.make(floor_seed, step, attempt)

	func _log(line: String) -> void:
		log_lines.append("  attempt %d: %s" % [attempt, line])

	func _sort_tiles() -> void:
		for room: RoomData in FloorGenerator.tile_pool(department):
			match room.tile_role:
				TileStandards.ROLE_TEMPLATE:
					if room.room_kind == &"lift":
						elevators.append(room)
					elif room.room_kind == &"welcome_center":
						welcome_centers.append(room)
				TileStandards.ROLE_MAIN_HALL:
					_add_piece(main_pieces, room)
				TileStandards.ROLE_SECONDARY_HALL:
					_add_piece(hall_pieces, room)
				TileStandards.ROLE_ROOM:
					shared_rooms.append(room)

	func _add_piece(pieces: Dictionary[StringName, Array], room: RoomData) -> void:
		var kind: StringName = FloorGenerator.piece_kind(room)
		if kind == FloorGenerator.PIECE_STRAIGHT:
			# Straight pieces by length: "straight1" (filler), "straight3", "straight5"...
			kind = StringName("straight%d" % room.size_cells.z)
		if not pieces.has(kind):
			pieces[kind] = []
		pieces[kind].append(room)

	# --- The steps -------------------------------------------------------------------------------------

	func build() -> FloorLayout:
		target_rooms = int(FloorGenTuning.grown(float(tuning.target_rooms_base), tuning.target_rooms_per_floor,
			float(tuning.target_rooms_cap), floor_number))
		var connectors: Array[Array] = _place_start()
		if not problem.is_empty():
			return layout
		var hall_rng: RandomNumberGenerator = _rng(&"floorgen_main_halls")
		for connector: Array in connectors:
			_grow_main_hall(connector, hall_rng)
		_grow_branches()
		_add_loops()
		_pick_markers()
		_check()
		layout.stats["rooms"] = rooms
		return layout

	## Step 1: the elevator and the welcome center. Returns the welcome center's connectors (groups of
	## open sockets facing the same way), where the main hallways start.
	func _place_start() -> Array[Array]:
		var connectors: Array[Array] = []
		if elevators.is_empty() or welcome_centers.is_empty():
			problem = "no elevator or welcome center tile"
			return connectors
		var rng: RandomNumberGenerator = _rng(&"floorgen_start")
		var elevator: int = _place(_pick(elevators, rng), Vector2i.ZERO, 0, -1)
		var opening: Array[Dictionary] = _open_sockets_of(elevator)
		var welcome: int = -1
		if not opening.is_empty():
			welcome = _attach(opening[0], [_pick(_department_first(welcome_centers), rng)], 1, -1, rng, opening)
		if welcome < 0:
			problem = "the welcome center doesn't fit the elevator's open side"
			return connectors
		var by_dir: Dictionary[Vector2i, Array] = {}
		for socket: Dictionary in _open_sockets_of(welcome):
			var dir: Vector2i = socket["dir"]
			if not by_dir.has(dir):
				by_dir[dir] = []
			by_dir[dir].append(socket)
		var dirs: Array[Vector2i] = by_dir.keys()
		dirs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		for dir: Vector2i in dirs:
			connectors.append(by_dir[dir])
		_log("elevator and %s placed; %d main hallway connectors" % [layout.placements[welcome].room_id, connectors.size()])
		return connectors

	## Step 2: one main hallway out of a connector.
	func _grow_main_hall(connector: Array, rng: RandomNumberGenerator) -> void:
		var dir: Vector2i = (connector[0] as Dictionary)["dir"]
		var lo: float = FloorGenTuning.grown(float(tuning.main_hall_length_min), tuning.main_hall_length_per_floor,
			float(tuning.main_hall_length_cap), floor_number)
		var hi: float = FloorGenTuning.grown(float(tuning.main_hall_length_max), tuning.main_hall_length_per_floor,
			float(tuning.main_hall_length_cap), floor_number)
		var length: int = rng.randi_range(int(lo), int(hi))
		var frontier: Array[Dictionary] = []
		for socket: Variant in connector:
			frontier.append(socket as Dictionary)
		var grown: Dictionary = _grow_hall(frontier, main_pieces, length, tuning.main_hall_turn_chance,
			tuning.main_hall_max_turns, 0.0, -1, -dir, rng)
		var pieces: PackedInt32Array = grown["pieces"]
		layout.main_halls.append(pieces)
		_log("%s main hallway: %d of %d units, %d pieces" % [DIRECTION_NAMES.get(dir, "?"), grown["length"], length,
			pieces.size()])

	## Grows a hallway from open sockets (the frontier): pieces until `length` units, then an end piece.
	## Returns {"pieces": PackedInt32Array, "length": int, "splits": Array (frontiers left by T junctions)}.
	func _grow_hall(start: Array[Dictionary], pieces: Dictionary[StringName, Array], length: int, turn_chance: float,
			max_turns: int, split_chance: float, wing: int, back: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
		var frontier: Array[Dictionary] = start
		var placed := PackedInt32Array()
		var splits: Array = []
		var done: int = 0
		var turns: int = 0
		while done < length and not frontier.is_empty():
			var left: int = length - done
			var kinds: Array[StringName] = []
			if done > 0 and turns < max_turns and rng.randf() < turn_chance:
				kinds.append(FloorGenerator.PIECE_CORNER)
			if done > 0 and rng.randf() < split_chance:
				kinds.append(FloorGenerator.PIECE_T)
			if left >= 5 and rng.randf() < tuning.main_hall_long_piece_share:
				kinds.append(&"straight5")
			if left >= 3:
				kinds.append(&"straight3")
			kinds.append(&"straight1")
			var index: int = -1
			var kind_used: StringName = &""
			for kind: StringName in kinds:
				if not pieces.has(kind):
					continue
				index = _attach(frontier[0], _typed(pieces[kind]), 1, wing, rng, frontier, back)
				if index >= 0:
					kind_used = kind
					break
			if index < 0:
				break
			placed.append(index)
			var size: Vector2i = _size_of(index)
			done += maxi(size.x, size.y) if kind_used == FloorGenerator.PIECE_CORNER else maxi(1, _length_of(index))
			if kind_used == FloorGenerator.PIECE_CORNER:
				turns += 1
			var exits: Array[Array] = _exit_groups(index)
			if exits.is_empty():
				frontier = []
				break
			var pick: int = rng.randi_range(0, exits.size() - 1)
			frontier = _typed_sockets(exits[pick])
			for other: int in exits.size():
				if other != pick:
					splits.append(exits[other])
		if not frontier.is_empty() and pieces.has(FloorGenerator.PIECE_END):
			var end: int = _attach(frontier[0], _typed(pieces[FloorGenerator.PIECE_END]), 1, wing, rng, frontier, back)
			if end >= 0:
				placed.append(end)
		return {"pieces": placed, "length": done, "splits": splits}

	## Step 3: branches off every side doorway (main hallways first, then what grows from them).
	func _grow_branches() -> void:
		var rng: RandomNumberGenerator = _rng(&"floorgen_branches")
		var queue: Array[Dictionary] = []
		for hall: int in layout.main_halls.size():
			var hall_dir: String = _main_hall_name(hall)
			for piece: int in layout.main_halls[hall]:
				for socket: Dictionary in _door_sockets_of(piece):
					queue.append({"socket": socket, "depth": 0, "wing": -1, "hall": hall_dir, "must_room": false,
						"exit": false})
		_shuffle(queue, rng)
		var max_depth: int = tuning.by_bracket(tuning.max_branch_depth_by_bracket, floor_number)
		var index: int = 0
		while index < queue.size():
			var item: Dictionary = queue[index]
			index += 1
			if rooms >= target_rooms:
				break
			var socket: Dictionary = item["socket"]
			if _is_joined(socket) or occupied.has((socket["cell"] as Vector2i) + (socket["dir"] as Vector2i)):
				continue
			var depth: int = item["depth"]
			var wing: int = item["wing"]
			var choice: StringName = _roll_branch(rng, depth < max_depth, item["must_room"])
			if item["exit"]:
				# A T junction's other way: another hallway while the depth limit allows it, else a cap.
				choice = &"hall" if depth < max_depth else &"nothing"
			if choice == &"nothing":
				continue
			var new_wing: bool = wing < 0
			if new_wing:
				wing = _new_wing(String(item["hall"]))
			var placed: bool = false
			match choice:
				&"room":
					placed = _attach(socket, shared_rooms, 0, wing, rng) >= 0
					if placed:
						rooms += 1
				&"cluster":
					placed = _place_cluster(socket, wing, rng)
				&"hall":
					placed = _place_secondary(socket, wing, depth, rng, queue)
			if not placed and new_wing and _wing_is_empty(wing):
				# Nothing grew: forget the wing again.
				layout.wings.resize(layout.wings.size() - 1)
				wing_counts[_main_hall_index(String(item["hall"]))] -= 1
		_log("branches: %d rooms (target %d), %d wings" % [rooms, target_rooms, layout.wings.size()])

	func _roll_branch(rng: RandomNumberGenerator, hall_allowed: bool, must_room: bool) -> StringName:
		var weights := PackedFloat32Array([tuning.branch_room_weight, tuning.branch_cluster_weight,
			tuning.branch_hall_weight if hall_allowed and not must_room else 0.0,
			0.0 if must_room else tuning.branch_nothing_weight])
		var names: Array[StringName] = [&"room", &"cluster", &"hall", &"nothing"]
		var picked: int = SeededRng.pick_weighted(rng, weights)
		return names[maxi(picked, 0)]

	func _place_cluster(socket: Dictionary, wing: int, rng: RandomNumberGenerator) -> bool:
		var first: int = _attach(socket, shared_rooms, 0, wing, rng)
		if first < 0:
			return false
		rooms += 1
		var cluster: Array[int] = [first]
		var wanted: int = rng.randi_range(tuning.cluster_rooms_min, tuning.cluster_rooms_max)
		while cluster.size() < wanted and rooms < target_rooms:
			var doors: Array[Dictionary] = []
			for member: int in cluster:
				for door: Dictionary in _door_sockets_of(member):
					if not occupied.has((door["cell"] as Vector2i) + (door["dir"] as Vector2i)):
						doors.append(door)
			_shuffle(doors, rng)
			var added: int = -1
			for door: Dictionary in doors:
				added = _attach(door, shared_rooms, 0, wing, rng)
				if added >= 0:
					break
			if added < 0:
				break
			cluster.append(added)
			rooms += 1
		return true

	## A secondary hallway out of a doorway: its side doorways and its end (and T junction exits) go on the
	## queue one level deeper; its end leads to a room.
	func _place_secondary(socket: Dictionary, wing: int, depth: int, rng: RandomNumberGenerator,
			queue: Array[Dictionary]) -> bool:
		var length: int = rng.randi_range(tuning.secondary_hall_length_min, tuning.secondary_hall_length_max)
		var grown: Dictionary = _grow_hall([socket] as Array[Dictionary], hall_pieces, length,
			tuning.secondary_turn_chance, tuning.main_hall_max_turns, tuning.secondary_split_chance, wing,
			-(socket["dir"] as Vector2i), rng)
		var pieces: PackedInt32Array = grown["pieces"]
		if pieces.is_empty():
			return false
		layout.stats["max_depth"] = maxi(layout.stats.get("max_depth", 0), depth + 1)
		for piece: int in pieces:
			var is_end: bool = FloorGenerator.piece_kind(_room_of(piece)) == FloorGenerator.PIECE_END
			for door: Dictionary in _door_sockets_of(piece):
				queue.append({"socket": door, "depth": depth + 1, "wing": wing, "hall": "", "must_room": is_end,
					"exit": false})
		for split: Variant in grown["splits"]:
			var exits: Array = split
			if not exits.is_empty():
				queue.append({"socket": exits[0], "depth": depth + 1, "wing": wing, "hall": "", "must_room": false,
					"exit": true})
		return true

	## Step 4: short hallways (1-unit fillers) between free doorways of different wings that face each other
	## across a few empty cells, so blocked routes later have a way round.
	func _add_loops() -> void:
		var wanted: int = tuning.by_bracket(tuning.loops_by_bracket, floor_number)
		var fillers: Array = hall_pieces.get(&"straight1", [])
		if wanted <= 0 or fillers.is_empty():
			return
		var rng: RandomNumberGenerator = _rng(&"floorgen_loops")
		var candidates: Array[Dictionary] = []
		var keys: Array[String] = sockets.keys()
		keys.sort()
		for key: String in keys:
			var socket: Dictionary = sockets[key]
			if _is_joined(socket):
				continue
			var cell: Vector2i = socket["cell"]
			var dir: Vector2i = socket["dir"]
			for step: int in range(1, tuning.loop_max_gap_units + 2):
				var at: Vector2i = cell + dir * step
				if not occupied.has(at):
					continue
				var other_key: String = _edge_key(at, -dir)
				if step > 1 and sockets.has(other_key):
					var other: Dictionary = sockets[other_key]
					var wing_a: int = layout.placements[socket["placement"]].wing
					var wing_b: int = layout.placements[other["placement"]].wing
					if wing_a != wing_b and String(key) < other_key:
						candidates.append({"a": socket, "b": other, "gap": step - 1})
				break
		_shuffle(candidates, rng)
		for candidate: Dictionary in candidates:
			if layout.loops.size() >= wanted:
				break
			var a: Dictionary = candidate["a"]
			var b: Dictionary = candidate["b"]
			if _is_joined(a) or _is_joined(b):
				continue
			var dir: Vector2i = a["dir"]
			var cells: Array[Vector2i] = []
			for step: int in range(1, int(candidate["gap"]) + 1):
				cells.append((a["cell"] as Vector2i) + dir * step)
			var free: bool = true
			for cell: Vector2i in cells:
				free = free and not occupied.has(cell)
			if not free:
				continue
			var steps: int = 0 if dir.x == 0 else 1
			var wing: int = layout.placements[a["placement"]].wing
			for cell: Vector2i in cells:
				_place(_pick(_typed(fillers), rng), cell, steps, wing)
			layout.loops.append(Vector2i(a["placement"], b["placement"]))
		_log("loops: %d of %d wanted (%d places a loop could go)" % [layout.loops.size(), wanted, candidates.size()])

	## A stand-in for step 10: switch on a share of the prop_spawn markers.
	func _pick_markers() -> void:
		var rng: RandomNumberGenerator = _rng(&"floorgen_markers")
		var keys := PackedStringArray()
		for index: int in layout.placements.size():
			for marker: Dictionary in RoomShape.of(_room_of(index), unit).markers:
				if marker["kind"] == &"prop_spawn" and rng.randf() < tuning.prop_spawn_share:
					keys.append(FloorLayout.marker_key(index, marker["path"]))
		layout.active_markers[&"prop_spawn"] = keys

	## The checks for this step (step 12 of the plan adds the rest).
	func _check() -> void:
		if not problem.is_empty():
			return
		if layout.main_halls.size() < 2:
			problem = "only %d main hallways" % layout.main_halls.size()
			return
		for hall: int in layout.main_halls.size():
			var units: int = 0
			for piece: int in layout.main_halls[hall]:
				units += _length_of(piece)
			if units < tuning.min_main_hall_units:
				problem = "main hallway %d is only %d units long" % [hall, units]
				return
		var needed: int = maxi(1, ceili(float(target_rooms) * tuning.min_rooms_share))
		if rooms < needed:
			problem = "only %d rooms (needs %d of the target %d)" % [rooms, needed, target_rooms]

	## The safe fallback floor: the elevator, the welcome center, a short straight main hallway each way
	## with a room at each end. No randomness that can fail.
	func build_fallback() -> FloorLayout:
		layout.is_fallback = true
		var connectors: Array[Array] = _place_start()
		if not problem.is_empty():
			return layout
		var rng: RandomNumberGenerator = _rng(&"floorgen_fallback")
		for connector: Array in connectors:
			var frontier: Array[Dictionary] = _typed_sockets(connector)
			var grown: Dictionary = _grow_hall(frontier, main_pieces, 3, 0.0, 0, 0.0, -1, Vector2i.ZERO, rng)
			var pieces: PackedInt32Array = grown["pieces"]
			layout.main_halls.append(pieces)
			if pieces.is_empty():
				continue
			var wing: int = _new_wing(_main_hall_name(layout.main_halls.size() - 1))
			for door: Dictionary in _door_sockets_of(pieces[pieces.size() - 1]):
				if _attach(door, shared_rooms, 0, wing, rng) >= 0:
					rooms += 1
					break
		_pick_markers()
		return layout

	# --- Grid bookkeeping --------------------------------------------------------------------------------

	func _edge_key(cell: Vector2i, dir: Vector2i) -> String:
		return "%d,%d,%d,%d" % [cell.x, cell.y, dir.x, dir.y]

	func _place(room: RoomData, corner: Vector2i, steps: int, wing: int) -> int:
		var index: int = layout.placements.size()
		layout.placements.append(RoomPlacement.make(room.id, Vector3i(corner.x, 0, corner.y), steps, wing))
		var shape: RoomShape = RoomShape.of(room, unit)
		var size: Vector2i = shape.rotated_size(steps)
		for x: int in size.x:
			for z: int in size.y:
				occupied[corner + Vector2i(x, z)] = index
		var own: Array = []
		for doorway: Dictionary in shape.rotated_doorways(steps):
			var socket: Dictionary = {"placement": index, "cell": corner + (doorway["cell"] as Vector2i),
				"dir": doorway["dir"], "open": doorway["open_edge"], "name": doorway["name"]}
			sockets[_edge_key(socket["cell"], socket["dir"])] = socket
			own.append(socket)
		placement_sockets.append(own)
		return index

	func _fits(corner: Vector2i, size: Vector2i) -> bool:
		for x: int in size.x:
			for z: int in size.y:
				if occupied.has(corner + Vector2i(x, z)):
					return false
		return true

	func _is_joined(socket: Dictionary) -> bool:
		return sockets.has(_edge_key((socket["cell"] as Vector2i) + (socket["dir"] as Vector2i), -(socket["dir"] as Vector2i)))

	## Joins one of these tiles to a free socket (any turn, any of its sockets that faces it).
	## open: 1 = the tile's socket must be an open edge, 0 = a doorway, -1 = either.
	## all_of: every one of these sockets must be met too (a 2-wide hallway end has two).
	## back: the tile's other open sockets may not face this way (a hallway can't turn back).
	## Returns the new placement index, or -1.
	func _attach(target: Dictionary, candidates: Array[RoomData], open: int, wing: int, rng: RandomNumberGenerator,
			all_of: Array[Dictionary] = [], back: Vector2i = Vector2i.ZERO) -> int:
		var to: Vector2i = (target["cell"] as Vector2i) + (target["dir"] as Vector2i)
		var facing: Vector2i = -(target["dir"] as Vector2i)
		if occupied.has(to):
			return -1
		for room: RoomData in _weighted_order(candidates, rng):
			var shape: RoomShape = RoomShape.of(room, unit)
			var first_turn: int = rng.randi_range(0, 3)
			for turn: int in 4:
				var steps: int = (first_turn + turn) % 4
				var doorways: Array[Dictionary] = shape.rotated_doorways(steps)
				for doorway: Dictionary in doorways:
					if doorway["dir"] != facing:
						continue
					if (open == 1 and not doorway["open_edge"]) or (open == 0 and doorway["open_edge"]):
						continue
					var corner: Vector2i = to - (doorway["cell"] as Vector2i)
					if not _fits(corner, shape.rotated_size(steps)):
						continue
					if not _meets_all(doorways, corner, all_of):
						continue
					if back != Vector2i.ZERO and _faces_back(doorways, corner, all_of, target, back):
						continue
					return _place(room, corner, steps, wing)
		return -1

	func _meets_all(doorways: Array[Dictionary], corner: Vector2i, all_of: Array[Dictionary]) -> bool:
		for needed: Dictionary in all_of:
			var cell: Vector2i = (needed["cell"] as Vector2i) + (needed["dir"] as Vector2i)
			var met: bool = false
			for doorway: Dictionary in doorways:
				met = met or (corner + (doorway["cell"] as Vector2i) == cell and doorway["dir"] == -(needed["dir"] as Vector2i))
			if not met:
				return false
		return true

	## True if one of the tile's other open sides faces `back` (toward where the hallway came from).
	func _faces_back(doorways: Array[Dictionary], corner: Vector2i, all_of: Array[Dictionary], target: Dictionary,
			back: Vector2i) -> bool:
		var entry: Array[Dictionary] = all_of if not all_of.is_empty() else [target] as Array[Dictionary]
		for doorway: Dictionary in doorways:
			if not doorway["open_edge"] or doorway["dir"] != back:
				continue
			var cell: Vector2i = corner + (doorway["cell"] as Vector2i)
			var is_entry: bool = false
			for needed: Dictionary in entry:
				is_entry = is_entry or cell == (needed["cell"] as Vector2i) + (needed["dir"] as Vector2i)
			if not is_entry:
				return true
		return false

	## A placed tile's open sockets nothing joins yet, grouped by the way they face.
	func _exit_groups(index: int) -> Array[Array]:
		var by_dir: Dictionary[Vector2i, Array] = {}
		for socket: Variant in placement_sockets[index]:
			var entry: Dictionary = socket
			if entry["open"] and not _is_joined(entry):
				var dir: Vector2i = entry["dir"]
				if not by_dir.has(dir):
					by_dir[dir] = []
				by_dir[dir].append(entry)
		var groups: Array[Array] = []
		var dirs: Array[Vector2i] = by_dir.keys()
		dirs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		for dir: Vector2i in dirs:
			groups.append(by_dir[dir])
		return groups

	func _open_sockets_of(index: int) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for socket: Variant in placement_sockets[index]:
			if (socket as Dictionary)["open"] and not _is_joined(socket as Dictionary):
				found.append(socket as Dictionary)
		return found

	func _door_sockets_of(index: int) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for socket: Variant in placement_sockets[index]:
			if not (socket as Dictionary)["open"] and not _is_joined(socket as Dictionary):
				found.append(socket as Dictionary)
		return found

	func _room_of(index: int) -> RoomData:
		return ContentRegistry.get_content(layout.placements[index].room_id) as RoomData

	func _size_of(index: int) -> Vector2i:
		return RoomShape.of(_room_of(index), unit).rotated_size(layout.placements[index].rotation_steps)

	## A hallway piece's length along its straight run (its unturned z size).
	func _length_of(index: int) -> int:
		return _room_of(index).size_cells.z

	func _new_wing(hall_name: String) -> int:
		var hall: int = _main_hall_index(hall_name)
		var letter: int = wing_counts.get(hall, 0)
		wing_counts[hall] = letter + 1
		layout.wings.append("%s wing %s" % [hall_name, String.chr(65 + letter % 26)])
		return layout.wings.size() - 1

	func _wing_is_empty(wing: int) -> bool:
		for placement: RoomPlacement in layout.placements:
			if placement.wing == wing:
				return false
		return true

	func _main_hall_name(hall: int) -> String:
		if hall < 0 or hall >= layout.main_halls.size() or layout.main_halls[hall].is_empty():
			return "Main"
		var first: int = layout.main_halls[hall][0]
		for socket: Variant in placement_sockets[first]:
			var entry: Dictionary = socket
			if entry["open"] and _is_joined(entry):
				var other: Dictionary = sockets[_edge_key((entry["cell"] as Vector2i) + (entry["dir"] as Vector2i),
					-(entry["dir"] as Vector2i))]
				if int(other["placement"]) == 1:
					return DIRECTION_NAMES.get(-(entry["dir"] as Vector2i), "Main")
		return "Main %d" % (hall + 1)

	func _main_hall_index(hall_name: String) -> int:
		for hall: int in layout.main_halls.size():
			if _main_hall_name(hall) == hall_name:
				return hall
		return -1

	func _department_first(templates: Array[RoomData]) -> Array[RoomData]:
		var own: Array[RoomData] = []
		for room: RoomData in templates:
			if department != null and room.department_ids.has(department.id):
				own.append(room)
		return own if not own.is_empty() else templates

	func _pick(rooms_list: Array[RoomData], rng: RandomNumberGenerator) -> RoomData:
		var weights := PackedFloat32Array()
		for room: RoomData in rooms_list:
			weights.append(room.weight)
		return rooms_list[maxi(SeededRng.pick_weighted(rng, weights), 0)]

	func _weighted_order(rooms_list: Array[RoomData], rng: RandomNumberGenerator) -> Array[RoomData]:
		var left: Array[RoomData] = rooms_list.duplicate()
		var order: Array[RoomData] = []
		while not left.is_empty():
			var picked: RoomData = _pick(left, rng)
			order.append(picked)
			left.erase(picked)
		return order

	func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
		for index: int in range(items.size() - 1, 0, -1):
			var other: int = rng.randi_range(0, index)
			var swap: Variant = items[index]
			items[index] = items[other]
			items[other] = swap

	func _typed(rooms_list: Array) -> Array[RoomData]:
		var typed: Array[RoomData] = []
		for room: Variant in rooms_list:
			typed.append(room as RoomData)
		return typed

	func _typed_sockets(list: Array) -> Array[Dictionary]:
		var typed: Array[Dictionary] = []
		for socket: Variant in list:
			typed.append(socket as Dictionary)
		return typed
