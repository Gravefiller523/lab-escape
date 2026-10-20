extends EnemyState
## Stand around. Sees a player -> go after them. After a while -> patrol (if it has that state).

@export var min_seconds: float = 1.5
@export var max_seconds: float = 4.0

var _left: float = 0.0


func enter(enemy: Enemy) -> void:
	enemy.stop()
	_left = enemy.rng.randf_range(min_seconds, max_seconds)


func physics_update(enemy: Enemy, delta: float) -> StringName:
	enemy.stop()
	if enemy.update_target() != null:
		return enemy.pursuit_state()
	_left -= delta
	if _left <= 0.0 and enemy.has_state(&"patrol"):
		return &"patrol"
	return &""
