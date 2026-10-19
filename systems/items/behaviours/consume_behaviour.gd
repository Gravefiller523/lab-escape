extends ItemBehaviour
## Drink or eat it (energy drink: speed boost). Heals, gives a status, and uses one use up.


func use_host(user: PlayerCharacter, data: ItemBehaviourData, _aim_origin: Vector3, _aim_dir: Vector3,
		_item: ItemData, slot_index: int) -> void:
	var consume := data as ConsumeBehaviourData
	var health: HealthComponent = HealthComponent.of(user)
	if health != null and consume.heal_amount > 0.0:
		health.heal(consume.heal_amount)
	var statuses: StatusEffectComponent = StatusEffectComponent.of(user)
	if statuses != null and not consume.status_id.is_empty():
		statuses.apply(consume.status_id, user.player_id)
	var inventory: InventoryComponent = InventoryComponent.of(user)
	if inventory != null and slot_index >= 0:
		inventory.spend_use(slot_index)
