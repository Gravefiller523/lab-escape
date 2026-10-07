class_name UseOnObjectBehaviourData
extends ItemBehaviourData
## Use the item on something in the world, e.g. pour energy drink on a mutated
## plant to grow a ladder. World objects list which interaction tags they accept.

## Tag sent to the target, e.g. "water", "pry", "cut", "light".
@export var interaction_tag: StringName = &""
## How close the target must be, in metres.
@export var reach: float = 2.0
## If true, one use is spent.
@export var spends_use: bool = true
