extends EnemyState
## Close enough: face the target and hit it every attack_cooldown. Too far again -> go after them.


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_target() != null


func physics_update(enemy: Enemy, delta: float) -> StringName:
	if should_flee(enemy):
		return &"flee"
	var target: PlayerCharacter = enemy.update_target()
	if target == null:
		return &"idle"
	var reach: float = enemy.data.attack_range if enemy.data != null else 1.5
	if enemy.flat_distance_to_target() > reach * 1.3:
		return enemy.pursuit_state()
	if enemy.flying:
		enemy.move_towards(target.global_position, 0.3, delta)
	elif enemy.is_on_floor():
		enemy.stop()
		enemy.face(target.global_position, delta)
	# (In the air, e.g. a kangaroo's leap, it keeps its momentum.)
	enemy.try_attack()
	return &""
