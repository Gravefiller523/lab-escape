class_name UIService
extends CanvasLayer
## Autoload "UI". Shows screens (main menu, pause), toasts, and sends you to the right scene after
## hosting, joining or losing the connection. Owns no game rules. Spec: docs/systems/ui.md.
##
## Phase 1a slice: main menu, a small pause menu and toasts. NEW 2026-10-19: the HUD and nameplates.

const SCREEN_MAIN_MENU: StringName = &"main_menu"
const SCREEN_PAUSE: StringName = &"pause"
## Above the game, below debug overlays.
const LAYER: int = 10
const TOAST_GAP_SECONDS: float = 0.2

var _screens: Dictionary[StringName, PackedScene] = {
	SCREEN_MAIN_MENU: preload("res://systems/ui/screens/main_menu.tscn"),
	SCREEN_PAUSE: preload("res://systems/ui/screens/pause_menu.tscn"),
}
var _open_screen: Control
var _open_name: StringName = &""
var _toast_label: Label
var _hud: Hud
var _nameplates: Nameplates
var _toast_queue: Array[String] = []
var _toast_seconds: Array[float] = []
var _toast_left: float = 0.0
## STUB (game_flow): how scenes are changed. Tests swap it for a fake.
var _flow: GameFlowStub = GameFlowStub.new()


## For tests only: use a fake scene changer.
func use_flow(flow: GameFlowStub) -> void:
	_flow = flow


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud = Hud.new()
	add_child(_hud)
	_nameplates = Nameplates.new()
	add_child(_nameplates)
	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(-300, 70)
	_toast_label.size = Vector2(600, 40)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 22)
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 6)
	add_child(_toast_label)

	EventBus.toast_requested.connect(func(text: String) -> void: toast(text))
	SteamSession.lobby_created.connect(func(_lobby_id: int) -> void: _enter_break_room())
	SteamSession.lobby_joined.connect(func(_lobby_id: int) -> void: _enter_break_room())
	SteamSession.lobby_join_failed.connect(func(reason: String) -> void: toast(reason, 5.0))
	# Joining can take you straight into the game (net_core's handshake loads the host's scene first):
	# the main menu must not stay on top.
	EventBus.game_state_changed.connect(func(_old_state: int, new_state: int) -> void:
		if _open_name == SCREEN_MAIN_MENU and new_state not in [GameFlowService.State.BOOT, GameFlowService.State.MAIN_MENU]:
			close_screen())
	SteamSession.connection_lost.connect(func() -> void: _back_to_menu("Lost connection to the host."))
	Net.join_refused.connect(func(reason: String) -> void: _back_to_menu(reason))


## NEW 2026-10-19: the HUD (prompt, hold bar, lift panel, spots for health and the inventory bar).
func get_hud() -> Hud:
	return _hud


## NEW 2026-10-19: the names above other players' heads (with the speaker icon).
func get_nameplates() -> Nameplates:
	return _nameplates


## Opens a screen by name (&"main_menu", &"pause"). Player input is off while a screen is open.
func show_screen(screen: StringName) -> void:
	if not _screens.has(screen):
		push_error("UI.show_screen: no screen called '%s'." % screen)
		return
	close_screen()
	_open_screen = _screens[screen].instantiate() as Control
	_open_name = screen
	add_child(_open_screen)
	move_child(_toast_label, -1)
	_set_player_input(false)


func close_screen() -> void:
	if _open_screen == null:
		return
	_open_screen.queue_free()
	_open_screen = null
	_open_name = &""
	_set_player_input(true)


func is_screen_open() -> bool:
	return _open_screen != null


## The name of the open screen, or &"" if none.
func get_open_screen() -> StringName:
	return _open_name


## Shows a short message at the top of the screen. Several toasts queue up.
func toast(text: String, seconds: float = 3.0) -> void:
	_toast_queue.append(text)
	_toast_seconds.append(seconds)
	if _toast_label.text.is_empty():
		_next_toast()


## Subtitle for an important sound: shown (as a toast for now) only if Settings > Accessibility > Subtitles is on.
func caption(text: String) -> void:
	if Settings.is_subtitles_on():
		toast(text)


## Other systems can add screens.
func register_screen(screen: StringName, scene: PackedScene) -> void:
	_screens[screen] = scene


## Leaves the game (or the lobby) and goes back to the main menu.
func leave_game() -> void:
	SteamSession.leave_lobby()
	_back_to_menu("")


func _process(delta: float) -> void:
	if _toast_label.text.is_empty():
		return
	_toast_left -= delta
	if _toast_left <= 0.0:
		_toast_label.text = ""
		if not _toast_queue.is_empty():
			get_tree().create_timer(TOAST_GAP_SECONDS).timeout.connect(_next_toast)


## The current toast text, or "" (used by tests).
func get_toast_text() -> String:
	return _toast_label.text


func _next_toast() -> void:
	if _toast_queue.is_empty() or not _toast_label.text.is_empty():
		return
	_toast_label.text = _toast_queue.pop_front()
	_toast_left = _toast_seconds.pop_front()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputActions.PAUSE):
		return
	if _open_name == SCREEN_PAUSE:
		close_screen()
		get_viewport().set_input_as_handled()
	elif not is_screen_open() and _local_body() != null:
		show_screen(SCREEN_PAUSE)
		get_viewport().set_input_as_handled()


## After hosting or joining from the main menu. (In the Break Room or a test scene we stay put.)
func _enter_break_room() -> void:
	if _open_name == SCREEN_MAIN_MENU:
		close_screen()
	if not _flow.is_in_main_menu(get_tree()):
		return
	_flow.go_to_break_room(get_tree())


## After leaving, losing the host or being refused. Test scenes stay open and just show the message.
func _back_to_menu(message: String) -> void:
	if _flow.is_in_break_room(get_tree()):
		close_screen()
		_flow.go_to_main_menu(get_tree())
	elif _flow.is_in_main_menu(get_tree()) and get_open_screen() != SCREEN_MAIN_MENU:
		show_screen(SCREEN_MAIN_MENU)
	elif _open_name == SCREEN_PAUSE:
		close_screen()
	if not message.is_empty():
		toast(message, 5.0)


func _local_body() -> PlayerCharacter:
	return PlayerCharacter.find(Net.local_player_id())


func _set_player_input(enabled: bool) -> void:
	var body: PlayerCharacter = _local_body()
	if body != null:
		body.set_input_enabled(enabled)
	elif not enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
