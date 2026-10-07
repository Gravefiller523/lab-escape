class_name BossData
extends ContentData
## A department boss. Example id: "boss_giant_rat". Files live in res://content/bosses/.

@export var scene: PackedScene
@export var max_health: float = 1000.0
## Phases in order. Phase 0 starts the fight.
@export var phases: Array[BossPhaseData] = []
## The arena room this boss fights in.
@export var arena_room_id: StringName = &""
## Loot table rolled when the boss dies.
@export var loot_id: StringName = &""
@export var music: AudioStream


func get_type_key() -> StringName:
	return &"boss"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append_array(PackedStringArray(["scene", "phases", "arena_room_id"]))
	return fields
