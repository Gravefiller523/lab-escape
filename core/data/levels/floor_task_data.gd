class_name FloorTaskData
extends ContentData
## A co-op floor task, e.g. the crane game or the hamster wheel.
## Example id: "task_hamster_wheel". Files live in res://content/floor_tasks/.

@export var scene: PackedScene
## Fewest players needed to finish it.
@export var min_players: int = 1
## Players who can take part at once. 0 = no limit.
@export var max_participants: int = 0
## What finishing it gives: "loot" (NEW 2026-11-13: rolls reward_loot_id), and later "lift_part", "fuse", "keycard",
## "door_open".
@export var reward: StringName = &"lift_part"
@export var weight: float = 1.0
## Room kind it must be placed in. Empty = any normal room big enough.
@export var room_kind: StringName = &""
## NEW 2026-11-13 (roadmap WP15): how much work finishes it: seconds of one player doing the task (two players take
## half as long).
@export var work_seconds: float = 20.0
## NEW 2026-11-13: the loot table rolled at the task when it is finished (reward "loot").
@export var reward_loot_id: StringName = &""
## NEW 2026-11-13: numbers only this task's scene uses (the hamster wheel's belt_speed). Read with params.get().
@export var params: Dictionary = {}


func get_type_key() -> StringName:
	return &"task"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
