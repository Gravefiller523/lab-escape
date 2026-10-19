extends ItemBehaviour
## Throw the item (potted plant, hot coffee). One leaves the inventory and flies as its world pickup; the
## first thing it hits takes the damage (and status). Thrown things CAN hurt teammates (DEFAULT, it's
## funny). breaks_on_impact items (the coffee pot) are gone after the first hit; others can be picked up.

## Thrown things start this far in front of the eyes (metres).
const START_DISTANCE: float = 0.7


func use_host(user: PlayerCharacter, data: ItemBehaviourData, aim_origin: Vector3, aim_dir: Vector3,
		item: ItemData, slot_index: int) -> void:
	var throw := data as ThrowBehaviourData
	var inventory: InventoryComponent = InventoryComponent.of(user)
	if inventory == null or slot_index < 0:
		return
	var taken: InventorySlot = inventory.take_one(slot_index)
	if taken == null:
		return
	var forward: Vector3 = aim_dir.normalized()
	var at := Transform3D(Basis.IDENTITY, aim_origin + forward * START_DISTANCE)
	var prop: NetProp = Props.spawn_item(item.id, at, taken.uses_left)
	if prop == null:
		return
	var tracker := ThrownItem.new()
	tracker.setup(throw, user)
	prop.add_child(tracker)
	Props.apply_impulse(prop, forward * throw.throw_force * maxf(prop.mass, 0.1))
