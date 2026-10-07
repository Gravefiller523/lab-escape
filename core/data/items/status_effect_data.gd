class_name StatusEffectData
extends ContentData
## A timed effect on a player or enemy, e.g. burning or a speed boost.
## Example id: "status_burning". Files live in res://content/status_effects/.

## Seconds it lasts. 0 or less = until removed.
@export var duration: float = 5.0
## Damage dealt every tick_interval seconds. 0 = none.
@export var tick_damage: float = 0.0
@export var tick_interval: float = 1.0
@export var damage_type: StringName = &""
## Stat changes while active.
@export var stat_modifiers: Array[StatEffectData] = []
## Optional particles or model shown on the target.
@export var visual_scene: PackedScene
## If true, applying it again restarts the timer. If false, it is ignored.
@export var refresh_on_reapply: bool = true


func get_type_key() -> StringName:
	return &"status"
