class_name PlayerInputState
extends RefCounted
## One physics frame of the local player's controls, gathered by PlayerCharacter and handed to the
## active movement mode. Tests fill one in by hand instead of pressing keys.

## x = right, y = forward, each -1 to 1.
var move: Vector2 = Vector2.ZERO
## True only on the frame the jump key went down.
var jump_pressed: bool = false
var sprint: bool = false
var crouch: bool = false
