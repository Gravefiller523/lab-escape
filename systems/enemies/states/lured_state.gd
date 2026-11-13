extends EnemyState
## Lured (NEW 2026-11-12, roadmap WP14): something it can't resist is nearby (Enemy.get_lure(): a laser dot, trash).
## It forgets whoever it was after, goes to the lure and stays on it, watching it. It snaps out when it is hurt
## (Enemy.on_hurt_by), when the lure is gone, or when it gets bored after Config.feel.ai.lure_attention_seconds
## (then it ignores lures for lure_bored_seconds, so a laser pointer can't hold a rat for ever).
## Enemy adds this state by itself to any enemy whose EnemyData.lure_kinds isn't empty. Host only.

## This close to the lure it stops and stares at it.
const STARE_DISTANCE: float = 0.9

var _attention_left: float = 0.0


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_lure() != null


func enter(enemy: Enemy) -> void:
	enemy.set_target(null)
	_attention_left = Config.feel.ai.lure_attention_seconds


func physics_update(enemy: Enemy, delta: float) -> StringName:
	var lure: Lure = enemy.get_lure()
	_attention_left -= delta
	if lure == null or _attention_left <= 0.0:
		if lure != null:
			enemy.search_point = lure.global_position
			enemy.ignore_lures_for(Config.feel.ai.lure_bored_seconds)
		enemy.clear_lure()
		return &"search" if enemy.has_state(&"search") else &"idle"
	var point: Vector3 = lure.global_position
	if enemy.flat_distance_to(point) > STARE_DISTANCE:
		enemy.move_towards(point, 1.0, delta)
	else:
		enemy.stop()
		enemy.face(point, delta)
	return &""
