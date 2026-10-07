class_name LootEntryData
extends Resource
## One line of a loot table. Saved inside the table's .tres file.

## The prop to drop, e.g. "prop_gem", "prop_meat", "prop_robot_part".
## Gems may glow (GameConfig.gem_glow_chance); robot parts always hold a cybernetic.
@export var prop_id: StringName = &""
## Or an item to drop instead (leave prop_id empty).
@export var item_id: StringName = &""
@export var weight: float = 1.0
@export var min_count: int = 1
@export var max_count: int = 1
