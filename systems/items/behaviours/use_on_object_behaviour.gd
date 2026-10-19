extends ItemBehaviour
## Use the item on something in the world: pour the energy drink on a mutated plant ("water"), pry with
## the crowbar ("pry"). The thing needs a UseTarget that accepts the tag.


func use_host(user: PlayerCharacter, data: ItemBehaviourData, aim_origin: Vector3, aim_dir: Vector3,
		_item: ItemData, slot_index: int) -> void:
	var use := data as UseOnObjectBehaviourData
	var mask: int = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.INTERACTABLES) \
		| PhysicsLayers.bit(PhysicsLayers.PROPS)
	var space: PhysicsDirectSpaceState3D = user.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + aim_dir.normalized() * use.reach, mask,
		[user.get_rid()])
	query.collide_with_areas = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit["collider"] as Node
	var target: UseTarget = UseTarget.of(collider)
	if target == null or not target.try_use(use.interaction_tag, user.player_id):
		return
	var inventory: InventoryComponent = InventoryComponent.of(user)
	if use.spends_use and inventory != null and slot_index >= 0:
		inventory.spend_use(slot_index)
