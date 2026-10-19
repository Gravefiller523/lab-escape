class_name ThrownItem
extends Node
## Host only: rides along on a thrown item pickup for a few seconds. The first hurtbox it touches takes
## the throw's damage and status; when it hits something hard (or after that hit) a breaks_on_impact
## item is gone. Not networked: damage and despawning sync through their own systems.

const NODE_NAME: String = "Thrown"
const HIT_RADIUS: float = 0.4
## Seconds the throw counts for.
const LIFETIME: float = 3.0
## The thrower's own hurtbox is ignored this long (the item starts next to them).
const SELF_GRACE: float = 0.4
## Speed lost in one physics frame that means "it hit something" (fraction of the speed before).
const IMPACT_SPEED_DROP: float = 0.5
const IMPACT_MIN_SPEED: float = 2.0

var _data: ThrowBehaviourData
var _thrower: PlayerCharacter
var _thrower_id: int = 0
var _age: float = 0.0
var _last_speed: float = 0.0
var _hit_something: bool = false


func setup(data: ThrowBehaviourData, thrower: PlayerCharacter) -> void:
	_data = data
	_thrower = thrower
	_thrower_id = thrower.player_id


func _ready() -> void:
	name = NODE_NAME


func _physics_process(delta: float) -> void:
	var prop := get_parent() as NetProp
	if prop == null or _data == null or not multiplayer.is_server():
		queue_free()
		return
	_age += delta
	if not _hit_something:
		var target: Hurtbox = _touching_hurtbox(prop)
		if target != null:
			_hit_something = true
			var info := DamageInfo.make(_data.damage, _data.damage_type, prop)
			info.source_player_id = _thrower_id
			info.hit_position = prop.global_position
			info.status_id = _data.status_id
			info.knockback = prop.linear_velocity * 0.3
			Damage.hit(target, info)
	var speed: float = prop.linear_velocity.length()
	var impact: bool = _age > 0.05 and _last_speed > IMPACT_MIN_SPEED and speed < _last_speed * IMPACT_SPEED_DROP
	_last_speed = speed
	if (impact or _hit_something) and _data.breaks_on_impact:
		Props.despawn(prop)
		return
	if _age > LIFETIME or impact:
		queue_free()


func _touching_hurtbox(prop: NetProp) -> Hurtbox:
	var space: PhysicsDirectSpaceState3D = prop.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, prop.global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = PhysicsLayers.bit(PhysicsLayers.HITBOXES)
	for hit: Dictionary in space.intersect_shape(query, 8):
		var hurtbox := hit["collider"] as Hurtbox
		if hurtbox == null:
			continue
		if _age < SELF_GRACE and is_instance_valid(_thrower) and hurtbox.get_parent() == _thrower:
			continue
		return hurtbox
	return null
