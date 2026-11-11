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


## NEW 2026-11-11 (roadmap WP9): for chase and swarm: an enemy with a ranged attack starts shooting once it can see
## its target, is outside melee reach but inside its range, and its attack is ready.
static func should_shoot(enemy: Enemy) -> bool:
	if not enemy.has_state(&"attack_ranged") or enemy.data == null or enemy.data.ranged_attack == null:
		return false
	var distance: float = enemy.flat_distance_to_target()
	var melee_close: bool = enemy.has_state(&"attack_melee") and distance <= engage_distance(enemy)
	return not melee_close and distance <= enemy.data.ranged_attack.max_range and enemy.attack_ready() \
		and enemy.can_see_target()
