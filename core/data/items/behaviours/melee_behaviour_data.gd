class_name MeleeBehaviourData
extends ItemBehaviourData
## Swing and hit what is in front of the player.

@export var damage: float = 10.0
## Damage type name, e.g. "blunt", "sharp", "fire". See docs/systems/damage.md.
@export var damage_type: StringName = &"blunt"
## How far the swing reaches, in metres.
@export var reach: float = 2.0
@export var knockback: float = 3.0
## Status effect applied on hit, e.g. "status_burning". Empty = none.
@export var status_id: StringName = &""
