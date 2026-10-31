class_name RoomTypeData
extends Resource
## NEW 2026-10-30 (floor generation): one kind of room a department can have, with how often it appears.
## Saved inside a DepartmentData file (its room_types list), like loot entries in a loot table.
## The generator first picks a room type for a room slot, then a tile (RoomData) of that room_kind and size.
## See docs/design/floor-generation-plan.md, section 4.3.

## Unique name inside its department, e.g. "room_type_robot_test_bay".
@export var id: StringName = &""
## Which tiles can be this room: RoomData files with this room_kind, e.g. "robot_test_bay".
@export var room_kind: StringName = &""
## Shown on room signs and the security map, e.g. "Robot Test Bay".
@export var display_name: String = ""
## How often it is picked compared with the department's other room types.
@export var weight: float = 1.0
## Most of this room type on one floor. 0 = no limit.
@export var max_per_floor: int = 0
## Earliest floor of the run it can appear on.
@export var min_floor: int = 1
## Room sizes it can be: "small", "medium", "large". Empty = any size its tiles have.
@export var size_categories: PackedStringArray = PackedStringArray()
## Kinds of lift part that make sense in this room, e.g. ["mechanical", "electrical"] (PropData.part_category).
@export var part_categories: PackedStringArray = PackedStringArray()
