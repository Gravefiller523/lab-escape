class_name Interactable
extends Node
## Makes an object usable with the use key (E). Add it as a child of a CollisionObject3D (a StaticBody3D
## or Area3D) on the INTERACTABLES layer. The object's own script listens to `used`, which fires on the
## HOST only, after the host has checked distance, `enabled` and `use_condition`.
## If clients need to see the result (a door opening), the object's owner syncs that itself.

## Fires on the host when a player has used this. (Emitted by the InteractionController.)
@warning_ignore("unused_signal")
signal used(player_id: int)

## Shown after "Press E to ...", e.g. "Open door".
@export var prompt_text: String = "Use"
## 0 = press once. More than 0 = hold the key this many seconds (e.g. a lever).
@export var hold_seconds: float = 0.0
## How close the player's eyes must be (metres).
@export var max_distance: float = 2.5
@export var enabled: bool = true
## Optional extra check on the host: func(player_id: int) -> bool. Empty = always allowed.
var use_condition: Callable


## The Interactable for a node: the node itself, one of its children, or one up the tree. Null if none.
static func of(node: Node) -> Interactable:
	var current: Node = node
	while current != null:
		if current is Interactable:
			return current as Interactable
		for child: Node in current.get_children():
			if child is Interactable:
				return child as Interactable
		current = current.get_parent()
	return null


## Where distance is measured to: the object this Interactable belongs to.
func get_anchor() -> Node3D:
	return get_parent() as Node3D


## Host only: true if this player may use it now (checked after distance and hold time).
func allows(player_id: int) -> bool:
	if not enabled:
		return false
	if use_condition.is_valid():
		var allowed: bool = use_condition.call(player_id)
		if not allowed:
			return false
	return true
