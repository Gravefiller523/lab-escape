class_name UseTarget
extends Node
## Put it on a world object that reacts to items (a mutated plant that grows a ladder when watered, a
## boarded-up hatch you pry open). The host decides; the "used" state reaches every PC (and joiners).
## The object listens to used_changed to show it. Spec: docs/systems/items.md.

## Host: an item with one of the accepted tags was used on it.
signal item_used_on(tag: StringName, player_id: int)
## NEW 2026-10-19, every PC: it was used (or reset). The object shows its new look here.
signal used_changed(used: bool)

const NODE_NAME: String = "UseTarget"

## Item interaction tags it reacts to, e.g. ["water"] or ["pry"].
@export var accepted_tags: PackedStringArray = PackedStringArray()
## Only works once (a plant grows once).
@export var single_use: bool = true

var _used: bool = false


static func of(node: Node) -> UseTarget:
	var current: Node = node
	while current != null:
		var target := current as UseTarget
		if target != null:
			return target
		target = current.get_node_or_null(NodePath(NODE_NAME)) as UseTarget
		if target != null:
			return target
		current = current.get_parent()
	return null


func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_state_rpc.rpc_id(1)


func is_used() -> bool:
	return _used


## True if an item with this tag would do something now.
func accepts(tag: StringName) -> bool:
	return accepted_tags.has(String(tag)) and not (single_use and _used)


## Host: try an item tag on it. True if it reacted.
func try_use(tag: StringName, player_id: int) -> bool:
	if not is_inside_tree() or not multiplayer.is_server() or not accepts(tag):
		return false
	_state_rpc.rpc(true)
	item_used_on.emit(tag, player_id)
	return true


## Host: back to unused (test scenes).
func reset() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_state_rpc.rpc(false)


@rpc("authority", "call_local", "reliable")
func _state_rpc(used: bool) -> void:
	if not is_inside_tree():
		return
	var was: bool = _used
	_used = used
	if was != used:
		used_changed.emit(used)


@rpc("any_peer", "call_remote", "reliable")
func _request_state_rpc() -> void:
	if is_inside_tree() and multiplayer.is_server():
		_state_rpc.rpc_id(multiplayer.get_remote_sender_id(), _used)
