extends BossAttack
## Charge: the boss stops, lines up on the target, then runs straight at it. Anyone in its path is hit
## and thrown (once per charge). It stops when it hits a wall or runs out of time.

@export var windup: float = 0.7
@export var speed: float = 10.0
@export var duration: float = 1.4
@export var damage: float = 20.0
@export var damage_type: StringName = &"blunt"
@export var knockback: float = 12.0
@export var hit_radius: float = 1.6

var _time: float = 0.0
var _direction: Vector3 = Vector3.FORWARD
var _hit: Array[int] = []


func start(boss: Boss, target: PlayerCharacter) -> void:
	super.start(boss, target)
	_time = 0.0
	_hit.clear()
	_direction = -boss.global_basis.z


func update(boss: Boss, delta: float) -> void:
	_time += delta
	var target: PlayerCharacter = boss.get_target()
	if _time < windup:
		boss.stop()
		if target != null:
			boss.face(target.global_position, delta * 3.0)
			var toward: Vector3 = target.global_position - boss.global_position
			toward.y = 0.0
			if toward.length() > 0.1:
				_direction = toward.normalized()
		return
	boss.velocity.x = _direction.x * speed
	boss.velocity.z = _direction.z * speed
	_hit.append_array(hit_players_near(boss, boss.global_position, hit_radius, damage, damage_type, knockback,
		knockback * 0.4, _hit))
	if _time > windup + duration or (_time > windup + 0.25 and boss.is_on_wall()):
		boss.stop()
		finish()


func play_effect(boss: Boss) -> void:
	var mesh := boss.get_node_or_null(^"Mesh") as Node3D
	if mesh == null:
		return
	# Crouches back before running.
	var tween: Tween = mesh.create_tween()
	tween.tween_property(mesh, "rotation:x", deg_to_rad(12.0), windup * 0.8)
	tween.tween_property(mesh, "rotation:x", 0.0, 0.15)
