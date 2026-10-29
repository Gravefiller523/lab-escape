class_name WalkMovementMode
extends MovementMode
## The default movement mode: walk, sprint, jump, crouch, fall.
## Loaded by name ("walk") from PlayerMovement.load_mode(). The other modes (hover, hop, slide, wall_climb)
## extend this one and change only the steps they need: _speed, _grip, _jump_speed, _jump, _fall, _after_move.


## Dropping more than this in one tick while staying on the floor is a step down (the floor snap pulled
## us down a stair), so the camera smooths it.
const STEP_DOWN_MIN: float = 0.15

## Seconds left on a jump pressed in the air (jump buffer).
var _jump_buffer_left: float = 0.0
## Seconds since standing on the floor, and whether we left it by jumping (for coyote time).
var _air_seconds: float = 0.0
var _left_by_jump: bool = false


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

	var wish: Vector3 = wish_direction(body, input)
	var grounded: bool = body.is_on_floor()
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var vertical: float = body.velocity.y

	# Jump (CHANGED 2026-10-29): allowed while crouched, a press up to jump_buffer_seconds before landing
	# counts, and so does a late one up to coyote_seconds after walking off a ledge.
	if input.jump_pressed:
		_jump_buffer_left = tuning.jump_buffer_seconds
	if grounded:
		_air_seconds = 0.0
		_left_by_jump = false
	else:
		_air_seconds += delta
	var coyote: bool = not _left_by_jump and _air_seconds <= tuning.coyote_seconds
	var jumped: bool = false
	if _jump_buffer_left > 0.0 and (grounded or coyote) and movement.can_jump():
		jumped = true
		vertical = _jump_speed(body)
		horizontal = _jump(body, input, horizontal)
		_jump_buffer_left = 0.0
		_left_by_jump = true
	_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)

	# Source-style (CHANGED 2026-10-29): on the ground friction then accelerate; in the air only air
	# accelerate, so nothing brakes you. Jumping on the very tick you land skips that tick's friction, as in
	# Source; a buffered jump (pressed earlier) doesn't, so bunny hopping still takes timing.
	var on_ground: bool = grounded and not (jumped and input.jump_pressed)
	var grip: float = _grip(body, grounded and not jumped)
	if on_ground:
		horizontal = apply_friction(horizontal, tuning.ground_friction * grip, tuning.stop_speed, delta)
	if grounded and not jumped:
		horizontal = accelerate(horizontal, wish.normalized(), speed * wish.length(),
			tuning.ground_acceleration * grip, delta)
		vertical = minf(vertical, 0.0)
	else:
		horizontal = air_accelerate(horizontal, wish.normalized(), speed * wish.length(),
			tuning.air_acceleration * grip, _air_wish_cap(body), delta)
		if not jumped:
			vertical = _fall(body, input, vertical, delta)

	var stepped: float = 0.0
	if grounded and not jumped:
		stepped = StairStepper.try_step(body, horizontal * delta, tuning.step_height)
	if stepped > 0.0:
		# Already moved up and forward onto the step: a still move_and_slide just updates the floor contact.
		body.velocity = Vector3.ZERO
		body.move_and_slide()
		body.velocity = Vector3(horizontal.x, 0.0, horizontal.z)
		body.add_camera_step(stepped)
	else:
		var before_y: float = body.global_position.y
		body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
		body.move_and_slide()
		# Pulled down a stair by the floor snap: smooth the camera.
		var dropped: float = before_y - body.global_position.y
		if grounded and not jumped and body.is_on_floor() and dropped > STEP_DOWN_MIN:
			body.add_camera_step(-dropped)
	if not grounded and body.is_on_floor():
		body.notify_landed(maxf(-vertical, 0.0))
	movement.set_grounded(body.is_on_floor())
	_after_move(body, input, delta)


## The keys' direction turned into a flat direction in the world, relative to where the body faces (length 0 to 1).
static func wish_direction(body: PlayerCharacter, input: PlayerInputState) -> Vector3:
	var wish: Vector3 = body.global_transform.basis * Vector3(input.move.x, 0.0, -input.move.y)
	wish.y = 0.0
	return wish.normalized() if wish.length() > 1.0 else wish


## Ground friction (Source-style): slows `velocity` by friction x speed per second, but never by less than
## friction x stop_speed, so slow movement stops crisply. Returns the new velocity (never reversed).
static func apply_friction(velocity: Vector3, friction: float, stop_speed: float, delta: float) -> Vector3:
	var speed: float = velocity.length()
	if speed < 0.001:
		return Vector3.ZERO
	var drop: float = maxf(speed, stop_speed) * friction * delta
	return velocity * (maxf(speed - drop, 0.0) / speed)


## Accelerate (Source-style): adds up to accel x wish_speed per second along `wish_dir` (a unit vector), but
## only until the speed along wish_dir reaches wish_speed. Speed in other directions is left alone.
static func accelerate(velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var add: float = wish_speed - velocity.dot(wish_dir)
	if add <= 0.0 or wish_speed <= 0.0:
		return velocity
	return velocity + wish_dir * minf(accel * wish_speed * delta, add)


## Air accelerate (Source-style): like accelerate, but the speed you can add along `wish_dir` stops at
## `wish_cap` instead of the full wish speed (while the rate still uses the full wish speed). You can bend
## your path but not brake, and turning the view while holding a side key builds speed (air strafing).
static func air_accelerate(velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float,
		wish_cap: float, delta: float) -> Vector3:
	var add: float = minf(wish_speed, wish_cap) - velocity.dot(wish_dir)
	if add <= 0.0 or wish_speed <= 0.0:
		return velocity
	return velocity + wish_dir * minf(accel * wish_speed * delta, add)


## Upward speed for a normal jump with this body's gravity and jump multiplier: v = sqrt(2 g h).
static func jump_speed(body: PlayerCharacter) -> float:
	var movement: PlayerMovement = body.get_movement()
	return sqrt(2.0 * gravity_of(body) * body.tuning.jump_height * movement.get_jump_multiplier())


static func gravity_of(body: PlayerCharacter) -> float:
	return body.tuning.gravity * body.get_movement().get_gravity_multiplier()


## The speed to aim for this frame (slide builds up speed the longer you move).
func _speed(_body: PlayerCharacter, _input: PlayerInputState, speed: float, _delta: float) -> float:
	return speed


## How much of the normal acceleration (and, on the ground, friction) applies (1 = normal; lower = slippery).
func _grip(_body: PlayerCharacter, _grounded: bool) -> float:
	return 1.0


## How hard a key can push in the air, in m/s (see air_accelerate). Fly's glide steers more.
func _air_wish_cap(body: PlayerCharacter) -> float:
	return body.tuning.air_wish_speed_cap


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
	var tuning: PlayerTuning = body.tuning
	# Crouch-jump (NEW 2026-10-29): in mid-air the body shrinks and grows at the feet, not the head.
	var tuck: bool = tuning.allow_crouch_jump and not body.is_on_floor()
	var target: float = 1.0 if wants_crouch else 0.0
	# Only stand up if there is room: above the head, or (tucked in the air) below the feet.
	if target < movement.crouch_amount and not body.has_headroom_to_stand() \
			and not (tuck and body.has_legroom_to_stand()):
		target = movement.crouch_amount
	var speed: float = tuning.air_crouch_transition_speed if tuck else tuning.crouch_transition_speed
	var old_height: float = movement.get_height()
	movement.crouch_amount = move_toward(movement.crouch_amount, target, speed * delta)
	var change: float = movement.get_height() - old_height
	if tuck and not is_zero_approx(change):
		# Lift the feet (or drop them) by the change, so the head stays where it is. If something is in the
		# way the body changes size at the head instead.
		var shift: Vector3 = Vector3.DOWN * change
		if not body.test_move(body.global_transform, shift):
			body.global_position += shift
	body.apply_height()
