extends GutTest
## Tests for the ui main menu slice (docs/systems/ui.md). Uses the real UI autoload with a fake
## scene changer, so no scenes are really loaded.

const PLAYER_SCENE: PackedScene = preload("res://systems/player/player.tscn")
const TEST_PORT: int = 17990


## Records what the ui asked game_flow (stub) to do.
class FakeFlow:
	extends GameFlowStub
	var in_main_menu: bool = true
	var in_break_room: bool = false
	var break_room_calls: int = 0
	var main_menu_calls: int = 0

	func is_in_main_menu(_tree: SceneTree) -> bool:
		return in_main_menu

	func is_in_break_room(_tree: SceneTree) -> bool:
		return in_break_room

	func go_to_break_room(_tree: SceneTree) -> void:
		break_room_calls += 1

	func go_to_main_menu(_tree: SceneTree) -> void:
		main_menu_calls += 1


var _flow: FakeFlow


func before_each() -> void:
	_flow = FakeFlow.new()
	UI.use_flow(_flow)


func after_each() -> void:
	UI.close_screen()
	SteamSession.leave_lobby()
	UI.use_flow(GameFlowStub.new())
	Input.action_release(InputActions.MOVE_FORWARD)
	await wait_process_frames(2)


func test_toast_queue() -> void:
	UI.toast("first", 0.1)
	UI.toast("second", 0.1)
	assert_eq(UI.get_toast_text(), "first")
	await wait_until(func() -> bool: return UI.get_toast_text() == "second", 2.0)
	assert_eq(UI.get_toast_text(), "second", "toasts show one after another")
	await wait_until(func() -> bool: return UI.get_toast_text().is_empty(), 2.0)


func test_host_local_from_menu_goes_to_break_room() -> void:
	UI.show_screen(UIService.SCREEN_MAIN_MENU)
	await wait_process_frames(2)
	var menu: Node = UI.get_child(UI.get_child_count() - 2)
	var port_edit := menu.find_child("PortEdit", true, false) as LineEdit
	port_edit.text = str(TEST_PORT)
	var host_button := menu.find_child("HostLocalButton", true, false) as Button
	host_button.pressed.emit()
	assert_true(SteamSession.is_local_mode(), "hosting locally")
	assert_eq(_flow.break_room_calls, 1, "the Break Room is loaded")
	assert_false(UI.is_screen_open(), "the menu closed")


func test_connection_lost_returns_to_menu() -> void:
	_flow.in_main_menu = false
	_flow.in_break_room = true
	SteamSession.connection_lost.emit()
	assert_eq(_flow.main_menu_calls, 1)
	assert_eq(UI.get_toast_text(), "Lost connection to the host.")


func test_join_refused_returns_to_menu() -> void:
	_flow.in_main_menu = false
	_flow.in_break_room = true
	Net.join_refused.emit(NetService.REFUSE_FULL)
	assert_eq(_flow.main_menu_calls, 1)


func test_test_scenes_are_left_alone() -> void:
	_flow.in_main_menu = false
	_flow.in_break_room = false
	SteamSession.lobby_created.emit(1)
	SteamSession.connection_lost.emit()
	assert_eq(_flow.break_room_calls, 0)
	assert_eq(_flow.main_menu_calls, 0)


func test_pause_disables_player_input() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	add_child_autofree(floor_body)
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	add_child_autofree(body)
	await wait_physics_frames(10)

	UI.show_screen(UIService.SCREEN_PAUSE)
	Input.action_press(InputActions.MOVE_FORWARD)
	var start: Vector3 = body.global_position
	await wait_physics_frames(20)
	assert_almost_eq(body.global_position.z, start.z, 0.05, "can't walk while the pause menu is open")

	UI.close_screen()
	await wait_physics_frames(20)
	assert_lt(body.global_position.z, start.z - 0.5, "walks again after closing it")
