extends ItemBehaviour
## Leave a lure where the player points (the laser pointer's dot). The host finds the first wall, floor or prop
## along the aim and asks the Enemies autoload to put the lure there for everyone; clicking again moves it.

## The dot sits this far off the surface, so it isn't buried in the wall.
const SURFACE_OFFSET: float = 0.08


func use_host(user: PlayerCharacter, data: ItemBehaviourData, aim_origin: Vector3, aim_dir: Vector3,
		_item: ItemData, _slot_index: int) -> void:
	var lure := data as LureBehaviourData
	if lure == null:
		return
	var mask: int = PhysicsLayers.bit(PhysicsLayers.WORLD) | PhysicsLayers.bit(PhysicsLayers.PROPS)
	var query := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + aim_dir.normalized() * lure.reach, mask,
		[user.get_rid()])
	var hit: Dictionary = user.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var spot: Vector3 = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * SURFACE_OFFSET
	Enemies.place_lure("%s_%d" % [lure.lure_kind, user.player_id], lure.lure_kind, spot, lure.radius, lure.seconds,
		lure.dot_color)
