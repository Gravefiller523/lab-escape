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
## Where it was last physics frame (NEW 2026-10-29: hits are checked along the whole path, so fast throws
## can't fly through an enemy between two frames).
var _last_position: Vector3 = Vector3.INF


func setup(data: ThrowBehaviourData, thrower: PlayerCharacter) -> void:
	_data = data
	_thrower = thrower
	_thrower_id = thrower.player_id


func _ready() -> void:
	name = NODE_NAME
	var prop := get_parent() as NetProp
	if prop != null:
		# This throw's own damage counts, not the prop's impact damage (NEW 2026-10-29).
		prop.own_hit_damage = true


func _exit_tree() -> void:
	var prop := get_parent() as NetProp
	if prop != null:
		prop.own_hit_damage = false


func _physics_process(delta: float) -> void:
	var prop := get_parent() as NetProp
	if prop == null or _data == null or not multiplayer.is_server():
		queue_free()
		return
	_age += delta
	var from: Vector3 = _last_position if _last_position.is_finite() else prop.global_position
	_last_position = prop.global_position
	if not _hit_something:
		var target: Hurtbox = _hurtbox_along(prop, from, prop.global_position)
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


## CHANGED 2026-10-29: the first hurtbox anywhere on the path from `from` to `to` (checked every HIT_RADIUS
## metres), not only where the item is now.
func _hurtbox_along(prop: NetProp, from: Vector3, to: Vector3) -> Hurtbox:
	var steps: int = maxi(ceili(from.distance_to(to) / HIT_RADIUS), 1)
	for step: int in range(1, steps + 1):
		var found: Hurtbox = _touching_hurtbox(prop, from.lerp(to, float(step) / float(steps)))
		if found != null:
			return found
	return null


func _touching_hurtbox(prop: NetProp, at: Vector3) -> Hurtbox:
	var space: PhysicsDirectSpaceState3D = prop.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
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
