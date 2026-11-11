extends EnemyState
## Shoot at the target from a distance (NEW 2026-11-11, roadmap WP9). Uses the enemy's EnemyData.ranged_attack:
## keep between its min_range and max_range (walk closer or back off, if it can move at all), wind up (the same
## growl and crouch as a melee attack, so players get a warning), fire a burst of `shots`, then wait out
## attack_cooldown and go again while it can see you. Lost sight: chase if it can, otherwise search or idle.
## Turrets are enemies with move_speed 0 and only idle + attack_ranged. Host only.

enum Step { POSITION, WINDUP, FIRE }

## Shots aim this high above the target's feet.
const CHEST_HEIGHT: float = 1.1

var _step: Step = Step.POSITION
var _left: float = 0.0
var _shots_left: int = 0


func can_enter(enemy: Enemy) -> bool:
	return enemy.get_target() != null and enemy.data != null and enemy.data.ranged_attack != null


func enter(_enemy: Enemy) -> void:
	_step = Step.POSITION


func can_interrupt(_enemy: Enemy) -> bool:
	return _step == Step.POSITION


func physics_update(enemy: Enemy, delta: float) -> StringName:
	var attack: RangedAttackData = enemy.data.ranged_attack if enemy.data != null else null
	if attack == null:
		return enemy.pursuit_state()
	if _step == Step.POSITION and should_flee(enemy):
		return &"flee"
	var target: PlayerCharacter = enemy.update_target()
	if target == null:
		return enemy.lose_target()
	if _step == Step.POSITION:
		if not enemy.can_see_target():
			return &"chase" if enemy.has_state(&"chase") else enemy.lose_target()
		var distance: float = enemy.flat_distance_to_target()
		var mobile: bool = enemy.data.move_speed > 0.0
		if mobile and distance > attack.max_range:
			enemy.move_towards(target.global_position, 1.0, delta)
			return &""
		if mobile and distance < attack.min_range:
			var away: Vector3 = enemy.global_position + (enemy.global_position - target.global_position).normalized() * 2.0
			enemy.move_towards(away, 1.0, delta)
			return &""
		enemy.stop()
		enemy.face(target.global_position, delta)
		if distance > attack.max_range or not enemy.attack_ready():
			return &""
		_step = Step.WINDUP
		_left = Config.feel.ai.attack_windup
		enemy.begin_windup()
		return &""
	enemy.stop()
	enemy.face(target.global_position, delta)
	_left -= delta
	if _left > 0.0:
		return &""
	if _step == Step.WINDUP:
		_step = Step.FIRE
		_shots_left = attack.shots
	enemy.fire_at(target.global_position + Vector3.UP * CHEST_HEIGHT)
	_shots_left -= 1
	_left = attack.shot_interval
	if _shots_left <= 0:
		enemy.start_attack_cooldown()
		_step = Step.POSITION
	return &""
