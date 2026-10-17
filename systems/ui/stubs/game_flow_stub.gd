class_name GameFlowStub
extends RefCounted
## STUB for game_flow (docs/systems/game_flow.md), which isn't built yet and will own scene loading.
## The ui calls these functions; when game_flow exists, call its API instead and delete this.
##
## It only moves between the main menu and the Break Room. Other scenes (systems' test scenes,
## which have their own Host/Join buttons) are left alone.

const BREAK_ROOM_SCENE: String = "res://systems/break_room/break_room.tscn"
const MAIN_MENU_SCENE: String = "res://systems/ui/main_menu_background.tscn"


func is_in_main_menu(tree: SceneTree) -> bool:
	return _current_path(tree) == MAIN_MENU_SCENE


func is_in_break_room(tree: SceneTree) -> bool:
	return _current_path(tree) == BREAK_ROOM_SCENE


func go_to_break_room(tree: SceneTree) -> void:
	tree.change_scene_to_file(BREAK_ROOM_SCENE)


func go_to_main_menu(tree: SceneTree) -> void:
	tree.change_scene_to_file(MAIN_MENU_SCENE)


func _current_path(tree: SceneTree) -> String:
	var current: Node = tree.current_scene
	return current.scene_file_path if current != null else ""
