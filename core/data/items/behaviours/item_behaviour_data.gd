class_name ItemBehaviourData
extends Resource
## Base for one shared behaviour piece inside an item.
## Saved inside the item's .tres file. Adding a NEW kind of behaviour piece is a
## code change in the items system; using existing kinds is not.

## Which input triggers it.
enum Trigger { PRIMARY, SECONDARY }

@export var trigger: Trigger = Trigger.PRIMARY
## Seconds before this behaviour can be used again.
@export var cooldown: float = 0.5
