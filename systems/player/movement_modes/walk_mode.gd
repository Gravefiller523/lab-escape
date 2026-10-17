extends MovementMode
## The default movement mode: walk, sprint, jump, crouch, fall.
## Loaded by name ("walk") from PlayerMovement.load_mode().


func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void:
	var tuning: PlayerTuning = body.tuning
	var movement: PlayerMovement = body.get_movement()

	_update_crouch(body, input.crouch, delta)

	var speed: float = tuning.walk_speed
	if movement.is_crouching():
		speed = tuning.crouch_speed
	elif input.sprint and input.move.y > 0.0:
		speed = tuning.sprint_speed
	speed *= movement.get_speed_multiplier()

	# Turn the stick/keys direction into a direction in the world, relative to where we face.
	var wish: Vector3 = body.global_transform.basis * Vector3(input.move.x, 0.0, -input.move.y)
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target: Vector3 = wish * speed

	var grounded: bool = body.is_on_floor()
	var acceleration: float = tuning.ground_acceleration if grounded else tuning.air_acceleration
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	horizontal = horizontal.lerp(target, clampf(acceleration * delta, 0.0, 1.0))

	var vertical: float = body.velocity.y
	var gravity: float = tuning.gravity * movement.get_gravity_multiplier()
	if grounded:
		vertical = minf(vertical, 0.0)
		if input.jump_pressed and movement.can_jump() and not movement.is_crouching():
			# Speed needed to reach jump_height under this gravity: v = sqrt(2 g h).
			vertical = sqrt(2.0 * gravity * tuning.jump_height * movement.get_jump_multiplier())
	else:
		vertical = maxf(vertical - gravity * delta, -tuning.max_fall_speed)

	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()
	movement.set_grounded(body.is_on_floor())


func _update_crouch(body: PlayerCharacter, wants_crouch: bool, delta: float) -> void:
	var movement: PlayerMovement = body.get_movement()
	var target: float = 1.0 if wants_crouch else 0.0
	# Only stand up if there is room above the head.
	if target < movement.crouch_amount and not body.has_headroom_to_stand():
		target = movement.crouch_amount
	movement.crouch_amount = move_toward(movement.crouch_amount, target,
		body.tuning.crouch_transition_speed * delta)
	body.apply_height()
