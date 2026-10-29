extends GutTest
## CameraFeel (NEW 2026-10-29, HL2 feel step 1.6): landing dip and punch, springing back, and the camera
## shake setting scaling it (0 = reduce motion = nothing).

const DT: float = 1.0 / 60.0


func _settle(feel: CameraFeel, tuning: PlayerTuning, seconds: float) -> void:
	for _tick: int in int(seconds / DT):
		feel.update(tuning, DT, true, Vector3.ZERO, Vector3.RIGHT, 1.0)


func test_soft_landing_dips_without_a_jolt() -> void:
	var tuning := PlayerTuning.new()
	var feel := CameraFeel.new()
	feel.landed(tuning, 5.0, 1.0)
	feel.update(tuning, DT, true, Vector3.ZERO, Vector3.RIGHT, 1.0)
	assert_lt(feel.dip, -0.01, "the view dips")
	assert_almost_eq(feel.punch, 0.0, 0.0001, "no jolt below the punch speed")


func test_hard_landing_jolts_and_springs_back() -> void:
	var tuning := PlayerTuning.new()
	var feel := CameraFeel.new()
	feel.landed(tuning, 14.0, 1.0)
	var lowest: float = 0.0
	for _tick: int in 20:
		feel.update(tuning, DT, true, Vector3.ZERO, Vector3.RIGHT, 1.0)
		lowest = minf(lowest, feel.punch)
	assert_between(rad_to_deg(-lowest), 1.0, tuning.landing_punch_max_degrees + 0.5, "looks down a few degrees")
	_settle(feel, tuning, 1.5)
	assert_almost_eq(feel.punch, 0.0, deg_to_rad(0.1), "back to level")
	assert_almost_eq(feel.dip, 0.0, 0.002, "back to eye height")


func test_reduce_motion_means_no_movement() -> void:
	var tuning := PlayerTuning.new()
	tuning.bob_height = 0.02
	var feel := CameraFeel.new()
	feel.landed(tuning, 14.0, 0.0)
	feel.update(tuning, DT, true, Vector3(4, 0, 0), Vector3.RIGHT, 0.0)
	assert_eq(feel.dip, 0.0)
	assert_eq(feel.punch, 0.0)
	assert_eq(feel.get_height_offset(tuning, 0.0), 0.0)
	assert_eq(feel.get_roll(), 0.0)


func test_bob_and_roll_are_off_by_default() -> void:
	var tuning := PlayerTuning.new()
	var feel := CameraFeel.new()
	for _tick: int in 30:
		feel.update(tuning, DT, true, Vector3(4, 0, 0), Vector3.RIGHT, 1.0)
	assert_eq(feel.get_height_offset(tuning, 1.0), 0.0, "no bob, like HL2")
	assert_eq(feel.get_roll(), 0.0, "no strafe roll, like HL2")
