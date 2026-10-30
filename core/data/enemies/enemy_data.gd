class_name EnemyData
extends ContentData
## A regular enemy. Example id: "enemy_rat". Files live in res://content/enemies/.
## The scene is built from the enemies system's shared AI states plus
## small per-enemy behaviour nodes. This file holds the numbers.

@export var scene: PackedScene
@export var max_health: float = 30.0
@export var move_speed: float = 3.0
@export var attack_damage: float = 10.0
@export var attack_damage_type: StringName = &"blunt"
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.0
## How far it can see players, in metres.
@export var sight_range: float = 15.0
## NEW 2026-10-30 (HL2 feel step 3.2): how wide it sees, in degrees (360 = all round). Players outside it
## go unnoticed unless they come within Config.feel.ai.close_sense_range or make a noise.
@export_range(10.0, 360.0) var sight_cone_degrees: float = 360.0
## NEW 2026-10-30 (step 3.4): how many of a player's attack tickets it needs to attack (small biters 1,
## heavy leapers 2). See Config.feel.ai.attack_tickets_per_player.
@export var attack_tickets: int = 1
## NEW 2026-10-30 (step 3.6): chance (0 to 1) that it jumps aside from a heavy prop thrown at it.
@export_range(0.0, 1.0) var dodge_chance: float = 0.0
## Health below this fraction makes it flee (0 = never flees).
@export_range(0.0, 1.0) var flee_health_fraction: float = 0.0
## Spawn budget cost. The spawner spends a per-floor budget on enemies.
@export var spawn_cost: int = 1
## Earliest floor (inside its department, 1 to 5) it can appear on.
@export var min_floor: int = 1
## Loot table rolled when it dies. Empty = the department's default table.
@export var loot_id: StringName = &""
## Can it knock items out of carts or steal them? (open question, default off)
@export var can_steal_from_carts: bool = false
## NEW 2026-10-29: how heavy it counts as when a thrown prop hits it (kg). Light enemies are hurt a lot by a
## thrown crate, heavy ones barely (rat 5, bat 2, fly 0.5, kangaroo 50).
@export var impact_mass: float = 20.0


func get_type_key() -> StringName:
	return &"enemy"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
