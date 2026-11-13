extends BossAttack
## Slam: the boss rears up, then crashes down. Every player within the radius is hurt and thrown up
## and away. Only used when someone is close.

@export var windup: float = 0.9
@export var radius: float = 4.5
@export var damage: float = 15.0
@export var damage_type: StringName = &"blunt"
@export var knockback: float = 8.0
@export var recover: float = 0.5
## NEW 2026-11-12 (roadmap WP13): a status effect everyone it hits gets (the Mushroom Man's spore slam), and the
## colour of the puff it throws up when it lands (see-through = no puff).
@export var status_id: StringName = &""
@export var puff_color: Color = Color(0, 0, 0, 0)

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
		hit_players_near(boss, boss.global_position, radius, damage, damage_type, knockback, knockback * 0.8, [], status_id)
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
	if puff_color.a > 0.0:
		var puff: Callable = func() -> void:
			Effects.burst(boss.get_parent(), boss.global_position + Vector3.UP * 0.3, puff_color, 40, radius * 1.5,
				0.25, 0.9)
		tween.tween_callback(puff)
	tween.tween_property(mesh, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.2)
