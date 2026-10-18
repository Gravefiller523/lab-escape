class_name RoomPlacement
extends RefCounted
## One room on a floor: which room, which grid cell its footprint starts at (its smallest x and z
## corner), and how far it is turned (0 to 3, times 90 degrees).

var room_id: StringName = &""
## Grid cell of the footprint's corner with the smallest x and z. y is the storey (always 0 for now).
var cell: Vector3i = Vector3i.ZERO
var rotation_steps: int = 0


static func make(id: StringName, at: Vector3i, steps: int) -> RoomPlacement:
	var placement := RoomPlacement.new()
	placement.room_id = id
	placement.cell = at
	placement.rotation_steps = posmod(steps, 4)
	return placement
