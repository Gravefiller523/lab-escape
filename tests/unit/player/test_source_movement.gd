extends GutTest
## The Source-style movement maths in WalkMovementMode (NEW 2026-10-29, HL2 feel step 1): friction and
## accelerate as pure functions, plus whole run-and-stop simulations at two tick rates.

const DT: float = 1.0 / 60.0


func test_friction_slows_by_a_share_of_speed() -> void:
	var after := WalkMovementMode.apply_friction(Vector3(4.5, 0, 0), 4.0, 2.5, DT)
	assert_almost_eq(after.x, 4.5 - 4.5 * 4.0 * DT, 0.0001)


func test_friction_below_stop_speed_brakes_a_fixed_amount() -> void:
	var after := WalkMovementMode.apply_friction(Vector3(0, 0, -1.0), 4.0, 2.5, DT)
	assert_almost_eq(after.z, -(1.0 - 2.5 * 4.0 * DT), 0.0001, "brakes as if moving at stop_speed")


func test_friction_never_reverses() -> void:
	var after := WalkMovementMode.apply_friction(Vector3(0.05, 0, 0), 4.0, 2.5, DT)
	assert_eq(after, Vector3.ZERO)


func test_accelerate_adds_along_the_keys() -> void:
	var after := WalkMovementMode.accelerate(Vector3.ZERO, Vector3(1, 0, 0), 4.5, 10.0, DT)
	assert_almost_eq(after.x, 10.0 * 4.5 * DT, 0.0001)


func test_accelerate_stops_at_wish_speed() -> void:
	var after := WalkMovementMode.accelerate(Vector3(4.4, 0, 0), Vector3(1, 0, 0), 4.5, 10.0, DT)
	assert_almost_eq(after.x, 4.5, 0.0001)
	after = WalkMovementMode.accelerate(Vector3(6.0, 0, 0), Vector3(1, 0, 0), 4.5, 10.0, DT)
	assert_almost_eq(after.x, 6.0, 0.0001, "already faster: nothing added, nothing taken")


func test_accelerate_keeps_sideways_speed() -> void:
	var after := WalkMovementMode.accelerate(Vector3(0, 0, 3.0), Vector3(1, 0, 0), 4.5, 10.0, DT)
	assert_almost_eq(after.z, 3.0, 0.0001)
	assert_gt(after.x, 0.0)


## Seconds to reach 95% of `top` from standing, and then to stop, with friction + accelerate at `rate` Hz.
func _run_and_stop(rate: float, top: float) -> Vector2:
	var dt: float = 1.0 / rate
	var velocity := Vector3.ZERO
	var t: float = 0.0
	while velocity.length() < top * 0.95 and t < 5.0:
		velocity = WalkMovementMode.apply_friction(velocity, 4.0, 2.5, dt)
		velocity = WalkMovementMode.accelerate(velocity, Vector3(0, 0, -1), top, 10.0, dt)
		t += dt
	var start_time: float = t
	while velocity.length() > 0.0 and t < 10.0:
		velocity = WalkMovementMode.apply_friction(velocity, 4.0, 2.5, dt)
		t += dt
	return Vector2(start_time, t - start_time)


func test_run_and_stop_times_are_snappy() -> void:
	var times: Vector2 = _run_and_stop(60.0, 4.5)
	assert_between(times.x, 0.08, 0.3, "reaches full walk speed quickly (%.3f s)" % times.x)
	assert_between(times.y, 0.2, 0.6, "stops crisply (%.3f s)" % times.y)


func test_same_feel_at_60_and_120_ticks() -> void:
	var at_60: Vector2 = _run_and_stop(60.0, 4.5)
	var at_120: Vector2 = _run_and_stop(120.0, 4.5)
	assert_almost_eq(at_120.x, at_60.x, at_60.x * 0.25, "time to top speed")
	assert_almost_eq(at_120.y, at_60.y, at_60.y * 0.25, "stop time")


func test_air_accelerate_never_brakes() -> void:
	var after := WalkMovementMode.air_accelerate(Vector3(5, 0, 0), Vector3(-1, 0, 0), 4.5, 10.0, 0.76, DT)
	assert_almost_eq(after.x, 5.0 - 0.75, 0.0001, "pressing backwards in the air only trims a little")
	after = WalkMovementMode.air_accelerate(Vector3(5, 0, 0), Vector3.ZERO, 0.0, 10.0, 0.76, DT)
	assert_eq(after, Vector3(5, 0, 0), "no keys: momentum kept")


func test_air_accelerate_stops_at_the_cap_along_the_keys() -> void:
	var after := WalkMovementMode.air_accelerate(Vector3(0.7, 0, 0), Vector3(1, 0, 0), 4.5, 10.0, 0.76, DT)
	assert_almost_eq(after.x, 0.76, 0.0001)


func test_air_strafing_builds_speed() -> void:
	# Moving forward at 5 m/s, holding a side key while turning the view with the path: each tick the side
	# key points just past square to the motion, which is how Source air strafing gains speed.
	var velocity := Vector3(0, 0, -5.0)
	for _tick: int in 60:
		var side: Vector3 = velocity.normalized().cross(Vector3.UP)
		velocity = WalkMovementMode.air_accelerate(velocity, side, 4.5, 10.0, 0.76, DT)
	assert_gt(velocity.length(), 5.5, "a second of air strafing gains speed (%.2f m/s)" % velocity.length())
