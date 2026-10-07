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


func get_type_key() -> StringName:
	return &"enemy"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
