class_name ItemData
extends ContentData
## A weapon, tool or consumable that goes in an inventory slot.
## Example id: "item_crowbar". Files live in res://content/items/.
## Loose physical things (gems, meat, robot parts, lift parts) are props, not items.

enum Category { WEAPON, TOOL, CONSUMABLE }

@export var category: Category = Category.TOOL
## The physical pickup lying in the world (a RigidBody3D scene).
@export var world_scene: PackedScene
## The first-person model shown in the player's hand.
@export var held_scene: PackedScene
## What the item does, built from shared behaviour pieces (melee, throw, consume, use-on-object).
@export var behaviours: Array[ItemBehaviourData] = []
## How many times it can be used. -1 = unlimited.
@export var uses: int = -1
## Kept simple for a possible crafting system later: crafting would only need
## a new RecipeData type that lists item ids, without changing this class.


func get_type_key() -> StringName:
	return &"item"


func get_required_fields() -> PackedStringArray:
	var fields: PackedStringArray = super()
	fields.append_array(PackedStringArray(["world_scene", "held_scene"]))
	return fields
