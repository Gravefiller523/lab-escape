class_name HitFeelTuning
extends Resource
## How hits, hurts, kills and pickups feel (NEW 2026-11-11, roadmap WP7, mock-up approved by Zachary). Part of
## FeelTuning: Config.feel.hits. Everything here is looks only: no damage or game rules.

@export_group("Hitting an enemy")
## How long a hit enemy flashes white.
@export var enemy_flash_seconds: float = 0.08
## How long the enemy you hit holds still at the moment of impact (the "hit pause").
@export var impact_freeze_seconds: float = 0.05
## How far (m) its body jerks back, and how long it takes to settle.
@export var flinch_distance: float = 0.12
@export var flinch_seconds: float = 0.15

@export_group("Killing an enemy")
## The puff of little cubes a dead enemy pops into.
@export var death_poof_cubes: int = 14
@export var death_poof_speed: float = 3.5
@export var death_poof_seconds: float = 0.8
@export var death_poof_cube_size: float = 0.08

@export_group("Getting hurt")
## Your camera kicks up by this much (degrees) when you're hit, scaled by the camera shake setting.
@export var hurt_kick_degrees: float = 4.0
## The red at the edges of your screen: how strong it starts (0 to 1) and how long it takes to fade.
@export_range(0.0, 1.0) var hurt_vignette_strength: float = 0.55
@export var hurt_vignette_seconds: float = 0.4

@export_group("Picking up gems")
@export var gem_sparkle_count: int = 10
@export var gem_sparkle_speed: float = 1.6
## The "+5" that floats up from a gem you grab: how far it rises and how long it lasts.
@export var gem_text_rise: float = 0.6
@export var gem_text_seconds: float = 0.9
