class_name CosmeticDresser
extends Node
## Puts a player's cosmetics on their body (NEW 2026-11-13, roadmap WP17). A child of every PlayerCharacter on every
## PC (the Cosmetics autoload adds it). refresh() rebuilds what shows from the player's loadout: each worn cosmetic's
## model goes on its slot's attach point (CosmeticsService.ATTACH_POINTS); a mutation listed in the cosmetic's
## mutation_variants swaps in that model; a slot an upgrade hides (Slug: shoes) shows nothing. Your own cosmetics
## are hidden from you like the rest of your body (you see them in the closet's preview).

const NODE_NAME: String = "CosmeticDresser"
const MODEL_PREFIX: String = "Cosmetic_"

var _body: PlayerCharacter


func _ready() -> void:
	name = NODE_NAME
	_body = get_parent() as PlayerCharacter


## The cosmetic models on the body now, by slot (tests).
func get_shown() -> Dictionary[StringName, Node3D]:
	var shown: Dictionary[StringName, Node3D] = {}
	if _body == null:
		return shown
	for slot: StringName in CosmeticsService.SLOTS:
		var point: Node3D = _point_for(slot)
		var model := point.get_node_or_null(NodePath(MODEL_PREFIX + String(slot))) as Node3D if point != null else null
		if model != null and not model.is_queued_for_deletion():
			shown[slot] = model
	return shown


func refresh() -> void:
	if _body == null or not is_inside_tree():
		return
	var loadout: Dictionary = Cosmetics.get_loadout(_body.player_id)
	var hidden: PackedStringArray = Upgrades.get_hidden_cosmetic_slots(_body.player_id)
	var upgrades: Array[StringName] = Upgrades.get_upgrades(_body.player_id)
	var coat_worn: bool = false
	for slot: StringName in CosmeticsService.SLOTS:
		var point: Node3D = _point_for(slot)
		if point == null:
			continue
		var old: Node = point.get_node_or_null(NodePath(MODEL_PREFIX + String(slot)))
		if old != null:
			point.remove_child(old)
			old.queue_free()
		if hidden.has(String(slot)) or not loadout.has(String(slot)):
			continue
		var data := ContentRegistry.get_content(StringName(str(loadout[String(slot)]))) as CosmeticData
		if data == null:
			continue
		var scene: PackedScene = model_for(data, upgrades)
		var model := scene.instantiate() as Node3D if scene != null else null
		if model == null:
			continue
		model.name = MODEL_PREFIX + String(slot)
		model.visible = not _body.is_local()
		point.add_child(model)
		if slot == &"coat":
			coat_worn = true
	# NEW 2026-11-14 (art rollout): a coat from the closet replaces the body's own white lab coat.
	_body.set_default_coat_shown(not coat_worn)


## The model to show: a mutation's variant if the player has one listed, else the normal one.
static func model_for(data: CosmeticData, upgrade_ids: Array[StringName]) -> PackedScene:
	for upgrade_id: StringName in upgrade_ids:
		var variant: Variant = data.mutation_variants.get(String(upgrade_id), data.mutation_variants.get(upgrade_id, null))
		if variant is PackedScene:
			return variant as PackedScene
	return data.scene


func _point_for(slot: StringName) -> Node3D:
	var point_name: StringName = CosmeticsService.ATTACH_POINTS.get(slot, &"body")
	return _body.get_attach_point(point_name)
