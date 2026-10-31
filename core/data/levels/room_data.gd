class_name RoomData
extends ContentData
## A pre-built room the level generator can place. Example id: "room_zoo_cages_m".
## Files live in res://content/rooms/. The scene holds the geometry and marker
## nodes (doors, spawn points); see docs/systems/level_gen.md for the rules
## every room must follow (wide doors and ramps for carts, etc.).

@export var scene: PackedScene
## Size in grid cells (x, floors, z). One cell is GameConfig.room_cell_size metres
## (CHANGED 2026-10-30: or Config.floor_gen.grid_unit, 3 m, when grid is "tile_3m").
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

## NEW 2026-10-30 (floor generation): the values of `grid` below.
const GRID_LEGACY: StringName = &"legacy_12m"
const GRID_TILE: StringName = &"tile_3m"

@export_group("Floor generation tiles")
## NEW 2026-10-30: which grid the room is built on. "legacy_12m" = the old grey-box rooms (cells of
## GameConfig.room_cell_size, used by today's LevelGenerator). "tile_3m" = the new tiles (cells of
## Config.floor_gen.grid_unit, 3 m; size_cells then counts those). Old files leave it alone.
@export var grid: StringName = GRID_LEGACY
## NEW 2026-10-30: what the tile is: "room", "main_hall" (2 units wide), "secondary_hall" (1 unit wide)
## or "template" (fixed pieces: the elevator, the welcome center).
@export var tile_role: StringName = &"room"
## NEW 2026-10-30: rooms only: "small", "medium" or "large" (must match the footprint table in
## docs/systems/level_gen.md; a test checks it). Empty for hallways and templates.
@export var size_category: StringName = &"medium"
## NEW 2026-10-30: the damage levels this tile has overlays for (Damage/Light, Damage/Heavy,
## Damage/Destroyed nodes). "pristine" is the tile itself. At least pristine and light.
@export var damage_levels: PackedStringArray = PackedStringArray(["pristine", "light", "heavy", "destroyed"])
## NEW 2026-10-30: kinds of lift part that make sense here, e.g. ["mechanical", "electrical"]
## (PropData.part_category).
@export var part_categories: PackedStringArray = PackedStringArray()
## NEW 2026-10-30: designed as a fighting arena (more enemy spawns).
@export var is_combat_room: bool = false


func get_type_key() -> StringName:
	return &"room"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
