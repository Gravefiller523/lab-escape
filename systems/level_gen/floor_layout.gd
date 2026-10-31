class_name FloorLayout
extends RefCounted
## The plan of one floor: which rooms go where. The host makes it (LevelGenerator, or NEW 2026-10-31 the
## FloorGenerator for 3 m tile floors) and sends it to everyone as a small dictionary; every PC builds the
## same floor from it (Level.build).

var department_id: StringName = &""
var floor_number: int = 0
var floor_seed: int = 0
var is_boss_floor: bool = false
## In placement order: the start room (or the arena) first.
var placements: Array[RoomPlacement] = []

# NEW 2026-10-31 (floor generation step 3) ------------------------------------------------------------
## Which grid the rooms are on: RoomData.GRID_LEGACY (12 m grey-box rooms) or RoomData.GRID_TILE (3 m tiles).
var grid: StringName = RoomData.GRID_LEGACY
## The generator's attempt that made this floor (0 = the first), and whether it is the safe fallback floor.
var attempt: int = 0
var is_fallback: bool = false
## Wing names, e.g. "West wing A". RoomPlacement.wing indexes this.
var wings: PackedStringArray = PackedStringArray()
## Placement indexes of each main hallway's pieces, in order from the welcome center.
var main_halls: Array[PackedInt32Array] = []
## Extra connections made to close loops: [placement a, placement b] pairs (step 4 of the plan).
var loops: Array[Vector2i] = []
## Markers the generator switched on, by kind: "placement/path inside the room" keys. A kind that isn't
## listed here has every marker on (Level.get_markers).
var active_markers: Dictionary[StringName, PackedStringArray] = {}
# NEW 2026-10-31 (floor generation step 4b: incident and damage) ----------------------------------------
## Each placement's damage level: 0 pristine, 1 light, 2 heavy, 3 destroyed (TileStandards.DAMAGE_LEVELS).
var damage: PackedByteArray = PackedByteArray()
## The floor's incident (IncidentData.id, or &"incident_generic") and the placement it started in (-1 = none).
var incident_id: StringName = &""
var origin: int = -1
## Placements of hallway pieces that collapsed (impassable, only where a loop gives a way round).
var collapsed: PackedInt32Array = PackedInt32Array()
## Extra settings for markers, by marker key: e.g. {"prop_id": "prop_debris_chunk"} or {"hazard_kind": "fire"}.
## Level.build copies them into the markers' params.
var marker_params: Dictionary[String, Dictionary] = {}
## The generation log (host only: not sent to other PCs).
var log_lines: PackedStringArray = PackedStringArray()
## Numbers about how the floor grew, for tests and the log (host only, not sent): "rooms", "max_depth".
var stats: Dictionary[String, int] = {}


func to_dict() -> Dictionary:
	var rooms: Array = []
	for placement: RoomPlacement in placements:
		var entry: Array = [String(placement.room_id), placement.cell.x, placement.cell.y, placement.cell.z,
			placement.rotation_steps]
		if placement.wing >= 0:
			entry.append(placement.wing)
		rooms.append(entry)
	var data: Dictionary = {
		"department_id": String(department_id),
		"floor_number": floor_number,
		"floor_seed": floor_seed,
		"is_boss_floor": is_boss_floor,
		"rooms": rooms,
	}
	if grid != RoomData.GRID_LEGACY:
		var halls: Array = []
		for hall: PackedInt32Array in main_halls:
			halls.append(hall)
		var loop_pairs: Array = []
		for pair: Vector2i in loops:
			loop_pairs.append([pair.x, pair.y])
		var markers: Dictionary = {}
		for kind: StringName in active_markers:
			markers[String(kind)] = active_markers[kind]
		data["grid"] = String(grid)
		data["attempt"] = attempt
		data["is_fallback"] = is_fallback
		data["wings"] = wings
		data["main_halls"] = halls
		data["loops"] = loop_pairs
		data["active_markers"] = markers
		data["damage"] = damage
		data["incident_id"] = String(incident_id)
		data["origin"] = origin
		data["collapsed"] = collapsed
		var params: Dictionary = {}
		for key: String in marker_params:
			params[key] = marker_params[key]
		data["marker_params"] = params
	return data


static func from_dict(data: Dictionary) -> FloorLayout:
	var layout := FloorLayout.new()
	layout.department_id = StringName(str(data.get("department_id", "")))
	layout.floor_number = data.get("floor_number", 0)
	layout.floor_seed = data.get("floor_seed", 0)
	layout.is_boss_floor = data.get("is_boss_floor", false)
	for entry: Variant in data.get("rooms", []):
		var room: Array = entry
		if room.size() >= 5:
			var x: int = room[1]
			var y: int = room[2]
			var z: int = room[3]
			var steps: int = room[4]
			var wing: int = room[5] if room.size() >= 6 else -1
			layout.placements.append(RoomPlacement.make(StringName(str(room[0])), Vector3i(x, y, z), steps, wing))
	layout.grid = StringName(str(data.get("grid", RoomData.GRID_LEGACY)))
	layout.attempt = data.get("attempt", 0)
	layout.is_fallback = data.get("is_fallback", false)
	layout.wings = PackedStringArray(data.get("wings", PackedStringArray()))
	for hall: Variant in data.get("main_halls", []):
		layout.main_halls.append(PackedInt32Array(hall))
	for pair: Variant in data.get("loops", []):
		var ends: Array = pair
		if ends.size() >= 2:
			var a: int = ends[0]
			var b: int = ends[1]
			layout.loops.append(Vector2i(a, b))
	var markers: Dictionary = data.get("active_markers", {})
	for kind: Variant in markers:
		layout.active_markers[StringName(str(kind))] = PackedStringArray(markers[kind])
	layout.damage = PackedByteArray(data.get("damage", PackedByteArray()))
	layout.incident_id = StringName(str(data.get("incident_id", "")))
	layout.origin = data.get("origin", -1)
	layout.collapsed = PackedInt32Array(data.get("collapsed", PackedInt32Array()))
	var params: Dictionary = data.get("marker_params", {})
	for key: Variant in params:
		layout.marker_params[str(key)] = params[key] as Dictionary
	return layout


## NEW 2026-10-31: the size of one grid cell (metres) for this floor.
func cell_size() -> float:
	return Config.floor_gen.grid_unit if grid == RoomData.GRID_TILE else Config.game.room_cell_size


## NEW 2026-10-31: the key active_markers uses for a marker (placement index and its path in the room).
static func marker_key(placement_index: int, path_in_room: String) -> String:
	return "%d/%s" % [placement_index, path_in_room]


## NEW 2026-10-31: a placement's damage level name ("pristine" if the floor has no damage).
func damage_level(index: int) -> StringName:
	if index < 0 or index >= damage.size():
		return &"pristine"
	return TileStandards.DAMAGE_LEVELS[mini(damage[index], TileStandards.DAMAGE_LEVELS.size() - 1)]
