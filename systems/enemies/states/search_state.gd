extends EnemyState
## NEW 2026-10-30 (HL2 feel step 3.2, 3.3): go to Enemy.search_point (a noise it heard, or where it lost
## you), look around there for Config.feel.ai.search_seconds, then go back to idle. Notices someone -> after
## them.

@export var speed_scale: float = 0.7
## Gives up walking there after this long (s) and looks around where it is.
@export var give_up_seconds: float = 8.0

var _travel_left: float = 0.0
var _look_left: float = 0.0
var _turn_left: float = 0.0
var _arrived: bool = false
var _look_at: Vector3 = Vector3.ZERO


func enter(enemy: Enemy) -> void:
	_travel_left = give_up_seconds
	_look_left = Config.feel.ai.search_seconds
	_turn_left = 0.0
	_arrived = false
	_look_at = enemy.search_point


func physics_update(enemy: Enemy, delta: float) -> StringName:
	if enemy.update_target() != null:
		return enemy.pursuit_state()
	if not _arrived:
		_travel_left -= delta
		if enemy.flat_distance_to(enemy.search_point) > Enemy.ARRIVE_DISTANCE and _travel_left > 0.0:
			enemy.move_towards(enemy.search_point, speed_scale, delta)
			return &""
		_arrived = true
	enemy.stop()
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = 0.8
		var angle: float = enemy.rng.randf() * TAU
		_look_at = enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 3.0
	enemy.face(_look_at, delta)
	_look_left -= delta
	return &"idle" if _look_left <= 0.0 else &""
