class_name RoomData
extends ContentData
## A pre-built room the level generator can place. Example id: "room_zoo_cages_m".
## Files live in res://content/rooms/. The scene holds the geometry and marker
## nodes (doors, spawn points); see docs/systems/level_gen.md for the rules
## every room must follow (wide doors and ramps for carts, etc.).

@export var scene: PackedScene
## Size in grid cells (x, floors, z). One cell is GameConfig.room_cell_size metres.
@export var size_cells: Vector3i = Vector3i(1, 1, 1)
## What sort of room it is. Common values: "normal", "start", "lift",
## "corridor", "hr", "armory", "cafeteria", "supply", "boss_arena".
## New kinds need no code unless the generator must treat them specially.
@export var room_kind: StringName = &"normal"
## Departments that can use it. Empty = any department.
@export var department_ids: Array[StringName] = []
## How likely it is to be picked compared with others of the same kind.
@export var weight: float = 1.0
## Earliest floor inside a department (1 to 5).
@export var min_floor: int = 1
## Most copies on one floor. 0 = no limit.
@export var max_per_floor: int = 0


func get_type_key() -> StringName:
	return &"room"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
