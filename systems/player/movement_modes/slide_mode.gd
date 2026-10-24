extends WalkMovementMode
## Slug: slow (the mutation's speed multiplier) and slippery. Low grip on the ground, so you keep sliding
## after letting go and take a while to turn, and slopes pull you downhill. Capped at slide_max_speed so the
## host's speed check never pulls you back.


func enter(body: PlayerCharacter) -> void:
	# Without this, standing still on a slope would hold you in place instead of sliding down.
	body.floor_stop_on_slope = false


func exit(body: PlayerCharacter) -> void:
	body.floor_stop_on_slope = true


func _grip(body: PlayerCharacter, grounded: bool) -> float:
	return body.tuning.slide_grip if grounded else 1.0


func _after_move(body: PlayerCharacter, _input: PlayerInputState, delta: float) -> void:
	if not body.is_on_floor():
		return
	var tuning: PlayerTuning = body.tuning
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	# Downhill: gravity along the slope (zero on flat ground).
	var normal: Vector3 = body.get_floor_normal()
	var downhill: Vector3 = Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	downhill.y = 0.0
	horizontal += downhill * gravity_of(body) * tuning.slide_slope_pull * delta
	var top_speed: float = tuning.sprint_speed * body.get_movement().get_speed_multiplier() * tuning.slide_max_speed
	horizontal = horizontal.limit_length(top_speed)
	body.velocity = Vector3(horizontal.x, body.velocity.y, horizontal.z)
