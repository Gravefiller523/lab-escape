class_name BehaviourEffectData
extends UpgradeEffectData
## Adds a special rule that no other effect piece covers,
## e.g. Fly's "attracted to trash". The scene's root node is added under the
## player while the upgrade is held, and removed when it is lost.

@export var behaviour_scene: PackedScene
## Optional settings passed to the behaviour node.
@export var params: Dictionary = {}
