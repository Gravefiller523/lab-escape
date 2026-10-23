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
## @deprecated use lift_breaks_min / lift_breaks_max instead (2026-10-19: the lift has a slot per part type).
@export var lift_parts_per_floor: int = 3
## @deprecated the parts are the lift-part props (PropData.lift_slot); not used since 2026-10-19.
@export var lift_part_prop_id: StringName = &""
## How many of the cargo lift's slots break on each regular floor (picked at random with the run's seed).
@export var lift_breaks_min: int = 1
@export var lift_breaks_max: int = 3
## Lift parts (PropData ids) that can break here. Empty = every lift part.
@export var lift_part_ids: Array[StringName] = []
## NEW 2026-10-23 (upgrades, Zachary): what this department's floors hide: &"mutation" (DNA vials: Zoology,
## Botany) or &"cybernetic" (data drives: Robotics). Mutations and cybernetics with department_ids only drop
## in those departments.
@export var upgrade_type: StringName = &"mutation"
## Chance of each try to spawn a vial or drive on a floor (Config.game.upgrade_carrier_tries tries). -1 =
## Config.game.upgrade_carrier_chance.
@export var upgrade_carrier_chance: float = -1.0
## How many rooms a regular floor has (the generator picks between these).
@export var rooms_per_floor_min: int = 6
@export var rooms_per_floor_max: int = 10
## Room kinds every regular floor must have. Every floor starts in its "lift" room (players arrive
## in the elevator), so "lift" is always there; others listed here go as far from it as possible.
@export var required_room_kinds: PackedStringArray = PackedStringArray(["lift"])
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
