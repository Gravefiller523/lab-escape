extends EnemyState
## Hurt badly: run away from the target for a short while, then come back and fight to the end.
## CHANGED 2026-10-20 (Zachary: the bat flew away and never came back): it flees only once, and when
## it's done it goes straight back after the player it ran from.

@export var flee_seconds: float = 2.5
@export var speed_scale: float = 1.2

var _left: float = 0.0


func enter(enemy: Enemy) -> void:
	_left = flee_seconds
	enemy.has_fled = true


func physics_update(enemy: Enemy, delta: float) -> StringName:
	_left -= delta
	var target: PlayerCharacter = enemy.get_target()
	if target == null:
		return &"idle"
	if _left <= 0.0:
		# Come back: it remembers who it ran from, even if it can't see them right now.
		enemy.set_target(target)
		return enemy.pursuit_state()
	var away: Vector3 = enemy.global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	enemy.move_towards(enemy.global_position + away.normalized() * 4.0, speed_scale, delta)
	return &""
