class_name StatEffectData
extends UpgradeEffectData
## Changes one number on the player. Also used inside status effects.
## Known stat names are listed in docs/systems/upgrades.md,
## e.g. "max_health", "melee_damage", "carry_strength", "throw_strength".

@export var stat: StringName = &""
## Added first.
@export var add: float = 0.0
## Then multiplied.
@export var multiply: float = 1.0
