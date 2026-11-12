extends Node
## NEW 2026-11-12 (roadmap WP10): the Thorns mutation's rule. Host: an enemy that hurts you up close (a bite, a claw,
## a lash) takes damage back. Params: damage (6), range (3 m). Added under the player's body by the upgrade.

var _body: PlayerCharacter


func _ready() -> void:
	_body = get_parent() as PlayerCharacter
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _on_damage_dealt(target: Node, _amount: float, _damage_type: StringName, source: Node) -> void:
	if _body == null or not multiplayer.is_server() or PlayerCharacter.of(target) != _body:
		return
	var enemy := source as Enemy
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return
	if enemy.global_position.distance_to(_body.global_position) > UpgradeBehaviourParams.number(self, "range", 3.0):
		return
	var info := DamageInfo.make(UpgradeBehaviourParams.number(self, "damage", 6.0), &"sharp", _body)
	info.source_player_id = _body.player_id
	info.hit_position = enemy.global_position
	Damage.hit(enemy, info)
