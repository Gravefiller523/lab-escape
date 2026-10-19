extends EnemyState
## Run at the target. In attack range -> attack. Lost them -> go to where they were last, then idle.
## Low health -> flee.


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_target() != null


func physics_update(enemy: Enemy, delta: float) -> StringName:
	if should_flee(enemy):
		return &"flee"
	var target: PlayerCharacter = enemy.update_target()
	if target == null:
		return &"idle"
	if enemy.data != null and enemy.flat_distance_to_target() <= enemy.data.attack_range and enemy.has_state(&"attack_melee"):
		return &"attack_melee"
	enemy.move_towards(target.global_position, 1.0, delta)
	return &""
