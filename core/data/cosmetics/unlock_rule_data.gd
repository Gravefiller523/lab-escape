class_name UnlockRuleData
extends Resource
## How a cosmetic is unlocked. Saved inside the cosmetic's .tres file.

## "achievement", "boss_defeated", "runs_completed", "floors_reached".
@export var kind: StringName = &"runs_completed"
## For kind "achievement".
@export var achievement_id: StringName = &""
## For kind "boss_defeated".
@export var boss_id: StringName = &""
## For counted kinds: how many.
@export var count: int = 1
