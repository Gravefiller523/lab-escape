class_name EnemyState
extends Node
## A shared AI building block (idle, patrol, chase, swarm, attack_melee, flee). Put it under an enemy
## scene's "States" node; the node's name is the state's name. Host only. Spec: docs/systems/enemies.md.


## Can the enemy switch to this state now?
func can_enter(_enemy: Enemy) -> bool:
	return true


func enter(_enemy: Enemy) -> void:
	pass


func exit(_enemy: Enemy) -> void:
	pass


## NEW 2026-10-30 (HL2 feel step 3.3): may a noise or a hit switch it to another state right now? False while
## it can't stop (mid-attack).
func can_interrupt(_enemy: Enemy) -> bool:
	return true


## Runs every physics frame while active. Returns the next state's name, or &"" to stay.
func physics_update(_enemy: Enemy, _delta: float) -> StringName:
	return &""


## NEW 2026-10-30 (HL2 feel step 3.4): within this flat distance of its target an enemy stops running at
## them and either takes an attack ticket (attacks) or circles.
static func engage_distance(enemy: Enemy) -> float:
	var reach: float = enemy.data.attack_range if enemy.data != null else 1.5
	return maxf(Config.feel.ai.circle_distance, reach) + 0.5


## Shared rule for every state: low on health and the enemy has a flee state -> flee (only once).
static func should_flee(enemy: Enemy) -> bool:
	if enemy.has_fled or not enemy.has_state(&"flee") or enemy.data == null or enemy.data.flee_health_fraction <= 0.0:
		return false
	var health: HealthComponent = enemy.get_health()
	return health != null and health.get_fraction() <= enemy.data.flee_health_fraction
