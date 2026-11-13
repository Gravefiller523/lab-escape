extends BossAttack
## Projectile burst (NEW 2026-11-12, roadmap WP13): the boss stops, winds up, then fires a fan of its projectiles
## at the target, one volley after another. With fan_degrees 360 it is a ring in every direction. The Mushroom
## Man's spore volley and spore ring and Robobrain's rocket volley are all this script with different numbers.
## `projectile` is the same RangedAttackData an enemy's ranged attack uses (speed, gravity, damage, status, colour);
## its `shots` is the number of volleys and `shot_interval` the pause between them.

@export var projectile: RangedAttackData
## Seconds the boss holds still before the first volley (the warning).
@export var windup: float = 0.8
## Projectiles in each volley.
@export_range(1, 40) var shots_per_volley: int = 5
## How wide the volley spreads (degrees). 360 = a ring all the way round.
@export_range(0.0, 360.0) var fan_degrees: float = 40.0
## Seconds it stands still after the last volley.
@export var recover: float = 0.5
## How high above its feet the shots leave.
@export var muzzle_height: float = 1.4
## Shots aim this high above the target's feet.
@export var aim_height: float = 1.1

var _time: float = 0.0
var _volleys_left: int = 0
var _next_volley_at: float = 0.0
var _done_at: float = 0.0


func get_projectile() -> RangedAttackData:
	return projectile


func can_start(boss: Boss) -> bool:
	return projectile != null and super.can_start(boss)


func start(boss: Boss, target: PlayerCharacter) -> void:
	super.start(boss, target)
	_time = 0.0
	_volleys_left = maxi(projectile.shots, 1)
	_next_volley_at = windup
	_done_at = 0.0


func update(boss: Boss, delta: float) -> void:
	_time += delta
	boss.stop()
	var target: PlayerCharacter = boss.get_target()
	if target != null:
		boss.face(target.global_position, delta * 2.0)
	if _volleys_left > 0:
		if _time >= _next_volley_at:
			_volleys_left -= 1
			_next_volley_at = _time + maxf(projectile.shot_interval, 0.05)
			_done_at = _time + recover
			_fire_volley(boss, target)
		return
	if _time >= _done_at:
		finish()


## One fan (or ring) of shots, centred on the target (straight ahead if there is none).
func _fire_volley(boss: Boss, target: PlayerCharacter) -> void:
	var from: Vector3 = boss.global_position + Vector3.UP * muzzle_height
	var forward: Vector3 = -boss.global_basis.z
	var distance: float = clampf(max_range * 0.5, 3.0, 12.0)
	var height: float = boss.global_position.y + aim_height
	if target != null:
		var flat: Vector3 = target.global_position - boss.global_position
		height = target.global_position.y + aim_height
		flat.y = 0.0
		if flat.length() > 0.5:
			forward = flat.normalized()
			distance = flat.length()
	var ring: bool = fan_degrees >= 359.0
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * projectile.gravity_scale
	var spread: float = deg_to_rad(projectile.spread_degrees)
	for index: int in shots_per_volley:
		var turn: float = 0.0
		if ring:
			turn = TAU * float(index) / float(shots_per_volley)
		elif shots_per_volley > 1:
			turn = deg_to_rad(fan_degrees) * (float(index) / float(shots_per_volley - 1) - 0.5)
		turn += boss.rng.randf_range(-spread, spread)
		var direction: Vector3 = forward.rotated(Vector3.UP, turn)
		var point := Vector3(boss.global_position.x, height, boss.global_position.z) + direction * distance
		# A lobbed shot aims above its landing point by how far it falls on the way (the same as Enemy.fire_at).
		var flight_seconds: float = from.distance_to(point) / maxf(projectile.projectile_speed, 0.1)
		point += Vector3.UP * 0.5 * gravity * flight_seconds * flight_seconds
		boss.fire_attack_projectile(self, from, (point - from).normalized() * projectile.projectile_speed)


func play_effect(boss: Boss) -> void:
	var mesh := boss.get_node_or_null(^"Mesh") as Node3D
	if mesh == null:
		return
	# Swells up before it fires.
	var tween: Tween = mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3(1.12, 1.12, 1.12), windup * 0.9)
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.15)
