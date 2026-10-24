class_name WalkMovementMode
extends MovementMode
## The default movement mode: walk, sprint, jump, crouch, fall.
## Loaded by name ("walk") from PlayerMovement.load_mode(). The other modes (hover, hop, slide, wall_climb)
## extend this one and change only the steps they need: _speed, _grip, _jump_speed, _jump, _fall, _after_move.


func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void:
	var tuning: PlayerTuning = body.tuning
	var movement: PlayerMovement = body.get_movement()

	_update_crouch(body, input.crouch, delta)

	var speed: float = tuning.walk_speed
	if movement.is_crouching():
		speed = tuning.crouch_speed
	elif input.sprint and input.move.y > 0.0:
		speed = tuning.sprint_speed
	speed = _speed(body, input, speed * movement.get_speed_multiplier(), delta)

	var target: Vector3 = wish_direction(body, input) * speed

	var grounded: bool = body.is_on_floor()
	var acceleration: float = (tuning.ground_acceleration if grounded else tuning.air_acceleration) * _grip(body, grounded)
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	horizontal = horizontal.lerp(target, clampf(acceleration * delta, 0.0, 1.0))

	var vertical: float = body.velocity.y
	if grounded:
		vertical = minf(vertical, 0.0)
		if input.jump_pressed and movement.can_jump() and not movement.is_crouching():
			vertical = _jump_speed(body)
			horizontal = _jump(body, input, horizontal)
	else:
		vertical = _fall(body, input, vertical, delta)

	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()
	movement.set_grounded(body.is_on_floor())
	_after_move(body, input, delta)


## The keys' direction turned into a flat direction in the world, relative to where the body faces (length 0 to 1).
static func wish_direction(body: PlayerCharacter, input: PlayerInputState) -> Vector3:
	var wish: Vector3 = body.global_transform.basis * Vector3(input.move.x, 0.0, -input.move.y)
	wish.y = 0.0
	return wish.normalized() if wish.length() > 1.0 else wish


## Upward speed for a normal jump with this body's gravity and jump multiplier: v = sqrt(2 g h).
static func jump_speed(body: PlayerCharacter) -> float:
	var movement: PlayerMovement = body.get_movement()
	return sqrt(2.0 * gravity_of(body) * body.tuning.jump_height * movement.get_jump_multiplier())


static func gravity_of(body: PlayerCharacter) -> float:
	return body.tuning.gravity * body.get_movement().get_gravity_multiplier()


## The speed to aim for this frame (slide builds up speed the longer you move).
func _speed(_body: PlayerCharacter, _input: PlayerInputState, speed: float, _delta: float) -> float:
	return speed


## How much of the normal acceleration applies (1 = normal; lower = slippery).
func _grip(_body: PlayerCharacter, _grounded: bool) -> float:
	return 1.0


## Upward speed when jumping (hop makes small automatic hops lower).
func _jump_speed(body: PlayerCharacter) -> float:
	return jump_speed(body)


## Just jumped: change the horizontal speed if the mode wants to (hop throws you forward).
func _jump(_body: PlayerCharacter, _input: PlayerInputState, horizontal: Vector3) -> Vector3:
	return horizontal


## In the air: the new vertical speed after this frame's gravity.
func _fall(body: PlayerCharacter, _input: PlayerInputState, vertical: float, delta: float) -> float:
	return maxf(vertical - gravity_of(body) * delta, -body.tuning.max_fall_speed)


## After moving (wall climbing looks at what it touched).
func _after_move(_body: PlayerCharacter, _input: PlayerInputState, _delta: float) -> void:
	pass


func _update_crouch(body: PlayerCharacter, wants_crouch: bool, delta: float) -> void:
	var movement: PlayerMovement = body.get_movement()
	var target: float = 1.0 if wants_crouch else 0.0
	# Only stand up if there is room above the head.
	if target < movement.crouch_amount and not body.has_headroom_to_stand():
		target = movement.crouch_amount
	movement.crouch_amount = move_toward(movement.crouch_amount, target,
		body.tuning.crouch_transition_speed * delta)
	body.apply_height()
