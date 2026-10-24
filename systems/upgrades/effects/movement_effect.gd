extends UpgradeEffect
## Movement changes (speed, jump, gravity, height, movement mode) -> PlayerMovement.set_modifier.


func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	player.get_movement().set_modifier(source_id, data as MovementEffectData)
	player.apply_height()


func remove(player: PlayerCharacter, _data: UpgradeEffectData, source_id: StringName) -> void:
	player.get_movement().remove_modifier(source_id)
	player.apply_height()
