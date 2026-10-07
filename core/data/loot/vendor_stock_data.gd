class_name VendorStockData
extends ContentData
## What a vendor can sell and for how many gems.
## Example id: "stock_zoology_vending". Files live in res://content/vendor_stock/.
## Vendors sell items only (weapons, tools, consumables).

## How many different items a vendor shows at once.
@export var slots_shown: int = 3
@export var entries: Array[VendorEntryData] = []


func get_type_key() -> StringName:
	return &"stock"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("entries")
	return fields
