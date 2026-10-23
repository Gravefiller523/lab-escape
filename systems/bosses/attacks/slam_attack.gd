extends BossAttack
## Slam: the boss rears up, then crashes down. Every player within the radius is hurt and thrown up
## and away. Only used when someone is close.

@export var windup: float = 0.9
@export var radius: float = 4.5
@export var damage: float = 15.0
@export var damage_type: StringName = &"blunt"
@export var knockback: float = 8.0
@export var recover: float = 0.5

var _time: float = 0.0
var _slammed: bool = false


func start(boss: Boss, target: PlayerCharacter) -> void:
	super.start(boss, target)
	_time = 0.0
	_slammed = false


func update(boss: Boss, delta: float) -> void:
	_time += delta
	boss.stop()
	if not _slammed and _time >= windup:
		_slammed = true
		hit_players_near(boss, boss.global_position, radius, damage, damage_type, knockback, knockback * 0.8)
	if _time >= windup + recover:
		finish()


func play_effect(boss: Boss) -> void:
	var mesh := boss.get_node_or_null(^"Mesh") as Node3D
	if mesh == null:
		return
	var rest: Vector3 = mesh.position
	var tween: Tween = mesh.create_tween()
	tween.tween_property(mesh, "position", rest + Vector3.UP * 1.0, windup * 0.9)
	tween.tween_property(mesh, "position", rest, windup * 0.1)
	tween.tween_property(mesh, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.2)
