extends UpgradeEffect
## Extra inventory slots -> InventoryComponent.set_bonus_slots (host; the inventory syncs itself).


func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void:
	var inventory: InventoryComponent = InventoryComponent.of(player)
	if inventory != null and player.multiplayer.is_server():
		inventory.set_bonus_slots(source_id, (data as SlotEffectData).extra_slots)


func remove(player: PlayerCharacter, _data: UpgradeEffectData, source_id: StringName) -> void:
	var inventory: InventoryComponent = InventoryComponent.of(player)
	if inventory != null and player.multiplayer.is_server():
		inventory.clear_bonus_slots(source_id)
