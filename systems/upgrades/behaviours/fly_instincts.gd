extends Node
## NEW 2026-11-12 (roadmap WP14): the Fly mutation's two instincts (from the brainstorm). Host only.
## - Flies love you: you carry a "fly_player" lure, so enemy flies within `fly_radius` notice you from afar and go
##   for you rather than your friends.
## - You love trash: within `trash_radius` of anything tagged as trash (a "trash" lure) you heal
##   `heal_per_second`.
## Params: fly_radius (14), trash_radius (4), heal_per_second (1.5). Added under the player's body by the upgrade's
## BehaviourEffectData.

const FLY_LURE: StringName = &"fly_player"
const TRASH_LURE: StringName = &"trash"

var _body: PlayerCharacter
var _lure: Lure


func _ready() -> void:
	_body = get_parent() as PlayerCharacter


func _exit_tree() -> void:
	if _lure != null and is_instance_valid(_lure):
		_lure.queue_free()
	_lure = null


## Is there trash close enough to enjoy?
func is_near_trash() -> bool:
	if _body == null:
		return false
	var reach: float = UpgradeBehaviourParams.number(self, "trash_radius", 4.0)
	for lure: Lure in Enemies.get_lures(TRASH_LURE):
		if lure.is_inside_tree() and lure.global_position.distance_to(_body.global_position) <= reach:
			return true
	return false


func _physics_process(delta: float) -> void:
	if _body == null or not multiplayer.is_server():
		return
	if _lure == null or not is_instance_valid(_lure):
		_lure = Enemies.attach_lure(_body, FLY_LURE, UpgradeBehaviourParams.number(self, "fly_radius", 14.0))
	var health: HealthComponent = HealthComponent.of(_body)
	if health == null or health.is_dead() or health.get_current() >= health.get_max():
		return
	if is_near_trash():
		health.heal(UpgradeBehaviourParams.number(self, "heal_per_second", 1.5) * delta)
