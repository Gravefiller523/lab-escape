class_name CosmeticData
extends ContentData
## A look-only item (hat, coat...). Never changes gameplay.
## Example id: "cosmetic_hat_beanie". Files live in res://content/cosmetics/.

## Body slot: "hat", "glasses", "coat", "gloves", "shoes".
@export var slot: StringName = &"hat"
@export var scene: PackedScene
## Replacement models for mutated bodies, keyed by mutation id
## (e.g. a longer scarf for "mutation_giraffe"). Missing = use the normal scene.
@export var mutation_variants: Dictionary = {}
## How it is unlocked. Leave empty for unlocked from the start.
@export var unlock: UnlockRuleData


func get_type_key() -> StringName:
	return &"cosmetic"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append("scene")
	return fields
