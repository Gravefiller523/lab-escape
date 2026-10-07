class_name MovementEffectData
extends UpgradeEffectData
## Changes how the player moves. Multipliers stack by multiplying.

@export var speed_multiplier: float = 1.0
@export var jump_multiplier: float = 1.0
@export var gravity_multiplier: float = 1.0
## Body height. Giraffe uses more than 1 and must crouch through doors.
@export var height_multiplier: float = 1.0
@export var can_jump: bool = true
## Name of a movement mode from the player system's mode library,
## e.g. "wall_climb", "slide", "hop". Empty = normal walking.
@export var movement_mode: StringName = &""
## When two upgrades set a movement mode, the higher priority wins.
@export var mode_priority: int = 0
