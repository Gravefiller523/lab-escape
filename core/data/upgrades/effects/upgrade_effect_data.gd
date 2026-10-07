class_name UpgradeEffectData
extends Resource
## Base for one small effect piece inside a mutation or cybernetic.
## Effect pieces are saved inside the upgrade's .tres file, not as separate content.
## Adding a NEW kind of effect piece is a code change in the upgrades system
## (see docs/systems/upgrades.md). Using existing kinds is not.

## Optional note for designers. Not shown in game.
@export var note: String = ""
