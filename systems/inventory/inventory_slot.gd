class_name InventorySlot
extends RefCounted
## What sits in one inventory slot. Spec: docs/systems/inventory.md.

var item_id: StringName = &""
## Uses left on the item (each one in a stack has its own uses only once it's taken out). -1 = unlimited.
var uses_left: int = -1
## NEW 2026-10-19: how many are stacked here (up to ItemData.max_stack; 1 for most items).
var count: int = 1


static func make(item_id_: StringName, uses_left_: int = -1, count_: int = 1) -> InventorySlot:
	var slot := InventorySlot.new()
	slot.item_id = item_id_
	slot.uses_left = uses_left_
	slot.count = count_
	return slot


func to_dict() -> Dictionary:
	return {"item_id": String(item_id), "uses_left": uses_left, "count": count}


static func from_dict(data: Dictionary) -> InventorySlot:
	var item_id_: String = data.get("item_id", "")
	var uses_left_: int = data.get("uses_left", -1)
	var count_: int = data.get("count", 1)
	return make(StringName(item_id_), uses_left_, count_)
