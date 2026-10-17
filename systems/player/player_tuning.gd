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

@export_group("Camera")
## Degrees turned per pixel of mouse movement. STUB: settings_input will provide this later.
@export var mouse_sensitivity: float = 0.25
## Field of view in degrees. STUB: settings_input will provide this later.
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
