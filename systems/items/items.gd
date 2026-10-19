class_name ItemsService
extends Node
## Autoload "Items". Gives every player body a HeldItemController (child "HeldItem") when it spawns, and
## makes `spawn item_<name> [count]` drop item pickups in the debug console. Spec: docs/systems/items.md.


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	DebugConsole.register_spawner(&"item", _console_spawn)


## A body's HeldItemController, or null.
static func held_of(body: Node) -> HeldItemController:
	return body.get_node_or_null(NodePath(HeldItemController.NODE_NAME)) as HeldItemController if body != null else null


func _on_player_spawned(_player_id: int, player_node: Node3D) -> void:
	if player_node.is_queued_for_deletion() or held_of(player_node) != null:
		return
	player_node.add_child(HeldItemController.new())


func _console_spawn(id: StringName, at: Transform3D, count: int, _player_id: int) -> String:
	var spawned: int = 0
	for index: int in count:
		var spot := at.translated(Vector3(0.0, 0.4 * float(index), 0.0))
		if Props.spawn_item(id, spot) != null:
			spawned += 1
	return "Spawned %d x %s." % [spawned, id]
