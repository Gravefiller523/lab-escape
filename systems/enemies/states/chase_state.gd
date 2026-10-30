extends EnemyState
## Run at the target. Close: take an attack ticket and attack, or circle until one is free. Lost them: run to
## where it saw them last, then search there. Low health -> flee.
## CHANGED 2026-10-30 (HL2 feel step 3.1, 3.4): it runs to where it last SAW you, not to where you really
## are (no more tracking you through walls), and it needs an attack ticket to attack.


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_target() != null


func physics_update(enemy: Enemy, delta: float) -> StringName:
	if should_flee(enemy):
		return &"flee"
	var target: PlayerCharacter = enemy.update_target()
	if target == null:
		return enemy.lose_target()
	if not enemy.can_see_target():
		if enemy.flat_distance_to(enemy.last_known_position) <= Enemy.ARRIVE_DISTANCE:
			return enemy.lose_target()
		enemy.move_towards(enemy.last_known_position, 1.0, delta)
		return &""
	if enemy.has_state(&"attack_melee") and enemy.flat_distance_to_target() <= engage_distance(enemy):
		if enemy.claim_attack_ticket():
			return &"attack_melee"
		enemy.circle(target, delta)
		return &""
	enemy.move_towards(target.global_position, 1.0, delta)
	return &""
