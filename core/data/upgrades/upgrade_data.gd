class_name UpgradeData
extends ContentData
## Shared base for mutations and cybernetics.
##
## An upgrade is just a list of small effect pieces (movement, voice, slots,
## stats, visuals, special behaviour). The upgrades system applies them.
## New upgrades are new combinations of existing effect pieces.

enum StackRule {
	## Gaining it again does nothing (the item is still used up).
	UNIQUE,
	## Each copy adds its effects again, up to max_stacks.
	STACKS,
}

## The building blocks this upgrade is made of.
@export var effects: Array[UpgradeEffectData] = []
@export var stack_rule: StackRule = StackRule.UNIQUE
## Only used when stack_rule is STACKS.
@export var max_stacks: int = 1
## Upgrades that share a clash tag cannot be held together.
## Gaining a new one replaces the old one (see docs/systems/upgrades.md).
## Example: Octo and Frog both have "legs".
@export var clash_tags: PackedStringArray = PackedStringArray()
## How likely this is to be rolled compared with others in the same pool.
@export var drop_weight: float = 1.0
## Only roll this upgrade on floors of these departments. Empty = any department.
@export var department_ids: Array[StringName] = []
## Colour of the glowing gem or robot part that holds this upgrade.
@export var glow_color: Color = Color(0.4, 1.0, 0.6)
