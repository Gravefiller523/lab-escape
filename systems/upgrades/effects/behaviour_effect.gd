extends UpgradeEffect
## A special rule no other piece covers: adds behaviour_scene's root under the player while held.
## The node gets its params as metadata "params".

const PREFIX: String = "UpgradeBehaviour_"


func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	var behaviour := data as BehaviourEffectData
	if behaviour.behaviour_scene == null:
		return
	var node: Node = behaviour.behaviour_scene.instantiate()
	node.name = PREFIX + String(source_id).replace("#", "_")
	node.set_meta(&"params", behaviour.params)
	player.add_child(node)


func remove(player: PlayerCharacter, _data: UpgradeEffectData, source_id: StringName) -> void:
	var node: Node = player.get_node_or_null(NodePath(PREFIX + String(source_id).replace("#", "_")))
	if node != null:
		player.remove_child(node)
		node.queue_free()
