class_name BossAttack
extends Node
## A boss attack building block (charge, slam...). Put it under the boss scene's "Attacks" node and give
## it an attack_name; a BossPhaseData lists the names its phase uses. The same script can be used twice
## with different numbers (the Giant Rat's "charge" and faster "charge_fast"). Spec: docs/systems/bosses.md.
## start / update run on the host; play_effect runs on every PC (the wind-up everyone sees).

## The name phases use, e.g. "charge".
@export var attack_name: StringName = &""
## Only starts when the target is this close (and at least min_range away).
@export var min_range: float = 0.0
@export var max_range: float = 30.0

var _finished: bool = true


## Host: can it start now? By default: the boss has a target within range.
func can_start(boss: Boss) -> bool:
	var target: PlayerCharacter = boss.get_target()
	if target == null:
		return false
	var distance: float = boss.flat_distance_to_target()
	return distance >= min_range and distance <= max_range


## Host: begin.
func start(_boss: Boss, _target: PlayerCharacter) -> void:
	_finished = false


## Host: every physics frame while it's the boss's attack. Call finish() when done.
func update(_boss: Boss, _delta: float) -> void:
	finish()


func is_finished() -> bool:
	return _finished


func finish() -> void:
	_finished = true


## Every PC: what everyone sees when it starts (a wind-up).
func play_effect(_boss: Boss) -> void:
	pass


## Shared helper: hurt every living player within `radius` of a point (host). Returns who was hit.
static func hit_players_near(boss: Boss, point: Vector3, radius: float, damage: float, damage_type: StringName,
		knockback: float, lift: float, already_hit: Array[int] = []) -> Array[int]:
	var hit: Array[int] = []
	for node: Node in boss.get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var player := node as PlayerCharacter
		if player == null or already_hit.has(player.player_id) or player.get_world_3d() != boss.get_world_3d():
			continue
		var health: HealthComponent = HealthComponent.of(player)
		if health == null or health.is_dead():
			continue
		var offset: Vector3 = player.global_position - point
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > radius or absf(offset.y) > 3.0:
			continue
		var info := DamageInfo.make(damage, damage_type, boss)
		info.hit_position = player.global_position
		info.knockback = flat.normalized() * knockback + Vector3.UP * lift
		var hurtbox: Node = player.get_node_or_null(NodePath(Hurtbox.NODE_NAME))
		Damage.hit(hurtbox if hurtbox != null else player, info)
		hit.append(player.player_id)
	return hit
