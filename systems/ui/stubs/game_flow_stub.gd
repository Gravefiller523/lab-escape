class_name GameFlowStub
extends RefCounted
## How the ui changes scenes. CHANGED 2026-10-18: game_flow exists now, so this only passes the
## ui's calls on to the GameFlow autoload (docs/systems/game_flow.md). The ui's tests swap it for a
## fake that records the calls, so no scenes are really loaded.
##
## Systems' own test scenes (which have their own Host/Join buttons) are left alone.

const BREAK_ROOM_SCENE: String = GameFlowService.BREAK_ROOM_SCENE
const MAIN_MENU_SCENE: String = GameFlowService.MAIN_MENU_SCENE


func is_in_main_menu(tree: SceneTree) -> bool:
	return _current_path(tree) == MAIN_MENU_SCENE


## True in any scene game_flow runs (the Break Room, and floors during a run): leaving goes to the menu.
func is_in_break_room(tree: SceneTree) -> bool:
	if _current_path(tree) == BREAK_ROOM_SCENE:
		return true
	return GameFlow.get_state() not in [GameFlowService.State.BOOT, GameFlowService.State.MAIN_MENU]


func go_to_break_room(_tree: SceneTree) -> void:
	GameFlow.go_to_break_room()


func go_to_main_menu(_tree: SceneTree) -> void:
	GameFlow.return_to_main_menu()


func _current_path(tree: SceneTree) -> String:
	var current: Node = tree.current_scene
	return current.scene_file_path if current != null else ""
