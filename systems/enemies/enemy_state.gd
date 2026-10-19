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


## Runs every physics frame while active. Returns the next state's name, or &"" to stay.
func physics_update(_enemy: Enemy, _delta: float) -> StringName:
	return &""


## Shared rule for every state: low on health and the enemy has a flee state -> flee.
static func should_flee(enemy: Enemy) -> bool:
	if not enemy.has_state(&"flee") or enemy.data == null or enemy.data.flee_health_fraction <= 0.0:
		return false
	var health: HealthComponent = enemy.get_health()
	return health != null and health.get_fraction() <= enemy.data.flee_health_fraction
