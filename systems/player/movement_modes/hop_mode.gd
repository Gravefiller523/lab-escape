extends WalkMovementMode
## Frog: walks slowly on the ground (hop_walk_speed_multiplier) but leaps far. Jumping happens when you
## let go of jump: hold it to charge (up to hop_charge_seconds), and a fuller charge leaps higher and
## throws you further forward and faster. A quick tap is a normal frog jump (the mutation's jump
## multiplier) with a forward throw. While charging the frog squats and moves very slowly.
## The leap goes the way you move, or the way you face when standing still.

## 0 = not charging. Grows from a tiny amount (just pressed) to 1 (full charge) while jump is held.
var _charge: float = 0.0
var _charging: bool = false
## The charge of the leap happening this frame (used by _jump_speed and _jump).
var _leap_power: float = 0.0


func enter(_body: PlayerCharacter) -> void:
	_charging = false
	_charge = 0.0


func is_charging() -> bool:
	return _charging


## 0 to 1: how full the charge is (tests, and later a HUD bar).
func get_charge() -> float:
	return _charge


func top_speed(body: PlayerCharacter) -> float:
	return maxf(super.top_speed(body), body.tuning.hop_max_speed)


func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void:
	var tuning: PlayerTuning = body.tuning
	var movement: PlayerMovement = body.get_movement()
	var can_leap: bool = body.is_on_floor() and movement.can_jump() and not movement.is_crouching()
	if not can_leap:
		_charging = false
		_charge = 0.0
	elif input.jump_pressed:
		_charging = true
		_charge = 0.0
	var leap := false
	if _charging:
		if input.jump_held or input.jump_pressed:
			_charge = minf(_charge + delta / tuning.hop_charge_seconds, 1.0)
		else:
			# Let go: leap with what was charged.
			leap = true
			_leap_power = _charge
			_charging = false
			_charge = 0.0
	# The walk mode jumps on jump_pressed, so hand it a copy that "presses" jump only on the leap frame.
	var step := PlayerInputState.new()
	step.move = input.move
	step.sprint = input.sprint
	step.crouch = input.crouch
	step.jump_held = input.jump_held
	step.jump_pressed = leap
	super.physics_update(body, step, delta)


func _grip(body: PlayerCharacter, grounded: bool) -> float:
	return 1.0 if grounded else body.tuning.hop_air_control


func _speed(body: PlayerCharacter, _input: PlayerInputState, speed: float, _delta: float) -> float:
	if not body.is_on_floor():
		return speed
	var tuning: PlayerTuning = body.tuning
	return speed * tuning.hop_walk_speed_multiplier * (tuning.hop_charge_move_multiplier if _charging else 1.0)


func _jump_speed(body: PlayerCharacter) -> float:
	var height_scale: float = lerpf(1.0, body.tuning.hop_charge_height_multiplier, _leap_power)
	# Jump height grows with the square of the take-off speed, so scale the speed by the square root.
	return super._jump_speed(body) * sqrt(height_scale)


func _jump(body: PlayerCharacter, input: PlayerInputState, horizontal: Vector3) -> Vector3:
	var tuning: PlayerTuning = body.tuning
	var direction: Vector3 = wish_direction(body, input)
	if direction.length() < 0.1:
		direction = -body.global_basis.z
		direction.y = 0.0
	direction = direction.normalized()
	var throw: float = tuning.hop_forward_speed * lerpf(1.0, tuning.hop_charge_forward_multiplier, _leap_power)
	return (horizontal + direction * throw).limit_length(tuning.hop_max_speed)
