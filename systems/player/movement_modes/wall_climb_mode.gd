extends WalkMovementMode
## Octo: walk into a wall (or anything solid you can't walk through: crates, machines) and you climb it.
## Forward climbs up, crouch climbs down, left/right moves along the wall, and with no keys you hang on.
## Pull back (S) to let go. Reaching the top gives a small push up so you get over the edge.
## Jumping is off for Octo (the mutation's can_jump), so the only way up is climbing.

## Pushing into the wall at least this much (dot product, 0 to 1) counts as "climb".
const INTO_WALL: float = 0.3
## Metres per second pressed into the wall while climbing, so you stay touching it.
const STICK_SPEED: float = 1.0

var _climbing: bool = false
var _wall_normal: Vector3 = Vector3.ZERO


func enter(_body: PlayerCharacter) -> void:
	_climbing = false


func is_climbing() -> bool:
	return _climbing


func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void:
	var touching: bool = body.is_on_wall()
	if touching:
		_wall_normal = body.get_wall_normal()
	var wish: Vector3 = wish_direction(body, input)
	var pushing: bool = touching and wish.dot(-_wall_normal) > INTO_WALL
	var hanging: bool = _climbing and touching and input.move.y >= 0.0
	if pushing or hanging:
		_climb(body, input, wish)
		return
	_climbing = false
	super.physics_update(body, input, delta)


func _climb(body: PlayerCharacter, input: PlayerInputState, wish: Vector3) -> void:
	var tuning: PlayerTuning = body.tuning
	var movement: PlayerMovement = body.get_movement()
	_climbing = true
	var up: float = 0.0
	if input.crouch:
		up = -tuning.wall_climb_speed
	elif input.move.y > 0.0:
		up = tuning.wall_climb_speed * input.move.y * movement.get_speed_multiplier()
	var along: Vector3 = _wall_normal.cross(Vector3.UP).normalized()
	var strafe: Vector3 = along * wish.dot(along) * tuning.wall_climb_strafe_speed
	body.velocity = -_wall_normal * STICK_SPEED + strafe + Vector3.UP * up
	body.move_and_slide()
	movement.set_grounded(body.is_on_floor())
	if not body.is_on_wall():
		# Climbed past the top (or off the side): hop up over the edge if still going up.
		_climbing = false
		if up > 0.0:
			body.velocity = -_wall_normal * tuning.walk_speed * 0.6 + Vector3.UP * tuning.wall_climb_ledge_boost
