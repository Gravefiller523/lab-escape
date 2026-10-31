class_name RoomPlacement
extends RefCounted
## One room on a floor: which room, which grid cell its footprint starts at (its smallest x and z
## corner), and how far it is turned (0 to 3, times 90 degrees).

var room_id: StringName = &""
## Grid cell of the footprint's corner with the smallest x and z. y is the storey (always 0 for now).
var cell: Vector3i = Vector3i.ZERO
var rotation_steps: int = 0
## NEW 2026-10-31 (floor generation step 3): which wing it belongs to (an index into FloorLayout.wings),
## -1 = none (the elevator, the welcome center, the main hallways).
var wing: int = -1


static func make(id: StringName, at: Vector3i, steps: int, wing_index: int = -1) -> RoomPlacement:
	var placement := RoomPlacement.new()
	placement.room_id = id
	placement.cell = at
	placement.rotation_steps = posmod(steps, 4)
	placement.wing = wing_index
	return placement
