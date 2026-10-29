class_name CameraFeel
extends RefCounted
## Small camera movements on your own camera only, never synced (NEW 2026-10-29, HL2 feel step 1.6):
## - a dip on every landing and a pitch jolt ("punch") on hard landings, springing back;
## - view bob while walking and a sideways roll while strafing. HL2 has neither, so both are off unless
##   tuning turns them on (bob_height, strafe_roll_degrees).
## Everything is scaled by the camera shake setting, so "reduce motion" switches it all off.
## PlayerCharacter owns one, tells it about landings and asks it for the offsets each frame.

## Turns the punch amount into a starting spin so the jolt peaks at about that amount.
const PUNCH_KICK: float = 15.0

## Metres the eye is below where it should be (negative), springing back to 0.
var dip: float = 0.0
## Extra pitch in radians (negative = looking further down), springing back to 0.
var punch: float = 0.0

var _dip_speed: float = 0.0
var _punch_speed: float = 0.0
var _bob_phase: float = 0.0
var _roll: float = 0.0


## The body landed after falling at `fall_speed` m/s (positive).
func landed(tuning: PlayerTuning, fall_speed: float, shake: float) -> void:
	if shake <= 0.0:
		return
	var dip_amount: float = minf(maxf(fall_speed - tuning.landing_dip_start_speed, 0.0) * tuning.landing_dip_per_speed,
		tuning.landing_dip_max)
	dip = minf(dip, -dip_amount * shake)
	if fall_speed > tuning.landing_punch_start_speed:
		var degrees: float = minf((fall_speed - tuning.landing_punch_start_speed) * tuning.landing_punch_per_speed,
			tuning.landing_punch_max_degrees)
		_punch_speed -= deg_to_rad(degrees) * PUNCH_KICK * shake


## Advances the springs, bob and roll. `flat_velocity` is the body's speed along the ground, `right` its
## right-hand direction.
func update(tuning: PlayerTuning, delta: float, grounded: bool, flat_velocity: Vector3, right: Vector3,
		shake: float) -> void:
	var stiffness: float = tuning.camera_spring_stiffness
	var damping: float = tuning.camera_spring_damping
	_dip_speed += (-stiffness * dip - damping * _dip_speed) * delta
	dip += _dip_speed * delta
	_punch_speed += (-stiffness * punch - damping * _punch_speed) * delta
	punch += _punch_speed * delta
	var speed: float = flat_velocity.length()
	if grounded and speed > 0.5:
		_bob_phase = fmod(_bob_phase + speed * delta * TAU / maxf(tuning.bob_stride, 0.1), TAU)
	var side: float = clampf(flat_velocity.dot(right) / 5.0, -1.0, 1.0)
	var target_roll: float = -deg_to_rad(tuning.strafe_roll_degrees) * side * shake
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-10.0 * delta))


## Metres to move the eye up (bob plus dip).
func get_height_offset(tuning: PlayerTuning, shake: float) -> float:
	return dip + sin(_bob_phase * 2.0) * tuning.bob_height * shake


## Radians to roll the camera (strafe roll).
func get_roll() -> float:
	return _roll
