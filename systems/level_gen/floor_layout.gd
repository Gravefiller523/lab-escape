class_name FloorLayout
extends RefCounted
## The plan of one floor: which rooms go where. The host makes it (LevelGenerator) and sends it to
## everyone as a small dictionary; every PC builds the same floor from it (Level.build).

var department_id: StringName = &""
var floor_number: int = 0
var floor_seed: int = 0
var is_boss_floor: bool = false
## In placement order: the start room (or the arena) first.
var placements: Array[RoomPlacement] = []


func to_dict() -> Dictionary:
	var rooms: Array = []
	for placement: RoomPlacement in placements:
		rooms.append([String(placement.room_id), placement.cell.x, placement.cell.y, placement.cell.z,
			placement.rotation_steps])
	return {
		"department_id": String(department_id),
		"floor_number": floor_number,
		"floor_seed": floor_seed,
		"is_boss_floor": is_boss_floor,
		"rooms": rooms,
	}


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
			layout.placements.append(RoomPlacement.make(StringName(str(room[0])), Vector3i(x, y, z), steps))
	return layout
