extends UpgradeEffect
## A model on the body (wings, tentacles, a robot arm) at a named attach point. Every PC adds it;
## your own body's is hidden from you like the rest of your body.

const PREFIX: String = "Upgrade_"


func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	var visual := data as VisualAttachmentEffectData
	if visual.scene == null:
		return
	var point: Node3D = player.get_attach_point(visual.attach_point)
	var holder: Node3D = point if point != null else player
	var model := visual.scene.instantiate() as Node3D
	if model == null:
		return
	model.name = _node_name(source_id)
	model.visible = not player.is_local()
	holder.add_child(model)


func remove(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	var visual := data as VisualAttachmentEffectData
	var point: Node3D = player.get_attach_point(visual.attach_point)
	var holder: Node3D = point if point != null else player
	var model: Node = holder.get_node_or_null(NodePath(_node_name(source_id)))
	if model != null:
		holder.remove_child(model)
		model.queue_free()


static func _node_name(source_id: StringName) -> String:
	return PREFIX + String(source_id).replace("#", "_")
