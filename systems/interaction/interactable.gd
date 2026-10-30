class_name Interactable
extends Node
## Makes an object usable with the use key (E). Add it as a child of a CollisionObject3D (a StaticBody3D
## or Area3D) on the INTERACTABLES layer. The object's own script listens to `used`, which fires on the
## HOST only, after the host has checked distance, `enabled` and `use_condition`.
## If clients need to see the result (a door opening), the object's owner syncs that itself.
## NEW 2026-10-30 (HL2 feel step 4.1): `continuous` objects (a valve, a crank) are turned by holding E: the
## host fires use_started, then use_tick every physics step, then use_stopped. `use_point` measures reach
## to a handle instead of the object's middle. `refused` tells the object someone tried and was turned away.

## Fires on the host when a player has used this. (Emitted by the InteractionController.)
@warning_ignore("unused_signal")
signal used(player_id: int)
## NEW 2026-10-30. Host: a player in reach tried to use it but it said no (disabled, or use_condition said
## no, e.g. a locked door). They hear the "can't use" buzz.
@warning_ignore("unused_signal")
signal refused(player_id: int)
## NEW 2026-10-30. Host, continuous objects only: a player started holding E on it.
@warning_ignore("unused_signal")
signal use_started(player_id: int)
## NEW 2026-10-30. Host, continuous objects only: every physics step while they hold E on it (in reach).
@warning_ignore("unused_signal")
signal use_tick(player_id: int, delta: float)
## NEW 2026-10-30. Host, continuous objects only: they let go, looked away, walked off or it said no.
@warning_ignore("unused_signal")
signal use_stopped(player_id: int)

## Shown after "Press E to ...", e.g. "Open door".
@export var prompt_text: String = "Use"
## 0 = press once. More than 0 = hold the key this many seconds (e.g. a lever).
@export var hold_seconds: float = 0.0
## How close the player's eyes must be (metres) to the use point.
@export var max_distance: float = 2.5
@export var enabled: bool = true
## NEW 2026-10-30: hold E to keep using it (use_tick), instead of a single `used`.
@export var continuous: bool = false
## NEW 2026-10-30: a Node3D whose position reach is measured to, e.g. a door's handle (relative to this
## node, so a sibling is "../Handle"). Empty = the object this Interactable belongs to.
@export var use_point: NodePath
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


## The object this Interactable belongs to.
func get_anchor() -> Node3D:
	return get_parent() as Node3D


## NEW 2026-10-30: where reach is measured to: the use point if it has one, else the object.
func get_use_position() -> Vector3:
	var point: Node3D = get_node_or_null(use_point) as Node3D if not use_point.is_empty() else null
	if point != null:
		return point.global_position
	var anchor: Node3D = get_anchor()
	return anchor.global_position if anchor != null else Vector3.ZERO


## Host only: true if this player may use it now (checked after distance and hold time).
func allows(player_id: int) -> bool:
	if not enabled:
		return false
	if use_condition.is_valid():
		var allowed: bool = use_condition.call(player_id)
		if not allowed:
			return false
	return true
