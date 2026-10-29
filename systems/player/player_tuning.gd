class_name PlayerTuning
extends Resource
## Movement and camera tuning numbers for the player. The live copy is
## systems/player/player_tuning.tres: change numbers there in the Inspector, never in code.

@export_group("Walking")
## Metres per second when walking. HL2's run is 4.83 (was 4.5 until 2026-10-29).
@export var walk_speed: float = 4.8
## Metres per second when sprinting (was 7.0 until 2026-10-29).
@export var sprint_speed: float = 7.5
## Metres per second while crouched (was 2.5 until 2026-10-29).
@export var crouch_speed: float = 1.9
## How quickly you reach full speed on the ground (higher = snappier). Source-style (CHANGED 2026-10-29):
## each second you gain this many times your target speed, so 10 reaches full speed in about 0.13 s.
@export_range(1.0, 30.0, 0.5) var ground_acceleration: float = 10.0
## How hard the ground slows you down (NEW 2026-10-29, Source-style). Higher = shorter stops.
@export_range(0.0, 12.0, 0.1) var ground_friction: float = 4.0
## Below this speed (m/s) friction brakes as if you were going this fast, so stops end crisply instead of
## drifting (NEW 2026-10-29).
@export_range(0.0, 6.0, 0.1) var stop_speed: float = 2.5
## How much you can steer in the air (lower = less air control). Source-style (CHANGED 2026-10-29): the air
## never slows you down; it only bends your path, and air strafing (turning while holding a side key) can
## build speed, as in HL2.
@export_range(0.0, 30.0, 0.5) var air_acceleration: float = 10.0
## How hard a key can push you in the air, in m/s (NEW 2026-10-29). HL2's 0.76 lets you curve and air strafe
## but not stop or turn round in mid-air. Higher = more air control.
@export_range(0.0, 10.0, 0.01) var air_wish_speed_cap: float = 0.76

@export_group("Stairs and floors")
## Highest ledge or stair you walk up without jumping, in metres (NEW 2026-10-29; HL2's is 0.46).
@export_range(0.0, 1.0, 0.01) var step_height: float = 0.45
## Walking down stairs or a slope, you stay on the floor if it is at most this far below (NEW 2026-10-29).
@export_range(0.0, 1.0, 0.01) var floor_snap_length: float = 0.45
## Steepest slope you can walk up, in degrees (NEW 2026-10-29).
@export_range(0.0, 89.0, 1.0) var floor_max_angle_degrees: float = 46.0
## Walls hit at a shallower angle than this (degrees) stop you instead of sliding you along (NEW
## 2026-10-29). Low = you slide along walls you brush against.
@export_range(0.0, 90.0, 1.0) var wall_min_slide_angle_degrees: float = 5.0
## After a stair step the camera catches up over about this long, instead of popping (NEW 2026-10-29).
@export_range(0.0, 0.5, 0.01) var camera_step_smooth_seconds: float = 0.08

@export_group("Jumping and falling")
## How high a normal jump goes, in metres (was 1.1 until 2026-10-29; HL2's standing jump is lower).
@export var jump_height: float = 0.9
## Downward pull in metres per second squared. 15.24 is HL2's, and the world (physics/3d/default_gravity)
## matches it (was 20 for the player and 9.8 for the world until 2026-10-29).
@export var gravity: float = 15.24
## Fastest you can fall, metres per second.
@export var max_fall_speed: float = 40.0
## A jump pressed this long before landing still happens when you land (NEW 2026-10-29).
@export_range(0.0, 0.3, 0.01) var jump_buffer_seconds: float = 0.1
## You can still jump this long after walking off a ledge (NEW 2026-10-29).
@export_range(0.0, 0.3, 0.01) var coyote_seconds: float = 0.1

@export_group("Body")
## Standing height in metres (before Giraffe-style height multipliers).
@export var stand_height: float = 1.8
## Crouched height in metres.
@export var crouch_height: float = 1.1
## Capsule radius in metres.
@export var radius: float = 0.35
## Eyes are this far below the top of the head.
@export var eye_offset: float = 0.15
## How fast crouching and standing up happen (1 / seconds).
@export var crouch_transition_speed: float = 10.0
## Crouching in mid-air tucks your legs up instead of lowering your head, so a crouch-jump clears higher
## ledges (NEW 2026-10-29, as in HL2).
@export var allow_crouch_jump: bool = true
## How fast the legs tuck up or drop back down in mid-air (crouches per second, NEW 2026-10-29).
@export_range(1.0, 40.0, 0.5) var air_crouch_transition_speed: float = 15.0

@export_group("Ladders")
## Metres per second up or down a ladder.
@export var ladder_climb_speed: float = 3.0
## Metres per second sideways on a ladder.
@export var ladder_strafe_speed: float = 1.5
## Look further down than this (degrees) and "forward" climbs down instead of up.
@export var ladder_look_down_degrees: float = 35.0
## Jumping off a ladder pushes you this fast away from it (metres per second).
@export var ladder_jump_off_speed: float = 4.0
## After jumping off, ladders can't grab you for this long (seconds).
@export var ladder_regrab_seconds: float = 0.4

@export_group("Hover (Fly)")
## Hold jump in the air to glide: you fall no faster than this (metres per second).
@export var hover_fall_speed: float = 1.2
## Seconds of gliding before you need to land again.
@export var hover_seconds: float = 2.5
## Steering in the air while gliding, as a multiple of normal air control.
@export var hover_air_control: float = 2.5

@export_group("Hop (Frog)")
## On the ground the frog walks slowly: walking and sprinting speed x this.
@export var hop_walk_speed_multiplier: float = 0.5
## A jump throws you forward this fast (metres per second) in the direction you move (or face, when standing).
@export var hop_forward_speed: float = 7.0
## Hold jump to charge (release to leap). Seconds to reach a full charge.
@export var hop_charge_seconds: float = 1.0
## A full charge jumps this many times higher than a tap.
@export var hop_charge_height_multiplier: float = 1.6
## A full charge throws you forward this many times faster than a tap.
@export var hop_charge_forward_multiplier: float = 2.0
## Moving while charging: walking speed x this (the frog squats).
@export var hop_charge_move_multiplier: float = 0.3
## Steering in the air during a leap, as a multiple of normal air control (low = the leap carries you, like a
## real frog; 1 = normal, which brakes the leap if you let go of the keys).
@export var hop_air_control: float = 0.1
## Fastest you can go sideways after a leap (the host's speed check allows this for frogs).
@export var hop_max_speed: float = 15.0

@export_group("Wall climb (Octo)")
## Metres per second up a wall.
@export var wall_climb_speed: float = 2.5
## Metres per second sideways along a wall.
@export var wall_climb_strafe_speed: float = 1.5
## Upward push when you reach the top of a wall, so you get over the edge (metres per second).
@export var wall_climb_ledge_boost: float = 4.0

@export_group("Slide (Slug)")
## Grip on the ground (1 = normal, lower = slippery: you keep sliding after letting go).
@export var slide_grip: float = 0.2
## How strongly slopes pull you downhill (1 = like a ball rolling).
@export var slide_slope_pull: float = 0.6
## Top speed once fully built up, as a multiple of the normal sprint speed (2 = twice as fast as
## sprinting). The host's speed check knows about it, so it never pulls a slug back.
@export var slide_max_speed: float = 2.0
## Seconds of moving to build up from the slug's starting speed to top speed.
@export var slide_build_up_seconds: float = 8.0
## Seconds to lose all of it after you stop moving.
@export var slide_lose_seconds: float = 3.0

@export_group("Camera feel")
## Landing dip (NEW 2026-10-29): landing faster than this (m/s, downwards) dips the view...
@export_range(0.0, 20.0, 0.1) var landing_dip_start_speed: float = 2.0
## ...by this many metres per m/s above it...
@export_range(0.0, 0.1, 0.001) var landing_dip_per_speed: float = 0.015
## ...up to this much (metres).
@export_range(0.0, 0.5, 0.01) var landing_dip_max: float = 0.12
## Landing punch (NEW 2026-10-29): landing faster than this jolts the view down. 8.9 m/s is HL2's (a fall of
## about 2.6 m)...
@export_range(0.0, 30.0, 0.1) var landing_punch_start_speed: float = 8.9
## ...by this many degrees per m/s above it...
@export_range(0.0, 3.0, 0.05) var landing_punch_per_speed: float = 0.5
## ...up to this many degrees.
@export_range(0.0, 20.0, 0.5) var landing_punch_max_degrees: float = 6.0
## How quickly the dip and punch spring back (higher = snappier) and settle (higher = less wobble).
@export_range(1.0, 300.0, 1.0) var camera_spring_stiffness: float = 65.0
@export_range(0.0, 50.0, 0.5) var camera_spring_damping: float = 9.0
## View bob while walking, in metres (NEW 2026-10-29). 0 = off, as in HL2. Try 0.012.
@export_range(0.0, 0.1, 0.001) var bob_height: float = 0.0
## Metres walked for one full bob cycle (two footsteps).
@export_range(0.5, 10.0, 0.1) var bob_stride: float = 3.4
## Camera tilt while strafing at full speed, in degrees (NEW 2026-10-29). 0 = off, as in HL2. Try 0.75.
@export_range(0.0, 5.0, 0.05) var strafe_roll_degrees: float = 0.0

@export_group("Footsteps")
## Metres walked per footstep sound (NEW 2026-10-29, HL2 feel step 1.7). HL2 is about 1.4 to 1.7.
@export_range(0.3, 5.0, 0.05) var footstep_stride: float = 1.7
## Metres per footstep when sprinting (longer strides).
@export_range(0.3, 5.0, 0.05) var footstep_sprint_stride: float = 2.1
## Metres per footstep when crouching.
@export_range(0.3, 5.0, 0.05) var footstep_crouch_stride: float = 1.2
## Slower than this (m/s) makes no footsteps.
@export_range(0.0, 5.0, 0.1) var footstep_min_speed: float = 0.8
## Footstep loudness in dB (0 = full).
@export_range(-40.0, 6.0, 0.5) var footstep_volume_db: float = -6.0
## Footstep loudness while crouching, in dB. Much quieter, for sneaking.
@export_range(-40.0, 6.0, 0.5) var footstep_crouch_volume_db: float = -18.0
## Landing slower than this (m/s) makes no landing sound; faster landings are louder.
@export_range(0.0, 20.0, 0.5) var landing_sound_min_speed: float = 3.0

@export_group("Camera")
## @deprecated 2026-10-24: use Settings.get_mouse_sensitivity() (the player's own setting).
@export var mouse_sensitivity: float = 0.066
## @deprecated 2026-10-24: use Settings.get_fov() (the player's own setting).
@export var fov: float = 74.0
## How far up and down you can look, in degrees.
@export var max_pitch: float = 89.0

@export_group("Network")
## How quickly other players' bodies catch up with their latest synced position (higher = snappier).
@export var remote_smoothing: float = 15.0
## If another player's body is further than this from its synced position, it jumps there (metres).
@export var remote_snap_distance: float = 4.0
## Host check: a player may move this many times their top speed before being pulled back.
@export var speed_check_tolerance: float = 1.5
## Host check: extra metres allowed on top of the speed limit in each window (covers network hiccups).
@export var speed_check_slack: float = 1.5
## Host check: seconds of movement judged at once (NEW 2026-10-29). Was every network update, which let the
## slack add up to any speed.
@export_range(0.1, 2.0, 0.05) var speed_check_window: float = 0.5
## Host check: how fast (m/s per second) the allowed speed may grow past top speed, for bunny hopping and
## air strafing (NEW 2026-10-29).
@export_range(0.0, 50.0, 0.5) var speed_check_growth: float = 8.0
## Host check: no player goes faster than this along the ground, in m/s (NEW 2026-10-29). About 3x sprint.
@export_range(5.0, 100.0, 0.5) var speed_check_max_speed: float = 22.5
