class_name BossPhaseData
extends Resource
## One phase of a boss fight. Saved inside the boss's .tres file.

## The phase starts when boss health drops to this fraction (1.0 = fight start).
@export_range(0.0, 1.0) var starts_at_health_fraction: float = 1.0
## Names of attacks from the boss scene to use in this phase, e.g. "laser_sweep".
@export var attack_names: PackedStringArray = PackedStringArray()
## Minions summoned during this phase.
@export var minion_enemy_ids: Array[StringName] = []
## How many minions per wave (before player-count scaling).
@export var minions_per_wave: int = 0
## Seconds between minion waves. 0 = one wave when the phase starts.
@export var minion_wave_interval: float = 0.0
