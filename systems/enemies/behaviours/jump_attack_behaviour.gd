class_name JumpAttackBehaviour
extends EnemyBehaviour
## Kangaroo: when it starts attacking it leaps at you, and its kick knocks you flying.
## CHANGED 2026-10-30 (HL2 feel step 3.4): it leaps when its wind-up is over (on_strike), not the moment it
## decides to attack, so you can see it coming.

## Speed of the leap forward and up (metres per second).
@export var leap_forward: float = 7.0
## 5.6 at gravity 15.24 reaches the same height (about 1 m) as 4.5 did at 9.8 (CHANGED 2026-10-29).
@export var leap_up: float = 5.6
## Knockback of its hit (replaces the enemy's attack_knockback).
@export var kick_knockback: float = 9.0


func on_strike(enemy: Enemy) -> void:
	if not enemy.multiplayer.is_server() or enemy.get_target() == null:
		return
	var toward: Vector3 = enemy.get_target().global_position - enemy.global_position
	toward.y = 0.0
	var forward: Vector3 = toward.normalized() * leap_forward
	enemy.velocity = Vector3(forward.x, leap_up, forward.z)


func on_attack(_enemy: Enemy, info: DamageInfo) -> void:
	var push: Vector3 = info.knockback
	push.y = 0.0
	info.knockback = push.normalized() * kick_knockback + Vector3.UP * kick_knockback * 0.4
