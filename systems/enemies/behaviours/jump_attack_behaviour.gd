class_name JumpAttackBehaviour
extends EnemyBehaviour
## Kangaroo: when it starts attacking it leaps at you, and its kick knocks you flying.

## Speed of the leap forward and up (metres per second).
@export var leap_forward: float = 7.0
@export var leap_up: float = 4.5
## Knockback of its hit (replaces the enemy's attack_knockback).
@export var kick_knockback: float = 9.0


func on_state_changed(enemy: Enemy, state: StringName) -> void:
	if state != &"attack_melee" or not enemy.multiplayer.is_server() or enemy.get_target() == null:
		return
	var toward: Vector3 = enemy.get_target().global_position - enemy.global_position
	toward.y = 0.0
	var forward: Vector3 = toward.normalized() * leap_forward
	enemy.velocity = Vector3(forward.x, leap_up, forward.z)


func on_attack(_enemy: Enemy, info: DamageInfo) -> void:
	var push: Vector3 = info.knockback
	push.y = 0.0
	info.knockback = push.normalized() * kick_knockback + Vector3.UP * kick_knockback * 0.4
