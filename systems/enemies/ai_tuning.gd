class_name AiTuning
extends Resource
## How every enemy thinks and moves, for all enemy types. NEW 2026-10-29 (feel tuning, step 0).
## The live copy is the "ai" section of res://config/feel_tuning.tres (open it in the Inspector).
## Read it with Config.feel.ai.<field>. Per-enemy numbers (health, speed, sight range) stay in
## content/enemies/*.tres.

@export_group("Senses")
## How often (seconds) an enemy looks for players. Lower = reacts faster but costs more.
@export var sight_check_seconds: float = 0.2
## An enemy's eyes are this high (m) above its origin.
@export var eye_height: float = 0.4
## Enemies aim their sight line at this height (m) on a player: the chest.
@export var player_chest_height: float = 1.0
## Seconds it remembers a player it can no longer see.
@export var target_memory_seconds: float = 3.0

@export_group("Moving")
## How fast enemies turn to face where they're going (higher = snappier).
@export var turn_speed: float = 8.0
## How often (seconds) a path is worked out again.
@export var repath_seconds: float = 0.25
## On other PCs, how quickly an enemy's copy catches up with where the host says it is.
@export var client_smoothing: float = 15.0

@export_group("Death")
## Seconds a dead enemy lies there before it's removed.
@export var corpse_seconds: float = 2.0
