class_name EnemyBehaviour
extends Node
## A small per-enemy extra (a kangaroo's leap, a bat's swoop). Add it as a child of the Enemy.
## Spec: docs/systems/enemies.md.


## Every PC: the enemy switched state (the host decides; others hear it with the position sync).
func on_state_changed(_enemy: Enemy, _state: StringName) -> void:
	pass


## Host: the enemy is about to hit; change the hit (more knockback, a status...).
func on_attack(_enemy: Enemy, _info: DamageInfo) -> void:
	pass
