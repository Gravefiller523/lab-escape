extends Control
## The main menu: Host (Steam), Quit, and a "Testing on one PC" section with Host local / Join local.
## Joining a friend over Steam happens through Steam itself: accept their invite, or right-click them
## in your friends list and choose "Join game". There is also a box for a lobby id, for testing.
##
## Launch options after "--" (for test windows): "host" or "join" press the local buttons by
## themselves, "port=7790" picks the port.

const DEFAULT_PORT: int = 7777
const DEFAULT_ADDRESS: String = "127.0.0.1"
## NEW 2026-11-14 (roadmap WP27): the line under the title, and the staff ID badge colour.
const TAGLINE: String = "Clock out. Get out. Bring friends."
const BADGE_COLOR: Color = Color(0.93, 0.94, 0.92)

## The "host" / "join" launch options run once per game start, not every time the menu is rebuilt
## (coming Back from Settings, or after leaving a game).
static var _launch_options_used: bool = false

var _status: Label
var _lobby_id_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_status()
	_run_launch_options.call_deferred()


func _build() -> void:
	# CHANGED 2026-11-14 (roadmap WP27, Zachary OK'd the mock-up): the lab look. The title and big buttons on the left
	# over the lit lab room behind (main_menu_background); "Join a friend" and "Test on one PC" open their options
	# under them; the Steam sign-in shows on a staff ID badge. The buttons and boxes are the same as before.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.position = Vector2(70, 46)
	column.custom_minimum_size = Vector2(430, 0)
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "LAB ESCAPE"
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	column.add_child(title)
	column.add_child(_hazard_stripe(430.0, 14.0))
	var tagline := Label.new()
	tagline.text = TAGLINE
	tagline.modulate = Color(1, 1, 1, 0.75)
	tagline.add_theme_constant_override("outline_size", 4)
	tagline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	column.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	column.add_child(gap)

	var host_button := _add_button(column, "HOST GAME", _on_host_steam)
	host_button.name = "HostSteamButton"
	host_button.disabled = not SteamSession.is_steam_running()

	var join_box := _sub_box(column)
	join_box.name = "JoinBox"
	_add_toggle(column, "JOIN A FRIEND", join_box)
	column.move_child(join_box, column.get_child_count() - 1)
	var join_column := VBoxContainer.new()
	join_box.add_child(join_column)
	var join_hint := Label.new()
	join_hint.text = "Accept their Steam invite, or right-click them in your
Steam friends list and choose \"Join game\"."
	join_hint.modulate = Color(0.85, 0.85, 0.88)
	join_column.add_child(join_hint)
	var lobby_row := HBoxContainer.new()
	join_column.add_child(lobby_row)
	_lobby_id_edit = LineEdit.new()
	_lobby_id_edit.placeholder_text = "Steam lobby id (testing)"
	_lobby_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_row.add_child(_lobby_id_edit)
	var join_id_button := _add_button(lobby_row, "Join by id", _on_join_by_id)
	join_id_button.disabled = not SteamSession.is_steam_running()

	var local_box := _sub_box(column)
	local_box.name = "LocalBox"
	_add_toggle(column, "TEST ON ONE PC", local_box)
	column.move_child(local_box, column.get_child_count() - 1)
	var local_column := VBoxContainer.new()
	local_box.add_child(local_column)
	var local_title := Label.new()
	local_title.text = "Two game windows on this PC (no Steam)"
	local_title.modulate = Color(0.85, 0.85, 0.88)
	local_column.add_child(local_title)
	var address_row := HBoxContainer.new()
	local_column.add_child(address_row)
	_address_edit = LineEdit.new()
	_address_edit.text = DEFAULT_ADDRESS
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(_address_edit)
	_port_edit = LineEdit.new()
	_port_edit.name = "PortEdit"
	_port_edit.text = str(DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(90, 0)
	address_row.add_child(_port_edit)
	var local_row := HBoxContainer.new()
	local_column.add_child(local_row)
	var host_local := _add_button(local_row, "Host local", _on_host_local)
	host_local.name = "HostLocalButton"
	host_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join_local := _add_button(local_row, "Join local", _on_join_local)
	join_local.name = "JoinLocalButton"
	join_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_add_button(column, "SETTINGS", func() -> void: Settings.open(UI.SCREEN_MAIN_MENU))
	_add_button(column, "QUIT", func() -> void: get_tree().quit())
	for child: Node in column.get_children():
		if child is Button:
			(child as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT

	# The staff ID badge: who Steam says you are.
	var badge := PanelContainer.new()
	badge.name = "StaffBadge"
	var paper := StyleBoxFlat.new()
	paper.bg_color = BADGE_COLOR
	paper.set_corner_radius_all(8)
	paper.set_content_margin_all(12)
	badge.add_theme_stylebox_override("panel", paper)
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(badge)
	var badge_column := VBoxContainer.new()
	badge.add_child(badge_column)
	var strip := ColorRect.new()
	strip.color = Color(0.28, 0.72, 0.4)
	strip.custom_minimum_size = Vector2(280, 8)
	badge_column.add_child(strip)
	var staff := Label.new()
	staff.text = "STAFF ID"
	staff.add_theme_font_size_override("font_size", 14)
	staff.add_theme_color_override("font_color", Color(0.3, 0.3, 0.32))
	badge_column.add_child(staff)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", Color(0.08, 0.08, 0.09))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(280, 0)
	badge_column.add_child(_status)
	# NEW 2026-11-13 (roadmap WP13b, OK'd by Zachary): which build this is, small and grey in the bottom-right corner,
	# so two friends can check they have the same one.
	var build := Label.new()
	build.name = "BuildLabel"
	build.text = BuildInfo.get_label()
	build.modulate = Color(0.55, 0.55, 0.6)
	build.add_theme_font_size_override("font_size", 14)
	build.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	build.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	build.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(build)


## NEW 2026-11-14 (roadmap WP27): a black-and-yellow hazard stripe under the title.
func _hazard_stripe(width: float, height: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, height)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index: int in int(width / 14.0) + 3:
		var piece := ColorRect.new()
		piece.color = HudStyle.ACCENT if index % 2 == 0 else Color(0.08, 0.08, 0.09)
		piece.size = Vector2(14.0, height * 3.0)
		piece.position = Vector2(index * 14.0 - height, -height)
		piece.rotation = deg_to_rad(30.0)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(piece)
	return holder


## NEW 2026-11-14: a hidden box of options under a big button.
func _sub_box(parent: Control) -> PanelContainer:
	var box := PanelContainer.new()
	box.visible = false
	parent.add_child(box)
	return box


## NEW 2026-11-14: a big button that opens or closes its box of options.
func _add_toggle(parent: Control, text: String, box: Control) -> Button:
	return _add_button(parent, text, func() -> void: box.visible = not box.visible)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _refresh_status() -> void:
	if SteamSession.is_steam_running():
		_status.text = "Steam: signed in as %s" % SteamSession.get_persona_name(SteamSession.get_local_steam_id())
	else:
		_status.text = "Steam isn't running: only local testing is available."


func _port() -> int:
	var text: String = _port_edit.text.strip_edges()
	return text.to_int() if text.is_valid_int() else DEFAULT_PORT


func _on_host_steam() -> void:
	_status.text = "Creating a Steam lobby..."
	SteamSession.host_lobby()


func _on_join_by_id() -> void:
	var text: String = _lobby_id_edit.text.strip_edges()
	if not text.is_valid_int():
		UI.toast("Type a lobby id (numbers only) first.")
		return
	_status.text = "Joining lobby..."
	SteamSession.join_lobby(text.to_int())


func _on_host_local() -> void:
	SteamSession.host_local(_port())


func _on_join_local() -> void:
	_status.text = "Connecting..."
	SteamSession.join_local(_address_edit.text.strip_edges(), _port())


func _run_launch_options() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("port=") and arg.trim_prefix("port=").is_valid_int():
			_port_edit.text = arg.trim_prefix("port=")
	if _launch_options_used:
		return
	_launch_options_used = true
	if args.has("host_steam"):
		_on_host_steam()
	elif args.has("host"):
		_on_host_local()
	elif args.has("join"):
		_on_join_local()
