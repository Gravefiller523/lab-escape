extends WalkMovementMode
## Slug: starts slow (the mutation's speed multiplier) but builds up speed the longer it keeps moving, up to
## slide_max_speed x sprint speed (1.75: much faster than a normal sprint). Stopping, or getting blocked, loses
## the built-up speed. Slippery too: low grip on the ground, so you keep sliding after letting go and take
## a while to turn, and slopes pull you downhill.

## How far the built-up speed may run ahead of how fast you really go (so a wall or a crate takes it away).
const MOMENTUM_LEAD: float = 0.25

## 0 = starting speed, 1 = top speed. Builds up while moving.
var _momentum: float = 0.0


func enter(body: PlayerCharacter) -> void:
	_momentum = 0.0
	# Without this, standing still on a slope would hold you in place instead of sliding down.
	body.floor_stop_on_slope = false


func exit(body: PlayerCharacter) -> void:
	body.floor_stop_on_slope = true


## 0 to 1: how much speed has built up (tests).
func get_momentum() -> float:
	return _momentum


func top_speed(body: PlayerCharacter) -> float:
	return maxf(super.top_speed(body), body.tuning.sprint_speed * body.tuning.slide_max_speed)


func _speed(body: PlayerCharacter, input: PlayerInputState, speed: float, delta: float) -> float:
	var tuning: PlayerTuning = body.tuning
	var top: float = tuning.sprint_speed * tuning.slide_max_speed
	if input.move.length() > 0.1 and not body.get_movement().is_crouching():
		_momentum = minf(_momentum + delta / tuning.slide_build_up_seconds, 1.0)
	else:
		_momentum = maxf(_momentum - delta / tuning.slide_lose_seconds, 0.0)
	# Blocked by something (a wall, a crate): the built-up speed goes too.
	var actual: float = Vector2(body.velocity.x, body.velocity.z).length()
	if top > speed:
		_momentum = clampf(minf(_momentum, inverse_lerp(speed, top, actual) + MOMENTUM_LEAD), 0.0, 1.0)
	return lerpf(speed, top, _momentum)


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
	horizontal = horizontal.limit_length(top_speed(body))
	body.velocity = Vector3(horizontal.x, body.velocity.y, horizontal.z)
