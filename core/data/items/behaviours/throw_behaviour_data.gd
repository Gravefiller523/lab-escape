class_name ThrowBehaviourData
extends ItemBehaviourData
## Throw the item. It leaves the inventory and becomes a physics object.

@export var throw_force: float = 12.0
@export var damage: float = 5.0
@export var damage_type: StringName = &"blunt"
## Status effect applied on impact, e.g. "status_burning" for hot coffee. Empty = none.
@export var status_id: StringName = &""
## If true the item breaks on impact (coffee pot) instead of landing intact.
@export var breaks_on_impact: bool = false
