class_name AchievementData
extends ContentData
## A Steam achievement driven by EventBus events.
## Example id: "achievement_first_escape". Files live in res://content/achievements/.

## The achievement's API name in the Steamworks partner site.
@export var steam_api_name: String = ""
## EventBus signal name that counts towards it, e.g. "boss_defeated".
@export var trigger_event: StringName = &""
## Only count events whose first StringName argument equals this, e.g. "boss_giant_rat".
## Empty = any.
@export var match_id: StringName = &""
## For events whose first argument is a player_id: only count the local player's events.
@export var local_player_only: bool = false
## How many matching events are needed.
@export var required_count: int = 1
## Optional Steam stat that stores progress (for counted achievements).
@export var steam_stat_name: String = ""


func get_type_key() -> StringName:
	return &"achievement"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append_array(PackedStringArray(["steam_api_name", "trigger_event"]))
	return fields
