class_name PullBehaviour
extends EnemyBehaviour
## NEW 2026-11-12 (roadmap WP10): its hit drags you towards it instead of knocking you away (Botany's vine creeper
## lashes you in from a distance). The pull is a knockback pointing at the enemy.

## How hard it pulls (the knockback's speed, towards the enemy).
@export var pull_strength: float = 7.0
## A little lift so you slide over the floor instead of scraping along it.
@export var pull_lift: float = 1.5


func on_attack(enemy: Enemy, info: DamageInfo) -> void:
	var target: PlayerCharacter = enemy.get_target()
	if target == null:
		return
	var toward: Vector3 = enemy.global_position - target.global_position
	toward.y = 0.0
	info.knockback = toward.normalized() * pull_strength + Vector3.UP * pull_lift
