class_name InteractionService
extends Node
## Autoload "Interaction". Gives every player body an InteractionController (child "Interaction") as
## soon as it spawns, so the player scene doesn't need editing. Other systems get the local player's
## controller here to plug in their use actions.


func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)


## The local player's controller, or null if you have no body right now.
func get_local_controller() -> InteractionController:
	for node: Node in get_tree().get_nodes_in_group(PlayerCharacter.GROUP):
		var body := node as PlayerCharacter
		if body != null and body.is_local() and not body.is_queued_for_deletion():
			return controller_of(body)
	return null


## A body's controller, or null.
static func controller_of(body: PlayerCharacter) -> InteractionController:
	return body.get_node_or_null(NodePath(InteractionController.NODE_NAME)) as InteractionController


func _on_player_spawned(_player_id: int, player_node: Node3D) -> void:
	var body := player_node as PlayerCharacter
	if body == null or controller_of(body) != null:
		return
	var controller := InteractionController.new()
	controller.name = InteractionController.NODE_NAME
	body.add_child(controller)
