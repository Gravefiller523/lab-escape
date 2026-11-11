class_name EnemyProjectile
extends Node3D
## A shot from an enemy's ranged attack (NEW 2026-11-11, roadmap WP9). Every PC flies its own copy from the same
## start and velocity (Enemy._fire_rpc), so they match without syncing positions; only the host's copy deals damage.
## Each step it checks the line it travelled, so a fast shot can't skip through a wall or a player. It stops at
## the first wall, prop or player it touches. Grey box: a coloured ball. Spec: docs/systems/enemies.md.

var attack: RangedAttackData
var velocity: Vector3 = Vector3.ZERO
## The enemy that fired it (may be gone by the time it lands), for kill credit and so it never hits itself.
var shooter: Node
var _age: float = 0.0
var _gravity: float = 9.8


## Sets it up before it goes into the tree.
func launch(from: Vector3, start_velocity: Vector3, data: RangedAttackData, by: Node) -> void:
	position = from
	velocity = start_velocity
	attack = data
	shooter = by


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var ball := MeshInstance3D.new()
	ball.name = "Ball"
	var sphere := SphereMesh.new()
	var radius: float = attack.projectile_radius if attack != null else 0.15
	sphere.radius = radius
	sphere.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = attack.projectile_color if attack != null else Color.WHITE
	material.emission_enabled = true
	material.emission = material.albedo_color
	sphere.material = material
	ball.mesh = sphere
	add_child(ball)


func _physics_process(delta: float) -> void:
	if attack == null:
		queue_free()
		return
	_age += delta
	if _age >= attack.lifetime:
		queue_free()
		return
	velocity.y -= _gravity * attack.gravity_scale * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to,
		PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PLAYERS)
		| PhysicsLayers.bit(PhysicsLayers.PROPS))
	query.hit_back_faces = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return
	global_position = hit["position"]
	_on_hit(hit["collider"] as Node)
	queue_free()


func _on_hit(collider: Node) -> void:
	if not multiplayer.is_server():
		return
	var player: PlayerCharacter = PlayerCharacter.of(collider) if collider != null else null
	if player == null or player.is_ghost():
		return
	var info := DamageInfo.make(attack.damage, attack.damage_type,
		shooter if shooter != null and is_instance_valid(shooter) else null)
	info.status_id = attack.status_id
	info.hit_position = global_position
	info.knockback = velocity.normalized() * 0.5
	var hurtbox: Node = player.get_node_or_null(NodePath(Hurtbox.NODE_NAME))
	Damage.hit(hurtbox if hurtbox != null else player, info)
