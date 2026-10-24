extends WalkMovementMode
## Fly: walking with floaty jumps (gravity and jump come from the mutation's numbers), plus short glides.
## Hold jump while falling to glide: you fall slowly and steer well, for up to hover_seconds. Landing refills it.

var _glide_left: float = 0.0
var _gliding: bool = false


func enter(body: PlayerCharacter) -> void:
	_glide_left = body.tuning.hover_seconds
	_gliding = false


func is_gliding() -> bool:
	return _gliding


func _grip(body: PlayerCharacter, grounded: bool) -> float:
	return body.tuning.hover_air_control if _gliding and not grounded else 1.0


func _fall(body: PlayerCharacter, input: PlayerInputState, vertical: float, delta: float) -> float:
	var falling: float = super._fall(body, input, vertical, delta)
	_gliding = input.jump_held and _glide_left > 0.0 and falling < 0.0
	if not _gliding:
		return falling
	_glide_left -= delta
	return maxf(falling, -body.tuning.hover_fall_speed)


func _after_move(body: PlayerCharacter, _input: PlayerInputState, _delta: float) -> void:
	if body.is_on_floor():
		_glide_left = body.tuning.hover_seconds
		_gliding = false
