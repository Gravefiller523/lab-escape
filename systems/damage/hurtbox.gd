class_name Hurtbox
extends Area3D
## An area that receives hits (on PhysicsLayers.HITBOXES). Weapons and attacks find it with a shape
## query or ray and call receive_hit (host only). Several hurtboxes can share one HealthComponent, each
## with its own multiplier (weak spots). Spec: docs/systems/damage.md.

const NODE_NAME: String = "Hurtbox"

## The health this hurtbox hurts. Empty = the HealthComponent of the node it is on.
@export var health: HealthComponent
## Damage x this. Above 1 for weak spots.
@export var multiplier: float = 1.0


func _ready() -> void:
	collision_layer = PhysicsLayers.bit(PhysicsLayers.HITBOXES)
	collision_mask = 0
	monitoring = false
	monitorable = true


## The health this hurtbox hurts (null if none).
func get_health() -> HealthComponent:
	if health == null:
		health = HealthComponent.of(get_parent())
	return health


## Host: apply a hit (times the multiplier) to the health.
func receive_hit(info: DamageInfo) -> void:
	var target: HealthComponent = get_health()
	if target == null or info == null:
		return
	target.apply_damage(info.scaled(multiplier) if not is_equal_approx(multiplier, 1.0) else info)
