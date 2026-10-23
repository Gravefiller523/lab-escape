class_name LootDrop
extends RefCounted
## One thing a loot roll gives: a prop (gems, meat...) or an item, how many, and the upgrade a glowing
## gem or robot part holds. Spec: docs/systems/loot.md.

var prop_id: StringName = &""
var item_id: StringName = &""
## Set for glowing gems and robot parts.
var upgrade_id: StringName = &""
var count: int = 1


static func make(prop_id_: StringName, item_id_: StringName, count_: int, upgrade_id_: StringName = &"") -> LootDrop:
	var drop := LootDrop.new()
	drop.prop_id = prop_id_
	drop.item_id = item_id_
	drop.count = count_
	drop.upgrade_id = upgrade_id_
	return drop
