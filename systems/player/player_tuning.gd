class_name PlayerTuning
extends Resource
## Movement and camera tuning numbers for the player. The live copy is
## systems/player/player_tuning.tres: change numbers there in the Inspector, never in code.

@export_group("Walking")
## Metres per second when walking.
@export var walk_speed: float = 4.5
## Metres per second when sprinting.
@export var sprint_speed: float = 7.0
## Metres per second while crouched.
@export var crouch_speed: float = 2.5
## How quickly you reach full speed on the ground (higher = snappier).
@export var ground_acceleration: float = 12.0
## How much you can steer in the air (lower = less air control).
@export var air_acceleration: float = 3.0

@export_group("Jumping and falling")
## How high a normal jump goes, in metres.
@export var jump_height: float = 1.1
## Downward pull in metres per second squared.
@export var gravity: float = 20.0
## Fastest you can fall, metres per second.
@export var max_fall_speed: float = 40.0

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
## A jump also throws you forward this fast (metres per second) in the direction you move.
@export var hop_forward_speed: float = 5.0
## Moving on the ground makes small automatic hops.
@export var hop_auto_hops: bool = true
## How high the small automatic hops go (metres).
@export var hop_small_height: float = 0.3
## Fastest you can go sideways while hopping (keep under sprint speed x the host's speed_check_tolerance).
@export var hop_max_speed: float = 9.0

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
## Fastest you can slide, as a multiple of sprint speed x your speed multiplier (keep it at 1 or less:
## the host pulls back anyone faster than that x speed_check_tolerance).
@export var slide_max_speed: float = 1.0

@export_group("Camera")
## @deprecated 2026-10-24: use Settings.get_mouse_sensitivity() (the player's own setting).
@export var mouse_sensitivity: float = 0.25
## @deprecated 2026-10-24: use Settings.get_fov() (the player's own setting).
@export var fov: float = 85.0
## How far up and down you can look, in degrees.
@export var max_pitch: float = 89.0

@export_group("Network")
## How quickly other players' bodies catch up with their latest synced position (higher = snappier).
@export var remote_smoothing: float = 15.0
## If another player's body is further than this from its synced position, it jumps there (metres).
@export var remote_snap_distance: float = 4.0
## Host check: a player may move this many times their top speed before being pulled back.
@export var speed_check_tolerance: float = 1.5
## Host check: extra metres allowed on top of the speed limit (covers network hiccups).
@export var speed_check_slack: float = 1.5
