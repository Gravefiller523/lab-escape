extends EnemyState
## Go after the target as a group (rats, flies): like chase, but each one circles in from its own side,
## so a pack surrounds you instead of queueing up.
## CHANGED 2026-10-30 (HL2 feel step 3.1, 3.4, 3.5): it runs to where it last SAW you (not through walls),
## takes an attack ticket to attack (the rest circle), and the pack's spacing now comes from the navigation
## avoidance every walking enemy has (the old every-rat-against-every-rat check is gone).

@export var spread: float = 1.2

var _angle: float = 0.0


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_target() != null


func enter(enemy: Enemy) -> void:
	_angle = enemy.rng.randf() * TAU


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
	_angle += delta * 0.8
	var side := Vector3(cos(_angle), 0.0, sin(_angle)) * spread
	var goal: Vector3 = target.global_position + side * clampf(enemy.flat_distance_to_target() / 4.0, 0.0, 1.0)
	enemy.move_towards(goal, 1.0, delta)
	return &""
