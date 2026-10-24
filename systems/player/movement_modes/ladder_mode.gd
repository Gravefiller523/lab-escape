class_name LadderMovementMode
extends MovementMode
## Climbing a Ladder. PlayerMovement switches to this (over any mutation's mode) while the body is in a
## ladder's climb area and wants to climb (see wants_to_climb). Forward climbs up, or down when you look
## down past ladder_look_down_degrees; crouch climbs down; left/right moves along the rungs; jump lets go,
## pushing you away. At the top, forward also moves you over the edge to step off.

## How hard the body is pulled to its spot in front of the ladder (1 / seconds).
const SNAP: float = 10.0


## Should a body in a ladder's area climb now? In the air: yes (you grab it). On the ground: only when
## moving forward towards up.
static func wants_to_climb(body: PlayerCharacter, input: PlayerInputState) -> bool:
	if not body.is_on_floor():
		return true
	return input.move.y > 0.1 and _up_sign(body) > 0.0


static func _up_sign(body: PlayerCharacter) -> float:
	return -1.0 if body.get_look_pitch() < -deg_to_rad(body.tuning.ladder_look_down_degrees) else 1.0


func physics_update(body: PlayerCharacter, input: PlayerInputState, _delta: float) -> void:
	var movement: PlayerMovement = body.get_movement()
	var ladder: Ladder = movement.get_ladder()
	if ladder == null:
		return
	var tuning: PlayerTuning = body.tuning
	if input.jump_pressed:
		movement.let_go_of_ladder()
		body.velocity = _side_normal(body, ladder) * tuning.ladder_jump_off_speed + Vector3.UP * 2.0
		body.move_and_slide()
		return
	var climb: float = input.move.y * _up_sign(body) * tuning.ladder_climb_speed
	if input.crouch:
		climb = -tuning.ladder_climb_speed
	var normal: Vector3 = _side_normal(body, ladder)
	var across: Vector3 = ladder.get_across()
	var wish: Vector3 = WalkMovementMode.wish_direction(body, input)
	var horizontal: Vector3 = across * wish.dot(across) * tuning.ladder_strafe_speed
	# Stay just in front of the ladder (the climb area is wider than the ladder is deep).
	var stand_off: float = tuning.radius + 0.1
	var offset: float = (body.global_position - ladder.global_position).dot(normal)
	horizontal += normal * (stand_off - offset) * SNAP
	if body.global_position.y >= ladder.get_top_y() - 0.1 and input.move.y > 0.0:
		# At the top: step forward off the ladder onto whatever it leans on.
		horizontal = -normal * tuning.walk_speed
		climb = maxf(climb, 1.0)
	body.velocity = Vector3(horizontal.x, climb, horizontal.z)
	body.move_and_slide()
	movement.set_grounded(body.is_on_floor())


## The ladder's face on the side the body is on (points from the ladder towards the body).
static func _side_normal(body: PlayerCharacter, ladder: Ladder) -> Vector3:
	var facing: Vector3 = ladder.get_facing()
	return facing if (body.global_position - ladder.global_position).dot(facing) >= 0.0 else -facing
