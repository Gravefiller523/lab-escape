extends ItemBehaviour
## Swing and hit what is in front of you (fists, crowbar, knife). Hits hurtboxes of enemies and props
## that can be hurt, and knocks loose props about. No friendly fire from melee (DEFAULT in the damage spec).


func use_host(user: PlayerCharacter, data: ItemBehaviourData, aim_origin: Vector3, aim_dir: Vector3,
		_item: ItemData, _slot_index: int) -> void:
	var melee := data as MeleeBehaviourData
	var mask: int = PhysicsLayers.bit(PhysicsLayers.HITBOXES) | PhysicsLayers.bit(PhysicsLayers.PROPS)
	var hit: Dictionary = find_in_reach_skipping_players(user, aim_origin, aim_dir, melee.reach, mask)
	if hit.is_empty():
		return
	var target: Node3D = hit["collider"]
	var info := DamageInfo.make(melee.damage, melee.damage_type, user)
	info.hit_position = hit["position"]
	info.knockback = aim_dir.normalized() * melee.knockback
	info.status_id = melee.status_id
	var prop: NetProp = NetProp.of(target)
	if prop != null:
		Props.apply_impulse(prop, aim_dir.normalized() * melee.knockback * maxf(prop.mass, 1.0) * 0.5)
		info.knockback = Vector3.ZERO
	Damage.hit(target, info)


## Like find_in_reach, but other players' hurtboxes don't count (melee doesn't hurt teammates).
static func find_in_reach_skipping_players(user: PlayerCharacter, aim_origin: Vector3, aim_dir: Vector3,
		reach: float, mask: int) -> Dictionary:
	var excluded: Array[RID] = []
	for node: Node in user.get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var other := node as PlayerCharacter
		var hurtbox := other.get_node_or_null(NodePath(Hurtbox.NODE_NAME)) as Hurtbox if other != null else null
		if hurtbox != null and other != user and other.get_world_3d() == user.get_world_3d():
			excluded.append(hurtbox.get_rid())
	return find_in_reach(user, aim_origin, aim_dir, reach, mask, 0.6, excluded)
