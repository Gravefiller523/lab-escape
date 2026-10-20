extends EnemyState
## Wander to a random spot near home, then idle. Sees a player -> go after them.

@export var wander_radius: float = 6.0
@export var speed_scale: float = 0.5
@export var give_up_seconds: float = 6.0

var _point: Vector3 = Vector3.ZERO
var _left: float = 0.0


func enter(enemy: Enemy) -> void:
	var angle: float = enemy.rng.randf() * TAU
	var distance: float = enemy.rng.randf_range(wander_radius * 0.3, wander_radius)
	_point = enemy.home + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_left = give_up_seconds


func physics_update(enemy: Enemy, delta: float) -> StringName:
	if enemy.update_target() != null:
		return enemy.pursuit_state()
	enemy.move_towards(_point, speed_scale, delta)
	_left -= delta
	var flat: Vector3 = _point - enemy.global_position
	flat.y = 0.0
	if flat.length() < 0.8 or _left <= 0.0:
		return &"idle"
	return &""
