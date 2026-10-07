class_name LootTableData
extends ContentData
## What drops when something dies or a crate opens.
## Example id: "loot_zoology_small". Files live in res://content/loot_tables/.
## The host rolls loot using the floor seed. Glowing-gem chance comes from GameConfig.

## How many times to pick from entries.
@export var rolls: int = 1
## Weight of "nothing drops" against the entry weights.
@export var nothing_weight: float = 0.0
@export var entries: Array[LootEntryData] = []


func get_type_key() -> StringName:
	return &"loot"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("entries")
	return fields
