class_name PropTuning
extends Resource
## How picking up, holding, throwing and pushing props feels. NEW 2026-10-29 (feel tuning, step 0).
## The live copy is the "props" section of res://config/feel_tuning.tres (open it in the Inspector).
## Read it with Config.feel.props.<field>. Change numbers there, never in code.
## Network numbers (sync rates, interpolation delay) stay in GameConfig.

@export_group("Picking up")
## Heaviest object (kg) one player can lift. Heavier ones need helpers (see heavy_lift_per_holder).
@export var grab_max_mass: float = 40.0
## Heavy objects: each person holding one takes this many kg off its weight. 1 person moves it very
## slowly, more people faster; once they take off all of it, it is fully lifted.
@export var heavy_lift_per_holder: float = 30.0
## How far away (m) a player can grab something.
@export var grab_reach: float = 2.5

@export_group("Holding")
## How far in front of the camera (m) a held object floats (plus the object's own size).
@export var hold_distance: float = 1.6
## A held object never comes closer to a wall in front of you than this (m).
@export var min_hold_gap: float = 0.2
## Furthest up or down (degrees) a held object follows your look (Half-Life 2: 75).
@export_range(0.0, 90.0) var max_hold_pitch_degrees: float = 75.0
## How fast (m/s) a fully lifted prop may move to keep up with your hands (Half-Life 2: about 25).
@export var held_prop_track_speed: float = 20.0
## Fastest (m/s) a heavy prop can be dragged; it goes slower with fewer helpers.
@export var held_prop_max_speed: float = 8.0
## Fastest a held prop turns to keep its angle (radians a second; Half-Life 2: 62.8 = 3600 degrees).
## Jolt's own limit (Project Settings > Physics > Jolt Physics 3D > Limits) must be at least this.
@export var hold_max_spin: float = 62.8
## While held, a fully lifted prop weighs this much (kg), so it nudges things gently (Half-Life 2: 1).
@export var held_mass: float = 1.0
## How strongly a held prop's spinning is slowed down (Half-Life 2: 10).
@export var held_angular_damp: float = 10.0
## Heavy props that aren't fully lifted are pulled toward your hands by a spring: its strength
## (per metre, per kg) and how much it damps wobbling.
@export var hold_stiffness: float = 150.0
@export var hold_damping: float = 22.0

@export_group("Dropping")
## If a held object is stuck this far (m) from where it should be...
@export var hold_break_distance: float = 1.5
## ...for this long (seconds), it is dropped.
@export var hold_break_seconds: float = 0.4
## A dropped prop moves at most this fast (m/s), so you can't fling things by spinning around.
@export var held_prop_release_max_speed: float = 10.5
## A dropped prop spins at most this fast (radians a second; Half-Life 2: 12.6 = 720 degrees).
@export var release_max_spin: float = 12.6

@export_group("Throwing")
## Throw strength, Half-Life 2 style: the push is throw_force x a weight factor (0.5 at 0.5 kg up to 4
## at 15 kg and above), so a 10 kg crate flies about 10 m/s and heavier things go less far.
## Half-Life 2 uses 25.4.
@export var throw_force: float = 34.0
## A thrown prop gets up to this much random spin (radians a second on each axis).
@export var throw_spin: float = 3.0

@export_group("Pushing")
## Props you walk into move this fraction of your speed, so you stay pressed against them.
@export var push_speed_factor: float = 0.9
