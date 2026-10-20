extends EnemyState
## Go after the target as a group (rats, flies): like chase, but each one circles in from its own side
## and keeps a little space from the others, so a pack surrounds you instead of queueing up.

@export var spread: float = 1.2
@export var separation: float = 0.8

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
		return &"idle"
	if enemy.data != null and enemy.flat_distance_to_target() <= enemy.data.attack_range and enemy.has_state(&"attack_melee"):
		return &"attack_melee"
	_angle += delta * 0.8
	var side := Vector3(cos(_angle), 0.0, sin(_angle)) * spread
	var goal: Vector3 = target.global_position + side * clampf(enemy.flat_distance_to_target() / 4.0, 0.0, 1.0)
	goal += _away_from_pack(enemy)
	enemy.move_towards(goal, 1.0, delta)
	return &""


func _away_from_pack(enemy: Enemy) -> Vector3:
	var push := Vector3.ZERO
	for node: Node in enemy.get_tree().get_nodes_in_group(Enemy.GROUP):
		var other := node as Enemy
		if other == null or other == enemy or other.is_dead():
			continue
		var offset: Vector3 = enemy.global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > 0.01 and distance < separation:
			push += offset.normalized() * (separation - distance)
	return push
