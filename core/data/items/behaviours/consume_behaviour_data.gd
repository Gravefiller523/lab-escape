class_name ConsumeBehaviourData
extends ItemBehaviourData
## Drink or eat the item (e.g. energy drink speed boost).

@export var heal_amount: float = 0.0
## Status effect given to the player, e.g. "status_speed_boost". Empty = none.
@export var status_id: StringName = &""
