extends EnemyState
## Hurt badly: run away from the target for a while, then idle (it may come back).

@export var flee_seconds: float = 4.0
@export var speed_scale: float = 1.2

var _left: float = 0.0


func enter(_enemy: Enemy) -> void:
	_left = flee_seconds


func physics_update(enemy: Enemy, delta: float) -> StringName:
	_left -= delta
	var target: PlayerCharacter = enemy.get_target()
	if target == null or _left <= 0.0:
		return &"idle"
	var away: Vector3 = enemy.global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	enemy.move_towards(enemy.global_position + away.normalized() * 4.0, speed_scale, delta)
	return &""
