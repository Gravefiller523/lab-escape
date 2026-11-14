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


func test_pause_menu_hosts_local_in_test_scenes() -> void:
	_flow.in_main_menu = false
	UI.show_screen(UIService.SCREEN_PAUSE)
	await wait_process_frames(2)
	var menu: Node = UI.get_child(UI.get_child_count() - 2)
	var port_edit := menu.find_child("PortEdit", true, false) as LineEdit
	port_edit.text = str(TEST_PORT + 1)
	assert_not_null(menu.find_child("JoinLocalButton", true, false), "join local is there too")
	(menu.find_child("HostLocalButton", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	assert_true(Net.is_online(), "now hosting")
	assert_false(UI.is_screen_open(), "the pause menu closes")
	assert_eq(_flow.break_room_calls, 0, "the test scene stays open")

	UI.show_screen(UIService.SCREEN_PAUSE)
	await wait_process_frames(2)
	menu = UI.get_child(UI.get_child_count() - 2)
	assert_null(menu.find_child("HostLocalButton", true, false), "no local testing buttons once connected")


func test_main_menu_closes_once_you_are_in_the_game() -> void:
	UI.show_screen(UIService.SCREEN_MAIN_MENU)
	assert_eq(UI.get_open_screen(), UIService.SCREEN_MAIN_MENU)
	# Joining loads the host's scene during the handshake, before "lobby joined" arrives.
	EventBus.game_state_changed.emit(GameFlowService.State.MAIN_MENU, GameFlowService.State.BREAK_ROOM)
	assert_false(UI.is_screen_open(), "the menu doesn't stay on top of the Break Room")
	_flow.in_main_menu = false
	UI.show_screen(UIService.SCREEN_MAIN_MENU)
	SteamSession.lobby_joined.emit(1)
	assert_false(UI.is_screen_open(), "nor when 'lobby joined' comes after the scene changed")
	assert_eq(_flow.break_room_calls, 0, "and it doesn't load the Break Room again")


## NEW 2026-11-11 (roadmap WP6): the pause menu's controls page lists the current key for each action.
func test_pause_menu_lists_the_controls() -> void:
	_flow.in_main_menu = false
	UI.show_screen(UIService.SCREEN_PAUSE)
	await wait_process_frames(2)
	var menu: Node = UI.get_child(UI.get_child_count() - 2)
	assert_false(menu.call("is_controls_open"), "hidden at first")
	for button: Node in menu.find_children("*", "Button", true, false):
		if (button as Button).text == "Controls":
			(button as Button).pressed.emit()
	assert_true(menu.call("is_controls_open"), "the Controls button shows it")
	var text: String = menu.call("get_controls_text")
	assert_string_contains(text, "Jump: %s" % Settings.get_binding_text(InputActions.JUMP))
	assert_string_contains(text, "Use / grab: %s" % Settings.get_binding_text(InputActions.USE))
	assert_string_contains(text, "Player list: Tab")


## NEW 2026-11-11 (roadmap WP6): Tab shows every player, with Mute for others and Kick for the host.
func test_tab_shows_the_player_list() -> void:
	_flow.in_main_menu = false
	var body := PLAYER_SCENE.instantiate() as PlayerCharacter
	body.player_id = Net.local_player_id()
	add_child_autofree(body)
	await wait_process_frames(2)
	var tab := InputEventAction.new()
	tab.action = InputActions.PLAYER_LIST
	tab.pressed = true
	Input.parse_input_event(tab)
	await wait_process_frames(3)
	assert_eq(UI.get_open_screen(), UIService.SCREEN_PLAYERS, "Tab opens the player list")
	var screen: Node = UI.get_child(UI.get_child_count() - 2)
	var rows: PackedStringArray = screen.call("get_row_texts")
	assert_eq(rows.size(), Net.get_player_ids().size(), "a row per player")
	assert_string_contains(rows[0], "(you)")
	assert_null(screen.call("find_button", Net.local_player_id(), "Mute"), "no Mute button for yourself")
	Input.parse_input_event(tab)
	await wait_process_frames(3)
	assert_false(UI.is_screen_open(), "Tab again closes it")


## NEW 2026-11-13 (roadmap WP13b, OK'd by Zachary): the main menu shows which build this is, so friends can compare.
func test_main_menu_shows_the_build() -> void:
	UI.show_screen(UIService.SCREEN_MAIN_MENU)
	await wait_process_frames(2)
	var menu: Node = UI.get_child(UI.get_child_count() - 2)
	var label := menu.find_child("BuildLabel", true, false) as Label
	assert_not_null(label, "a build label")
	assert_eq(label.text, BuildInfo.get_label(), "showing this build, e.g. v0.1.0 build 3fa9c1d")
	UI.close_screen()


func test_main_menu_join_and_local_options_open_under_their_buttons() -> void:
	# NEW 2026-11-14 (roadmap WP27): the lab look keeps the join and local testing options behind two big buttons.
	UI.show_screen(UIService.SCREEN_MAIN_MENU)
	await wait_process_frames(2)
	var menu: Node = UI.get_child(UI.get_child_count() - 2)
	var join_box := menu.find_child("JoinBox", true, false) as Control
	var local_box := menu.find_child("LocalBox", true, false) as Control
	assert_not_null(join_box)
	assert_not_null(local_box)
	assert_false(join_box.visible, "closed at first")
	assert_false(local_box.visible, "closed at first")
	var local_button: Button = null
	for button: Node in menu.find_children("*", "Button", true, false):
		if (button as Button).text == "TEST ON ONE PC":
			local_button = button as Button
	assert_not_null(local_button, "a Test on one PC button")
	local_button.pressed.emit()
	assert_true(local_box.visible, "pressing it shows the local testing options")
	assert_true(local_box.is_ancestor_of(menu.find_child("HostLocalButton", true, false)), "Host local is in there")
	assert_not_null(menu.find_child("StaffBadge", true, false), "the staff ID badge shows the Steam sign-in")
	UI.close_screen()
