class_name VisualAttachmentEffectData
extends UpgradeEffectData
## Attaches a model to the player's body (wings, tentacles, robot arm).

@export var scene: PackedScene
## Named attach point on the player body, e.g. "head", "back", "left_arm", "legs".
@export var attach_point: StringName = &""
## Cosmetic slots hidden while this is attached, e.g. ["shoes"] for Slug.
@export var hides_cosmetic_slots: PackedStringArray = PackedStringArray()
