extends BossAttack
## Laser sweep (NEW 2026-11-12, roadmap WP13): the boss stops and shows a thin aiming line (the warning), then the
## line becomes a beam and the boss turns its whole body through an arc, dragging the beam across the arena.
## The beam is low: jump over it, or get out of its reach. Each player is hit at most once per sweep, and never
## through a wall. Because the boss itself turns (its facing is already synced), every PC sees the same sweep.

const BEAM_NODE: String = "LaserBeam"
const PLAYER_HALF_WIDTH: float = 0.4

@export var windup: float = 1.1
@export var sweep_seconds: float = 2.4
## The arc the beam covers, centred on where the target stood when the wind-up ended.
@export var sweep_degrees: float = 140.0
@export var beam_length: float = 22.0
## Height of the beam above the boss's feet. Lower than a jump (PlayerTuning.jump_height) so it can be hopped.
@export var beam_height: float = 0.45
## Half the beam's width for hits (metres); a player's own width is added.
@export var beam_half_width: float = 0.3
@export var damage: float = 18.0
@export var damage_type: StringName = &"fire"
@export var knockback: float = 5.0
@export var recover: float = 0.6
@export var beam_color: Color = Color(1.0, 0.15, 0.1)

var _time: float = 0.0
var _start_yaw: float = 0.0
var _locked: bool = false
var _hit: Array[int] = []


func start(boss: Boss, target: PlayerCharacter) -> void:
	super.start(boss, target)
	_time = 0.0
	_locked = false
	_hit.clear()


func update(boss: Boss, delta: float) -> void:
	_time += delta
	boss.stop()
	if _time < windup:
		var target: PlayerCharacter = boss.get_target()
		if target != null:
			boss.face(target.global_position, delta * 3.0)
		return
	if not _locked:
		_locked = true
		_start_yaw = boss.rotation.y + deg_to_rad(sweep_degrees) * 0.5
	var sweep_time: float = _time - windup
	if sweep_time <= sweep_seconds:
		boss.rotation.y = _start_yaw - deg_to_rad(sweep_degrees) * (sweep_time / maxf(sweep_seconds, 0.01))
		_hit.append_array(_hit_players_on_beam(boss))
		return
	if sweep_time >= sweep_seconds + recover:
		finish()


## Whether a point (a player's feet) is touched by the beam leaving `origin` (the boss's feet) along `forward`.
func beam_touches(origin: Vector3, forward: Vector3, feet: Vector3) -> bool:
	var offset: Vector3 = feet - origin
	if offset.y > beam_height or offset.y < beam_height - 2.2:
		return false
	var flat := Vector3(offset.x, 0.0, offset.z)
	var direction := Vector3(forward.x, 0.0, forward.z).normalized()
	var along: float = flat.dot(direction)
	if along < 0.5 or along > beam_length:
		return false
	return (flat - direction * along).length() <= beam_half_width + PLAYER_HALF_WIDTH


func _hit_players_on_beam(boss: Boss) -> Array[int]:
	var hit: Array[int] = []
	var origin: Vector3 = boss.global_position
	var forward: Vector3 = -boss.global_basis.z
	for node: Node in boss.get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var player := node as PlayerCharacter
		if player == null or _hit.has(player.player_id) or player.get_world_3d() != boss.get_world_3d():
			continue
		var health: HealthComponent = HealthComponent.of(player)
		if health == null or health.is_dead() or not beam_touches(origin, forward, player.global_position):
			continue
		var muzzle: Vector3 = origin + Vector3.UP * beam_height
		var query := PhysicsRayQueryParameters3D.create(muzzle,
			Vector3(player.global_position.x, muzzle.y, player.global_position.z), PhysicsLayers.bit(PhysicsLayers.WORLD))
		if not boss.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var info := DamageInfo.make(damage, damage_type, boss)
		info.hit_position = player.global_position
		info.knockback = forward * knockback + Vector3.UP * knockback * 0.5
		var hurtbox: Node = player.get_node_or_null(NodePath(Hurtbox.NODE_NAME))
		Damage.hit(hurtbox if hurtbox != null else player, info)
		hit.append(player.player_id)
	return hit


## Every PC: a thin aiming line during the wind-up, then the full beam for the sweep. It hangs off the boss, so
## it turns with it.
func play_effect(boss: Boss) -> void:
	var old: Node = boss.get_node_or_null(NodePath(BEAM_NODE))
	if old != null:
		old.free()
	var beam := MeshInstance3D.new()
	beam.name = BEAM_NODE
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, beam_length)
	var material := StandardMaterial3D.new()
	material.albedo_color = beam_color
	material.emission_enabled = true
	material.emission = beam_color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = material
	beam.mesh = box
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0.0, beam_height, -beam_length * 0.5)
	beam.scale = Vector3(0.04, 0.04, 1.0)
	boss.add_child(beam)
	var wide: float = beam_half_width * 2.0
	var tween: Tween = beam.create_tween()
	tween.tween_interval(windup)
	tween.tween_property(beam, "scale", Vector3(wide, wide * 0.6, 1.0), 0.08)
	tween.tween_interval(maxf(sweep_seconds - 0.08, 0.0))
	tween.tween_property(beam, "scale", Vector3(0.01, 0.01, 1.0), 0.12)
	tween.tween_callback(beam.queue_free)
