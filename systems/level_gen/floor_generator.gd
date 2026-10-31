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
## NEW 2026-10-31 (step 4b), debug (`floorgen origin` / `floorgen damage`): where the incident starts ("near"
## = the room nearest the elevator, "far" = the farthest, "" = normal), and a damage level forced on every tile
## ("" = normal). They stay until changed.
static var debug_origin: StringName = &""
static var debug_damage: StringName = &""


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
	## NEW 2026-10-31 (step 5): this department's own room tiles, by room_kind.
	var department_rooms: Dictionary[StringName, Array] = {}
	## How many rooms of each room_kind are on the floor (for RoomTypeData.max_per_floor).
	var kind_counts: Dictionary[StringName, int] = {}
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
					if room.department_ids.is_empty():
						shared_rooms.append(room)
					else:
						if not department_rooms.has(room.room_kind):
							department_rooms[room.room_kind] = []
						department_rooms[room.room_kind].append(room)

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
		_apply_damage()
		_pick_markers()
		_pick_hazards()
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
		_place_required(queue)
		if not problem.is_empty():
			return
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
					placed = _attach_room(socket, wing, rng) >= 0
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

	## Step 5, first part: the department's required rooms (required_room_kinds, not "lift"/"start"), each at
	## the free main hallway doorway farthest from the elevator where one of its tiles fits. A required room
	## that fits nowhere fails the attempt.
	func _place_required(queue: Array[Dictionary]) -> void:
		if department == null:
			return
		var rng: RandomNumberGenerator = _rng(&"floorgen_required")
		var by_distance: Array[Dictionary] = queue.duplicate()
		by_distance.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _distance(a["socket"]) > _distance(b["socket"]))
		var placed_kinds := PackedStringArray()
		for kind_text: String in department.required_room_kinds:
			var kind := StringName(kind_text)
			if kind == &"lift" or kind == &"start":
				continue
			var tiles: Array[RoomData] = _typed(department_rooms.get(kind, []))
			if tiles.is_empty():
				_log("required room %s has no tiles: skipped" % kind)
				continue
			var placed: bool = false
			for item: Dictionary in by_distance:
				var socket: Dictionary = item["socket"]
				if _is_joined(socket) or occupied.has((socket["cell"] as Vector2i) + (socket["dir"] as Vector2i)):
					continue
				var wing: int = _new_wing(String(item["hall"]))
				if _attach(socket, tiles, 0, wing, rng) >= 0:
					rooms += 1
					kind_counts[kind] = kind_counts.get(kind, 0) + 1
					placed = true
					break
				layout.wings.resize(layout.wings.size() - 1)
				wing_counts[_main_hall_index(String(item["hall"]))] -= 1
			if not placed:
				problem = "required room %s didn't fit at any main hallway doorway" % kind
				return
			placed_kinds.append(kind)
		if not placed_kinds.is_empty():
			_log("required rooms: %s" % ", ".join(placed_kinds))

	## Step 5, the rest: a room for this doorway. A department room (a room type picked by weight, within its
	## max_per_floor and min_floor) or, with the shared room share (or if none fits), a shared room.
	func _attach_room(socket: Dictionary, wing: int, rng: RandomNumberGenerator) -> int:
		var share: float = tuning.shared_room_share
		if department != null and department.shared_room_weight >= 0.0:
			share = department.shared_room_weight
		if department != null and not department.room_types.is_empty() and rng.randf() >= share:
			var room_type: RoomTypeData = _pick_room_type(rng)
			if room_type != null:
				var tiles: Array[RoomData] = _tiles_of_type(room_type)
				var index: int = _attach(socket, tiles, 0, wing, rng) if not tiles.is_empty() else -1
				if index >= 0:
					kind_counts[room_type.room_kind] = kind_counts.get(room_type.room_kind, 0) + 1
					return index
		return _attach(socket, shared_rooms, 0, wing, rng)

	func _pick_room_type(rng: RandomNumberGenerator) -> RoomTypeData:
		var types: Array[RoomTypeData] = []
		var weights := PackedFloat32Array()
		for room_type: RoomTypeData in department.room_types:
			if room_type == null or room_type.min_floor > floor_number:
				continue
			if room_type.max_per_floor > 0 and kind_counts.get(room_type.room_kind, 0) >= room_type.max_per_floor:
				continue
			types.append(room_type)
			weights.append(room_type.weight)
		var picked: int = SeededRng.pick_weighted(rng, weights)
		return types[picked] if picked >= 0 else null

	## The department's tiles of a room type, in the sizes the type allows.
	func _tiles_of_type(room_type: RoomTypeData) -> Array[RoomData]:
		var tiles: Array[RoomData] = []
		for room: RoomData in _typed(department_rooms.get(room_type.room_kind, [])):
			if room_type.size_categories.is_empty() or room_type.size_categories.has(String(room.size_category)):
				tiles.append(room)
		return tiles

	## Grid steps from the elevator to the cell a socket faces.
	func _distance(socket: Dictionary) -> int:
		var cell: Vector2i = (socket["cell"] as Vector2i) + (socket["dir"] as Vector2i)
		return absi(cell.x - 1) + absi(cell.y - 1)

	func _roll_branch(rng: RandomNumberGenerator, hall_allowed: bool, must_room: bool) -> StringName:
		var weights := PackedFloat32Array([tuning.branch_room_weight, tuning.branch_cluster_weight,
			tuning.branch_hall_weight if hall_allowed and not must_room else 0.0,
			0.0 if must_room else tuning.branch_nothing_weight])
		var names: Array[StringName] = [&"room", &"cluster", &"hall", &"nothing"]
		var picked: int = SeededRng.pick_weighted(rng, weights)
		return names[maxi(picked, 0)]

	func _place_cluster(socket: Dictionary, wing: int, rng: RandomNumberGenerator) -> bool:
		var first: int = _attach_room(socket, wing, rng)
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
				added = _attach_room(door, wing, rng)
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
	## Prop spots (a stand-in for step 10): a share of the "prop_spawn" markers is used, more in damaged rooms.
	## A used spot without a fixed prop_id gets loose debris (more likely the worse the damage) or a prop
	## from the department's prop_pool.
	func _pick_markers() -> void:
		var rng: RandomNumberGenerator = _rng(&"floorgen_markers")
		var keys := PackedStringArray()
		var debris: int = 0
		for index: int in layout.placements.size():
			var level: int = layout.damage[index] if index < layout.damage.size() else 0
			var share: float = tuning.prop_spawn_share_damaged if level >= 2 else tuning.prop_spawn_share
			for marker: Dictionary in RoomShape.of(_room_of(index), unit).markers:
				if marker["kind"] != &"prop_spawn" or rng.randf() >= share:
					continue
				var key: String = FloorLayout.marker_key(index, marker["path"])
				keys.append(key)
				if (marker["params"] as Dictionary).has("prop_id"):
					continue
				var debris_chance: float = [0.0, tuning.debris_prop_chance_light, tuning.debris_prop_chance_heavy,
					tuning.debris_prop_chance_destroyed][level]
				if not tuning.debris_prop_ids.is_empty() and rng.randf() < debris_chance:
					layout.marker_params[key] = {"prop_id": String(tuning.debris_prop_ids[rng.randi_range(0, tuning.debris_prop_ids.size() - 1)])}
					debris += 1
				elif department != null and not department.prop_pool.is_empty():
					var weights := PackedFloat32Array()
					for entry: WeightedIdData in department.prop_pool:
						weights.append(entry.weight if entry != null else 0.0)
					var picked: int = SeededRng.pick_weighted(rng, weights)
					if picked >= 0:
						layout.marker_params[key] = {"prop_id": String(department.prop_pool[picked].content_id)}
		layout.active_markers[&"prop_spawn"] = keys
		if debris > 0:
			_log("props: %d spots used, %d with loose debris" % [keys.size(), debris])

	## NEW 2026-10-31 (step 6 of the plan, built in step 4b): the incident and the damage.
	## The department's incident (by weight) starts in a room it fits (origin_room_kinds), at least
	## incident_min_distance_share of the farthest walking distance from the elevator. Each tile's damage
	## score is intensity (grows with the floor) x how close it is to the origin (fading over
	## damage_falloff_metres of walking) + a little noise; thresholds turn it into a level. The elevator and
	## the welcome center (with its security room) never go above start_area_max_damage. Some destroyed
	## secondary hallway pieces collapse, but only where every other tile can still be reached.
	func _apply_damage() -> void:
		var rng: RandomNumberGenerator = _rng(&"floorgen_damage")
		var count: int = layout.placements.size()
		layout.damage.resize(count)
		layout.damage.fill(0)
		var links: Dictionary[int, Array] = _links()
		var from_start: PackedFloat32Array = _path_distances(links, 0)
		var farthest: float = 0.0
		for distance: float in from_start:
			if distance < INF:
				farthest = maxf(farthest, distance)
		var incident: IncidentData = _pick_incident(rng)
		layout.incident_id = incident.id if incident != null else &"incident_generic"
		layout.origin = _pick_origin(incident, from_start, farthest, rng)
		if layout.origin < 0:
			_log("incident: no room to start in, no damage")
			return
		var intensity: float = FloorGenTuning.grown(tuning.damage_intensity_base, tuning.damage_intensity_per_floor,
			tuning.damage_intensity_cap, floor_number)
		var from_origin: PackedFloat32Array = _path_distances(links, layout.origin)
		var start_cap: int = maxi(TileStandards.DAMAGE_LEVELS.find(tuning.start_area_max_damage), 0)
		var forced: int = TileStandards.DAMAGE_LEVELS.find(FloorGenerator.debug_damage)
		var counts := PackedInt32Array([0, 0, 0, 0])
		for index: int in count:
			var closeness: float = maxf(0.0, 1.0 - from_origin[index] / maxf(tuning.damage_falloff_metres, 0.1))
			var score: float = intensity * closeness + rng.randf_range(-tuning.damage_noise, tuning.damage_noise)
			var level: int = 0
			if score >= tuning.damage_destroyed_threshold:
				level = 3
			elif score >= tuning.damage_heavy_threshold:
				level = 2
			elif score >= tuning.damage_light_threshold:
				level = 1
			if forced >= 0:
				level = forced
			if index <= 1:
				level = mini(level, start_cap)
			level = mini(level, _highest_level(_room_of(index)))
			layout.damage[index] = level
			counts[level] += 1
		_collapse(links, rng)
		_log("incident %s in %s (#%d, %.0f m from the elevator): intensity %.2f; %d light, %d heavy, %d destroyed; %d collapsed" % [
			layout.incident_id, layout.placements[layout.origin].room_id, layout.origin, from_start[layout.origin],
			intensity, counts[1], counts[2], counts[3], layout.collapsed.size()])

	func _pick_incident(rng: RandomNumberGenerator) -> IncidentData:
		if department == null or department.incidents.is_empty():
			return null
		var weights := PackedFloat32Array()
		for incident: IncidentData in department.incidents:
			weights.append(incident.weight if incident != null else 0.0)
		var picked: int = SeededRng.pick_weighted(rng, weights)
		return department.incidents[picked] if picked >= 0 else null

	## The room the incident starts in: one of its origin_room_kinds far enough away, else any room far enough
	## away, else the farthest room. Debug "near"/"far" pick the nearest/farthest room.
	func _pick_origin(incident: IncidentData, from_start: PackedFloat32Array, farthest: float,
			rng: RandomNumberGenerator) -> int:
		var rooms_list: Array[int] = []
		for index: int in layout.placements.size():
			if _room_of(index).tile_role == TileStandards.ROLE_ROOM and from_start[index] < INF:
				rooms_list.append(index)
		if rooms_list.is_empty():
			return -1
		rooms_list.sort_custom(func(a: int, b: int) -> bool: return from_start[a] < from_start[b])
		if FloorGenerator.debug_origin == &"near":
			return rooms_list[0]
		if FloorGenerator.debug_origin == &"far":
			return rooms_list[-1]
		var far_enough: Array[int] = []
		var fitting: Array[int] = []
		for index: int in rooms_list:
			if from_start[index] < farthest * tuning.incident_min_distance_share:
				continue
			far_enough.append(index)
			if incident != null and incident.origin_room_kinds.has(String(_room_of(index).room_kind)):
				fitting.append(index)
		var pool: Array[int] = fitting if not fitting.is_empty() else far_enough
		if pool.is_empty():
			return rooms_list[-1]
		return pool[rng.randi_range(0, pool.size() - 1)]

	## The worst damage level a tile has overlays for.
	func _highest_level(room: RoomData) -> int:
		var highest: int = 0
		for level: String in room.damage_levels:
			highest = maxi(highest, TileStandards.DAMAGE_LEVELS.find(StringName(level)))
		return highest

	## Destroyed secondary hallway pieces may collapse (collapse_chance), only if every other tile can still be
	## reached from the elevator without them. Main hallways never collapse (Q31).
	func _collapse(links: Dictionary[int, Array], rng: RandomNumberGenerator) -> void:
		for index: int in layout.placements.size():
			if layout.damage[index] < 3 or _room_of(index).tile_role != TileStandards.ROLE_SECONDARY_HALL:
				continue
			if rng.randf() >= tuning.collapse_chance:
				continue
			var blocked := PackedInt32Array(layout.collapsed)
			blocked.append(index)
			if _all_reachable(links, blocked):
				layout.collapsed = blocked

	## Hazards (V12): a rolled number of the "hazard" markers in rooms at least hazard_min_damage are switched
	## on, each with a kind the marker allows and the department (or the incident) has.
	func _pick_hazards() -> void:
		var rng: RandomNumberGenerator = _rng(&"floorgen_hazards")
		var min_level: int = maxi(TileStandards.DAMAGE_LEVELS.find(tuning.hazard_min_damage), 1)
		var candidates: Array[Dictionary] = []
		for index: int in layout.placements.size():
			if index >= layout.damage.size() or layout.damage[index] < min_level or layout.collapsed.has(index):
				continue
			for marker: Dictionary in RoomShape.of(_room_of(index), unit).markers:
				if marker["kind"] != &"hazard":
					continue
				var params: Dictionary = marker["params"]
				var needed: int = TileStandards.DAMAGE_LEVELS.find(StringName(str(params.get("min_damage", "pristine"))))
				if layout.damage[index] >= needed:
					candidates.append({"key": FloorLayout.marker_key(index, marker["path"]), "params": params})
		var lo: int = int(FloorGenTuning.grown(float(tuning.hazards_min), tuning.hazards_per_floor, float(tuning.hazards_cap), floor_number))
		var hi: int = int(FloorGenTuning.grown(float(tuning.hazards_max), tuning.hazards_per_floor, float(tuning.hazards_cap), floor_number))
		var wanted: int = mini(rng.randi_range(lo, maxi(hi, lo)), candidates.size())
		_shuffle(candidates, rng)
		var allowed := PackedStringArray()
		if department != null:
			allowed.append_array(department.hazard_kinds)
		if department != null:
			for incident: IncidentData in department.incidents:
				if incident != null and incident.id == layout.incident_id:
					allowed.append_array(incident.hazard_kinds)
		var keys := PackedStringArray()
		for candidate: Dictionary in candidates.slice(0, wanted):
			var kinds: Array = (candidate["params"] as Dictionary).get("hazard_kinds", ["sparks"])
			var fitting: Array = kinds.filter(func(kind: Variant) -> bool: return allowed.is_empty() or allowed.has(str(kind)))
			var choice: Array = fitting if not fitting.is_empty() else kinds
			var key: String = candidate["key"]
			keys.append(key)
			layout.marker_params[key] = {"hazard_kind": str(choice[rng.randi_range(0, choice.size() - 1)])}
		layout.active_markers[&"hazard"] = keys
		if not keys.is_empty():
			_log("hazards: %d of %d places (%d to %d wanted)" % [keys.size(), candidates.size(), lo, hi])

	## Which tiles are joined to which: placement -> [[other placement, metres between their centres]].
	func _links() -> Dictionary[int, Array]:
		var links: Dictionary[int, Array] = {}
		for key: String in sockets:
			var socket: Dictionary = sockets[key]
			if not _is_joined(socket):
				continue
			var other: Dictionary = sockets[_edge_key((socket["cell"] as Vector2i) + (socket["dir"] as Vector2i),
				-(socket["dir"] as Vector2i))]
			var a: int = socket["placement"]
			var b: int = other["placement"]
			if a == b:
				continue
			if not links.has(a):
				links[a] = []
			links[a].append([b, _centre(a).distance_to(_centre(b))])
		return links

	func _centre(index: int) -> Vector2:
		var placement: RoomPlacement = layout.placements[index]
		return (Vector2(placement.cell.x, placement.cell.z) + Vector2(_size_of(index)) / 2.0) * unit

	## Walking distance (metres, through tile centres) from one tile to every tile (INF = can't get there).
	func _path_distances(links: Dictionary[int, Array], from: int, blocked: PackedInt32Array = PackedInt32Array()) -> PackedFloat32Array:
		var count: int = layout.placements.size()
		var distances := PackedFloat32Array()
		distances.resize(count)
		distances.fill(INF)
		var done: Dictionary[int, bool] = {}
		distances[from] = 0.0
		while true:
			var best: int = -1
			for index: int in count:
				if not done.has(index) and distances[index] < INF and (best < 0 or distances[index] < distances[best]):
					best = index
			if best < 0:
				break
			done[best] = true
			for link: Variant in links.get(best, []):
				var pair: Array = link
				var next: int = pair[0]
				var length: float = pair[1]
				if blocked.has(next):
					continue
				if distances[best] + length < distances[next]:
					distances[next] = distances[best] + length
		return distances

	func _all_reachable(links: Dictionary[int, Array], blocked: PackedInt32Array) -> bool:
		var distances: PackedFloat32Array = _path_distances(links, 0, blocked)
		for index: int in distances.size():
			if not blocked.has(index) and distances[index] == INF:
				return false
		return true

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
