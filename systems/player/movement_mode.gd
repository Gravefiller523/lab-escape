class_name MovementMode
extends RefCounted
## Base class for movement building blocks (walk, wall climb, slide, hop, hover).
## A mode called "wall_climb" lives in systems/player/movement_modes/wall_climb_mode.gd, so adding a
## mode is one new file. Modes only run on the PC that owns the body.


func enter(_body: PlayerCharacter) -> void:
	pass


func exit(_body: PlayerCharacter) -> void:
	pass


func physics_update(_body: PlayerCharacter, _input: PlayerInputState, _delta: float) -> void:
	pass


## Fastest this mode can move sideways (m/s). The host's speed check uses it, so a mode that goes faster than
## sprinting (slug slides, frog hops) isn't pulled back. Runs on every PC (no physics_update needed).
func top_speed(body: PlayerCharacter) -> float:
	return body.tuning.sprint_speed * body.get_movement().get_speed_multiplier()
