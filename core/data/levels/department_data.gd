class_name DepartmentData
extends ContentData
## A department bundle: everything a themed set of floors needs.
## Example id: "department_zoology". Files live in res://content/departments/.
## Adding a department = add its content files plus one of these. No code changes.

## Number of floors before the boss floor.
@export var floor_count: int = 5
## Rooms this department may use (in addition to rooms with no department set).
@export var room_ids: Array[StringName] = []
## Enemies that spawn here and how often.
@export var enemy_spawns: Array[WeightedIdData] = []
@export var boss_id: StringName = &""
## Default loot table for enemies that don't set their own.
@export var loot_id: StringName = &""
## What vendors on these floors sell.
@export var stock_id: StringName = &""
## Co-op floor tasks that can appear here.
@export var task_ids: Array[StringName] = []
## Lift parts needed to leave each regular floor.
@export var lift_parts_per_floor: int = 3
## How many rooms a regular floor has (the generator picks between these).
@export var rooms_per_floor_min: int = 6
@export var rooms_per_floor_max: int = 10
## Room kinds every regular floor must have, e.g. ["start", "lift"].
@export var required_room_kinds: PackedStringArray = PackedStringArray(["start", "lift"])
## Special room kinds that may appear, with their chance (0 to 1) per floor,
## e.g. {"supply": 0.6, "cafeteria": 0.3, "hr": 0.2, "armory": 0.2}.
@export var optional_room_chances: Dictionary = {}
## Department look: tiles/kit pieces the rooms use.
@export var tile_library: MeshLibrary
@export var music: AudioStream
@export var ambient_color: Color = Color(0.6, 0.6, 0.6)
@export var accent_color: Color = Color(1, 1, 1)
## Lower numbers tend to come earlier in a run (see game_flow).
@export var order_hint: int = 0
## False hides it from runs (e.g. a department still being built).
@export var in_run_rotation: bool = true


func get_type_key() -> StringName:
	return &"department"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append_array(PackedStringArray(["room_ids", "enemy_spawns", "boss_id", "loot_id"]))
	return fields
