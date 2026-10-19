class_name ItemBehaviour
extends RefCounted
## Runtime building block for one kind of ItemBehaviourData. Found by file name:
## MeleeBehaviourData (melee_behaviour_data.gd) -> systems/items/behaviours/melee_behaviour.gd.
## A new kind of behaviour = a new data class in core/data/items/behaviours/ + a runtime file here.
## Spec: docs/systems/items.md.

const BEHAVIOUR_FOLDER: String = "res://systems/items/behaviours/"

static var _cache: Dictionary[String, ItemBehaviour] = {}


## The runtime piece for a behaviour data resource (null if its file is missing).
static func for_data(data: ItemBehaviourData) -> ItemBehaviour:
	if data == null or data.get_script() == null:
		return null
	var data_file: String = (data.get_script() as Script).resource_path.get_file()
	var runtime_path: String = BEHAVIOUR_FOLDER + data_file.trim_suffix("_data.gd") + ".gd"
	if not _cache.has(runtime_path):
		if not ResourceLoader.exists(runtime_path):
			push_error("ItemBehaviour: no runtime file %s for %s." % [runtime_path, data_file])
			return null
		var script := load(runtime_path) as GDScript
		_cache[runtime_path] = script.new() as ItemBehaviour
	return _cache[runtime_path]


## Every PC and the host: can it be used now (besides the cooldown)?
func can_use(_user: PlayerCharacter, _data: ItemBehaviourData) -> bool:
	return true


## The owner's PC, at once: feedback only (the swing is played by HeldItemController).
func use_local(_user: PlayerCharacter, _data: ItemBehaviourData) -> void:
	pass


## Host: the real effect. CHANGED 2026-10-19: also gets the item and the inventory slot it is in
## (-1 for fists).
func use_host(_user: PlayerCharacter, _data: ItemBehaviourData, _aim_origin: Vector3, _aim_dir: Vector3,
		_item: ItemData, _slot_index: int) -> void:
	pass


## Shared helper: the closest thing a sweep in front of the player touches on `mask` (areas included),
## that the player can see (no wall in between). Skips the user's own body and hurtbox.
static func find_in_reach(user: PlayerCharacter, aim_origin: Vector3, aim_dir: Vector3, reach: float,
		mask: int, width: float = 0.6, also_skip: Array[RID] = []) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = user.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(width, width, reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collide_with_areas = true
	query.collision_mask = mask
	var forward: Vector3 = aim_dir.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	query.transform = Transform3D(Basis.looking_at(forward, up), aim_origin + forward * reach / 2.0)
	var skip: Array[RID] = _own_rids(user)
	skip.append_array(also_skip)
	query.exclude = skip
	var best: Dictionary = {}
	var best_distance: float = INF
	for hit: Dictionary in space.intersect_shape(query, 32):
		var collider: Object = hit["collider"]
		var node := collider as Node3D
		if node == null:
			continue
		var distance: float = aim_origin.distance_to(node.global_position)
		if distance >= best_distance or not _can_see(space, user, aim_origin, node):
			continue
		best_distance = distance
		best = {"collider": node, "position": node.global_position}
	return best


static func _own_rids(user: PlayerCharacter) -> Array[RID]:
	var rids: Array[RID] = [user.get_rid()]
	var hurtbox := user.get_node_or_null(NodePath(Hurtbox.NODE_NAME)) as Hurtbox
	if hurtbox != null:
		rids.append(hurtbox.get_rid())
	return rids


## Nothing solid (world) between the eyes and the target.
static func _can_see(space: PhysicsDirectSpaceState3D, user: PlayerCharacter, from: Vector3, node: Node3D) -> bool:
	var to: Vector3 = node.global_position
	if node is Hurtbox:
		to += Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.bit(PhysicsLayers.WORLD), _own_rids(user))
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	var blocker: Object = hit["collider"]
	return blocker == node or (blocker is Node and (blocker as Node).is_ancestor_of(node))
