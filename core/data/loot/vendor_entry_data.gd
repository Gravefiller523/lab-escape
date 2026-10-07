class_name VendorEntryData
extends Resource
## One item a vendor may sell. Saved inside the stock's .tres file.

@export var item_id: StringName = &""
## Price in gem value (a plain gem is usually worth 1).
@export var price: int = 3
## How likely it is to be chosen for one of the shown slots.
@export var weight: float = 1.0
## How many can be bought from one vendor. 0 = unlimited.
@export var stock_count: int = 1
