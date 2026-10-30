extends EnemyState
## It holds attack tickets for its target (see AttackTickets): get in range, wind up (a growl everyone hears),
## strike, then hand the tickets back and go after the target again.
## CHANGED 2026-10-30 (HL2 feel step 3.4): tickets, the wind-up, and one attack per ticket. Once the wind-up
## has started, nothing interrupts it.

enum Step { APPROACH, WINDUP, STRIKE }

var _step: Step = Step.APPROACH
var _left: float = 0.0


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_target() != null


func enter(_enemy: Enemy) -> void:
	_step = Step.APPROACH
	# Give up a little before the tickets run out, so nobody else gets them while it's still here.
	_left = Config.feel.ai.ticket_max_hold * 0.75


func exit(enemy: Enemy) -> void:
	AttackTickets.release(enemy)


func can_interrupt(_enemy: Enemy) -> bool:
	return _step == Step.APPROACH


func physics_update(enemy: Enemy, delta: float) -> StringName:
	var target: PlayerCharacter = enemy.update_target()
	if _step == Step.APPROACH:
		if should_flee(enemy):
			return &"flee"
		if target == null:
			return enemy.lose_target()
		_left -= delta
		if _left <= 0.0 or not AttackTickets.holds(enemy, target):
			# Took too long to get there (or lost its tickets): let someone else have a go.
			enemy.end_attack()
			return enemy.pursuit_state()
		var reach: float = enemy.data.attack_range if enemy.data != null else 1.5
		if enemy.flat_distance_to_target() > reach:
			enemy.move_towards(target.global_position, 1.0, delta)
			return &""
		_step = Step.WINDUP
		_left = Config.feel.ai.attack_windup
		# Keep the tickets for the whole wind-up and strike.
		AttackTickets.claim(enemy, target)
		enemy.begin_windup()
	if target == null:
		enemy.end_attack()
		return enemy.lose_target()
	if _step == Step.WINDUP:
		_hold(enemy, target, delta)
		_left -= delta
		if _left > 0.0:
			return &""
		_step = Step.STRIKE
		_left = Config.feel.ai.attack_strike_seconds
		enemy.strike()
	# Striking. A walking enemy only turns (a kangaroo's leap keeps its momentum); a flyer lunges in.
	if enemy.flying:
		enemy.move_towards(target.global_position, 0.3, delta)
	else:
		enemy.face(target.global_position, delta)
	if enemy.try_attack():
		enemy.end_attack()
		return enemy.pursuit_state()
	_left -= delta
	if _left <= 0.0:
		enemy.end_attack()
		return enemy.pursuit_state()
	return &""


## Winding up: stand still facing the target (a flyer drifts in slowly).
func _hold(enemy: Enemy, target: PlayerCharacter, delta: float) -> void:
	if enemy.flying:
		enemy.move_towards(target.global_position, 0.3, delta)
	else:
		enemy.stop()
		enemy.face(target.global_position, delta)
