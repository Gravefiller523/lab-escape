extends WalkMovementMode
## Frog: moves in hops. Walking on the ground makes small automatic hops (hop_auto_hops), and a real jump
## (higher thanks to the mutation's jump multiplier) also throws you forward in the direction you move.

var _small_hop: bool = false


func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void:
	_small_hop = false
	var moving: bool = input.move.length() > 0.1
	if body.tuning.hop_auto_hops and moving and not input.jump_pressed and body.is_on_floor() \
			and not body.get_movement().is_crouching():
		# A small hop instead of a step: same as pressing jump, but lower and without the forward throw.
		var hop := PlayerInputState.new()
		hop.move = input.move
		hop.sprint = input.sprint
		hop.crouch = input.crouch
		hop.jump_held = input.jump_held
		hop.jump_pressed = true
		_small_hop = true
		super.physics_update(body, hop, delta)
		return
	super.physics_update(body, input, delta)


func _jump_speed(body: PlayerCharacter) -> float:
	if _small_hop:
		return sqrt(2.0 * gravity_of(body) * body.tuning.hop_small_height)
	return super._jump_speed(body)


func _jump(body: PlayerCharacter, input: PlayerInputState, horizontal: Vector3) -> Vector3:
	if _small_hop:
		return horizontal
	var thrown: Vector3 = horizontal + wish_direction(body, input) * body.tuning.hop_forward_speed
	return thrown.limit_length(maxf(body.tuning.hop_max_speed, horizontal.length()))
