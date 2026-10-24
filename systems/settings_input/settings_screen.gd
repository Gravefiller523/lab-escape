class_name SettingsScreen
extends Control
## The Settings screen (UI screen &"settings", opened with Settings.open()). Every change is applied and
## saved at once. Tabs: Audio, Video, Controls (with key rebinding), Accessibility.
## Rebinding: click an action's button, then press a key or mouse button (Esc cancels).

const ROW_HEIGHT: float = 34.0
const LABEL_WIDTH: float = 230.0
const PANEL_SIZE: Vector2 = Vector2(640, 560)
const WAITING_TEXT: String = "Press a key... (Esc cancels)"
## Readable names for the actions in the rebinding list.
const ACTION_NAMES: Dictionary[StringName, String] = {
	&"move_forward": "Move forward", &"move_back": "Move back", &"move_left": "Move left",
	&"move_right": "Move right", &"jump": "Jump", &"crouch": "Crouch", &"sprint": "Sprint",
	&"use": "Use / grab", &"drop": "Drop", &"primary": "Attack / throw", &"secondary": "Item's second action",
	&"slot_next": "Next slot", &"slot_prev": "Previous slot", &"holster": "Holster", &"equip": "Put in inventory",
	&"push_to_talk": "Push to talk", &"pause": "Pause menu", &"debug_console": "Debug console",
}

var _settings: SettingsService
var _rebinding_action: StringName = &""
var _bind_buttons: Dictionary[StringName, Button] = {}
## Refreshers for every widget on a tab (after a reset).
var _refreshers: Dictionary[StringName, Array] = {}


func _ready() -> void:
	if _settings == null:
		_settings = Settings
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = PANEL_SIZE
	column.add_theme_constant_override("separation", 8)
	center.add_child(column)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	_build_audio(_add_tab(tabs, "Audio"))
	_build_video(_add_tab(tabs, "Video"))
	_build_controls(_add_tab(tabs, "Controls"))
	_build_accessibility(_add_tab(tabs, "Accessibility"))
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(close)
	column.add_child(back)


## For tests: use this settings object instead of the autoload (before adding to the tree).
func use_settings(settings: SettingsService) -> void:
	_settings = settings


## Saves what voice's mic panel changed, then goes back to the menu that opened it.
func close() -> void:
	_settings.set_value(SettingsService.AUDIO, &"mic_sensitivity", Voice.get_mic_sensitivity())
	var back_to: StringName = _settings.return_screen
	_settings.return_screen = &""
	if back_to != &"":
		UI.show_screen(back_to)
	else:
		UI.close_screen()


## Is it waiting for a key to rebind? (tests)
func get_rebinding_action() -> StringName:
	return _rebinding_action


func start_rebind(action: StringName) -> void:
	_rebinding_action = action
	_bind_buttons[action].text = WAITING_TEXT


func _input(event: InputEvent) -> void:
	if _rebinding_action == &"":
		if event.is_action_pressed(InputActions.PAUSE):
			close()
			get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if (key == null or not key.pressed or key.echo) and (mouse == null or not mouse.pressed):
		return
	get_viewport().set_input_as_handled()
	var action: StringName = _rebinding_action
	_rebinding_action = &""
	if key != null and key.physical_keycode == KEY_ESCAPE and action != InputActions.PAUSE:
		_bind_buttons[action].text = _settings.get_binding_text(action)
		return
	_settings.rebind(action, event)
	_bind_buttons[action].text = _settings.get_binding_text(action)


# --- Tabs ------------------------------------------------------------------------------------

func _add_tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	return rows


func _build_audio(rows: VBoxContainer) -> void:
	var section: StringName = SettingsService.AUDIO
	_slider(rows, section, &"master", "Master volume", 0.0, 1.0, 0.05, true)
	_slider(rows, section, &"music", "Music", 0.0, 1.0, 0.05, true)
	_slider(rows, section, &"sfx", "Sound effects", 0.0, 1.0, 0.05, true)
	_slider(rows, section, &"voice", "Voice chat", 0.0, 1.0, 0.05, true)
	_slider(rows, section, &"ui", "Menu sounds", 0.0, 1.0, 0.05, true)
	_mic_device(rows)
	_check(rows, section, &"push_to_talk", "Push to talk (hold %s)" % _settings.get_binding_text(InputActions.PUSH_TO_TALK))
	_check(rows, section, &"reduce_voice_effects", "Quieter voice effects (mutations)")
	rows.add_child(MicSensitivityPanel.new())
	_reset_button(rows, section)


func _build_video(rows: VBoxContainer) -> void:
	var section: StringName = SettingsService.VIDEO
	_check(rows, section, &"fullscreen", "Fullscreen")
	_check(rows, section, &"vsync", "VSync")
	_slider(rows, section, &"fov", "Field of view", 60.0, 110.0, 1.0, false)
	_slider(rows, section, &"max_fps", "Max FPS (0 = no limit)", 0.0, 240.0, 10.0, false)
	_slider(rows, section, &"resolution_scale", "3D resolution", 0.5, 1.0, 0.05, true)
	_reset_button(rows, section)


func _build_controls(rows: VBoxContainer) -> void:
	var section: StringName = SettingsService.CONTROLS
	_slider(rows, section, &"mouse_sensitivity", "Mouse sensitivity", 0.02, 1.0, 0.01, false)
	_check(rows, section, &"invert_y", "Invert mouse Y")
	_check(rows, section, &"toggle_crouch", "Crouch: tap to switch (not hold)")
	_check(rows, section, &"toggle_sprint", "Sprint: tap to switch (not hold)")
	_reset_button(rows, section)
	var keys_title := Label.new()
	keys_title.text = "Keys (click, then press the new key or mouse button)"
	rows.add_child(keys_title)
	for action: StringName in SettingsService.rebindable_actions():
		var row := _row(rows, _action_name(action))
		var button := Button.new()
		button.name = "Bind_%s" % action
		button.text = _settings.get_binding_text(action)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(start_rebind.bind(action))
		row.add_child(button)
		_bind_buttons[action] = button
	var reset := Button.new()
	reset.name = "ResetKeysButton"
	reset.text = "Reset all keys"
	reset.pressed.connect(_on_reset_keys)
	rows.add_child(reset)


func _build_accessibility(rows: VBoxContainer) -> void:
	var section: StringName = SettingsService.ACCESSIBILITY
	_check(rows, section, &"subtitles", "Subtitles for important sounds")
	_check(rows, section, &"reduce_motion", "Reduce motion (no head bob or camera shake)")
	_slider(rows, section, &"camera_shake", "Camera shake", 0.0, 1.0, 0.05, true)
	_slider(rows, section, &"text_scale", "Menu and text size", 0.75, 2.0, 0.05, true)
	_check(rows, section, &"high_contrast_glow", "Stronger glow on important objects")
	_reset_button(rows, section)


# --- Widgets ---------------------------------------------------------------------------------

func _row(rows: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	rows.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)
	return row


func _slider(rows: VBoxContainer, section: StringName, key: StringName, text: String, low: float, high: float,
		step: float, percent: bool) -> void:
	var row := _row(rows, text)
	var slider := HSlider.new()
	slider.name = "Slider_%s" % key
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(60, 0)
	row.add_child(value_label)
	var show_value := func(value: float) -> void:
		if percent:
			value_label.text = "%d%%" % roundi(value * 100.0)
		elif step < 1.0:
			value_label.text = "%.2f" % value
		else:
			value_label.text = str(int(value))
	var refresh := func() -> void:
		slider.set_value_no_signal(_settings.get_float(section, key))
		show_value.call(slider.value)
	refresh.call()
	# Whole-number settings (max FPS) are saved as int, the rest as float.
	var is_int: bool = _settings.get_value(section, key) is int
	slider.value_changed.connect(func(value: float) -> void:
		show_value.call(value)
		if is_int:
			_settings.set_value(section, key, roundi(value))
		else:
			_settings.set_value(section, key, value))
	_add_refresher(section, refresh)


func _check(rows: VBoxContainer, section: StringName, key: StringName, text: String) -> void:
	var box := CheckButton.new()
	box.name = "Check_%s" % key
	box.text = text
	box.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	rows.add_child(box)
	var refresh := func() -> void: box.set_pressed_no_signal(_settings.get_bool(section, key))
	refresh.call()
	box.toggled.connect(func(on: bool) -> void: _settings.set_value(section, key, on))
	_add_refresher(section, refresh)


func _mic_device(rows: VBoxContainer) -> void:
	var row := _row(rows, "Microphone")
	var picker := OptionButton.new()
	picker.name = "MicDevice"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.clip_text = true
	row.add_child(picker)
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	for device: String in devices:
		picker.add_item(device)
	var refresh := func() -> void:
		var index: int = devices.find(str(_settings.get_value(SettingsService.AUDIO, &"mic_device")))
		picker.select(maxi(index, 0))
	refresh.call()
	picker.item_selected.connect(func(index: int) -> void:
		_settings.set_value(SettingsService.AUDIO, &"mic_device", devices[index]))
	_add_refresher(SettingsService.AUDIO, refresh)


func _reset_button(rows: VBoxContainer, section: StringName) -> void:
	var button := Button.new()
	button.name = "Reset_%s" % section
	button.text = "Reset to defaults"
	button.pressed.connect(func() -> void:
		_settings.reset_section(section)
		for refresh: Callable in _refreshers.get(section, []):
			refresh.call())
	rows.add_child(button)


func _add_refresher(section: StringName, refresh: Callable) -> void:
	if not _refreshers.has(section):
		_refreshers[section] = []
	_refreshers[section].append(refresh)


func _on_reset_keys() -> void:
	_settings.reset_bindings()
	for action: StringName in _bind_buttons:
		_bind_buttons[action].text = _settings.get_binding_text(action)


func _action_name(action: StringName) -> String:
	if ACTION_NAMES.has(action):
		return ACTION_NAMES[action]
	return String(action).capitalize()
