extends Node
## NEW 2026-11-12 (roadmap WP10): the Spore Cough mutation's rule. Host: every so often you cough a cloud of spores
## and every enemy close by gets a sneezing fit (a status that stops it moving for a moment). Params: interval (8 s),
## radius (4 m), status_id ("status_sneezing"). Added under the player's body by the upgrade.

var _body: PlayerCharacter
var _left: float = 0.0


func _ready() -> void:
	_body = get_parent() as PlayerCharacter
	_left = UpgradeBehaviourParams.number(self, "interval", 8.0)


func _physics_process(delta: float) -> void:
	if _body == null or not multiplayer.is_server() or _body.is_ghost():
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = UpgradeBehaviourParams.number(self, "interval", 8.0)
	cough()


## Host: cough now. Returns how many enemies started sneezing.
func cough() -> int:
	var radius: float = UpgradeBehaviourParams.number(self, "radius", 4.0)
	var status_id := StringName(UpgradeBehaviourParams.text(self, "status_id", "status_sneezing"))
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or enemy.global_position.distance_to(_body.global_position) > radius:
			continue
		var statuses: StatusEffectComponent = StatusEffectComponent.of(enemy)
		if statuses != null:
			statuses.apply(status_id, _body.player_id)
			count += 1
	return count
