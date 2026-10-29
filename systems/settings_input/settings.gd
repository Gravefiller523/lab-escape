class_name SettingsService
extends Node
## Autoload "Settings": the player's own settings and key bindings. Spec: docs/systems/settings_input.md.
## Saved in user://settings.cfg on this PC (a Godot ConfigFile, nothing is sent over the network).
## set_value applies a setting at once, saves the file and emits EventBus.settings_changed(section).
## Unknown keys in the file are kept; missing ones use DEFAULTS.

const FILE_PATH: String = "user://settings.cfg"
const FILE_VERSION: int = 1
const META: StringName = &"meta"
const BINDINGS: StringName = &"bindings"
const SCREEN_SETTINGS: StringName = &"settings"
const SETTINGS_SCREEN: PackedScene = preload("res://systems/settings_input/settings_screen.tscn")

const AUDIO: StringName = &"audio"
const VIDEO: StringName = &"video"
const CONTROLS: StringName = &"controls"
const ACCESSIBILITY: StringName = &"accessibility"
## Audio bus for each volume key (the buses are made by audio's Sound autoload).
const VOLUME_BUSES: Dictionary[StringName, StringName] = {
	&"master": &"Master", &"music": &"Music", &"sfx": &"SFX", &"voice": &"Voice", &"ui": &"UI",
}
const MOUSE_BUTTON_NAMES: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "Mouse 1", MOUSE_BUTTON_RIGHT: "Mouse 2", MOUSE_BUTTON_MIDDLE: "Mouse 3",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}

## Where the screen's Back button goes (&"pause" or &"main_menu").
var return_screen: StringName = &""

var _file := ConfigFile.new()
var _path: String = FILE_PATH
var _live: bool = true
var _toggle_on: Dictionary[StringName, bool] = {}
var _was_pressed: Dictionary[StringName, bool] = {}


func _ready() -> void:
	if not _live:
		return
	load_file()
	UI.register_screen(SCREEN_SETTINGS, SETTINGS_SCREEN)


## Opens the Settings screen. Back returns to `from` (&"pause" or &"main_menu"; &"" just closes it).
func open(from: StringName) -> void:
	return_screen = from
	UI.show_screen(SCREEN_SETTINGS)


## For tests: use this file instead of user://settings.cfg (and don't touch the real one).
func use_file(path: String) -> void:
	_live = false
	_path = path
	load_file()


## Every setting with its default value, by section.
static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		AUDIO: {
			&"master": 1.0, &"music": 0.7, &"sfx": 1.0, &"voice": 1.0, &"ui": 0.8,
			&"mic_device": "Default", &"mic_sensitivity": Config.game.voice_mic_sensitivity,
			&"push_to_talk": Config.game.voice_push_to_talk_default, &"reduce_voice_effects": false,
		},
		VIDEO: {&"fullscreen": true, &"vsync": true, &"fov": 74.0, &"max_fps": 0, &"resolution_scale": 1.0},
		CONTROLS: {&"mouse_sensitivity": 0.066, &"invert_y": false, &"toggle_crouch": false, &"toggle_sprint": false},
		ACCESSIBILITY: {
			&"subtitles": true, &"reduce_motion": false, &"camera_shake": 1.0, &"text_scale": 1.0,
			&"high_contrast_glow": false,
		},
	}


## Reads the file (missing file: all defaults) and applies everything, bindings included.
func load_file() -> void:
	_file = ConfigFile.new()
	if FileAccess.file_exists(_path) and _file.load(_path) != OK:
		push_warning("Settings: could not read %s, using defaults." % _path)
		_file = ConfigFile.new()
	_apply_bindings()
	for section: StringName in defaults():
		_apply(section)


func get_value(section: StringName, key: StringName) -> Variant:
	var section_defaults: Dictionary = defaults().get(section, {})
	var fallback: Variant = section_defaults.get(key)
	return _file.get_value(section, key, fallback)


## Typed versions of get_value (for numbers and on/off settings).
func get_float(section: StringName, key: StringName) -> float:
	var value: Variant = get_value(section, key)
	return value as float if value is float else float(value as int)


func get_int(section: StringName, key: StringName) -> int:
	var value: Variant = get_value(section, key)
	return value as int if value is int else roundi(value as float)


func get_bool(section: StringName, key: StringName) -> bool:
	return get_value(section, key) as bool


## Applies at once, saves and emits EventBus.settings_changed(section).
func set_value(section: StringName, key: StringName, value: Variant) -> void:
	_file.set_value(section, key, value)
	_save()
	_apply(section)
	EventBus.settings_changed.emit(section)


## Back to the defaults for one section (bindings: use reset_bindings).
func reset_section(section: StringName) -> void:
	if _file.has_section(section):
		_file.erase_section(section)
	_save()
	_apply(section)
	EventBus.settings_changed.emit(section)


# --- Shortcuts other systems read often ------------------------------------------------------

func get_mouse_sensitivity() -> float:
	return get_float(CONTROLS, &"mouse_sensitivity")


func is_invert_y() -> bool:
	return get_bool(CONTROLS, &"invert_y")


func get_fov() -> float:
	return get_float(VIDEO, &"fov")


## &"Master", &"Music", &"SFX", &"Voice" or &"UI".
func get_volume_linear(bus: StringName) -> float:
	for key: StringName in VOLUME_BUSES:
		if VOLUME_BUSES[key] == bus:
			return get_float(AUDIO, key)
	return 1.0


func is_push_to_talk() -> bool:
	return get_bool(AUDIO, &"push_to_talk")


## Head bob and camera shake off.
func get_reduce_motion() -> bool:
	return get_bool(ACCESSIBILITY, &"reduce_motion")


## 0 with reduce motion on, otherwise the camera_shake slider.
func get_camera_shake_scale() -> float:
	return 0.0 if get_reduce_motion() else get_float(ACCESSIBILITY, &"camera_shake")


func is_subtitles_on() -> bool:
	return get_bool(ACCESSIBILITY, &"subtitles")


## Local: is sprint (or crouch) on? Reads the toggle settings: tap to switch, or hold. Called every
## physics tick by the player; each new press (down after being up) switches a toggle.
func is_action_on(action: StringName) -> bool:
	var pressed: bool = Input.is_action_pressed(action)
	var new_press: bool = pressed and not _was_pressed.get(action, false)
	_was_pressed[action] = pressed
	var toggle_key: StringName = &"toggle_sprint" if action == InputActions.SPRINT else &"toggle_crouch"
	if not get_bool(CONTROLS, toggle_key):
		return pressed
	if new_press:
		_toggle_on[action] = not _toggle_on.get(action, false)
	return _toggle_on.get(action, false)


# --- Rebinding --------------------------------------------------------------------------------

## Every action the player can rebind (all of InputActions).
static func rebindable_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for action: StringName in InputActions.DEFAULT_KEYS:
		actions.append(action)
	for action: StringName in InputActions.DEFAULT_MOUSE_BUTTONS:
		actions.append(action)
	for slot_number: int in range(1, InputActions.MAX_SLOT_KEYS + 1):
		actions.append(InputActions.slot_action(slot_number))
	return actions


## The action now uses only this key or mouse button. Saved.
func rebind(action: StringName, event: InputEvent) -> void:
	var clean: InputEvent = _clean_event(event)
	if clean == null or not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	_file.set_value(BINDINGS, action, var_to_str(clean))
	_save()
	EventBus.settings_changed.emit(BINDINGS)


## Every action back to InputActions' default keys.
func reset_bindings() -> void:
	if _file.has_section(BINDINGS):
		_file.erase_section(BINDINGS)
	_save()
	_restore_default_bindings()
	EventBus.settings_changed.emit(BINDINGS)


## "E", "Space", "Mouse 1". "" if nothing is bound.
func get_binding_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return event_text(events[0]) if not events.is_empty() else ""


static func event_text(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return MOUSE_BUTTON_NAMES.get(mouse.button_index, "Mouse %d" % mouse.button_index)
	return event.as_text()


## Only keys and mouse buttons, and only what matters (no "pressed", no modifiers).
func _clean_event(event: InputEvent) -> InputEvent:
	var key := event as InputEventKey
	if key != null:
		var clean_key := InputEventKey.new()
		clean_key.physical_keycode = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return clean_key
	var mouse := event as InputEventMouseButton
	if mouse != null:
		var clean_mouse := InputEventMouseButton.new()
		clean_mouse.button_index = mouse.button_index
		return clean_mouse
	return null


func _restore_default_bindings() -> void:
	for action: StringName in rebindable_actions():
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	InputActions.ensure_registered()


func _apply_bindings() -> void:
	_restore_default_bindings()
	if not _file.has_section(BINDINGS):
		return
	for key: String in _file.get_section_keys(BINDINGS):
		var event := str_to_var(str(_file.get_value(BINDINGS, key))) as InputEvent
		if event != null and InputMap.has_action(StringName(key)):
			InputMap.action_erase_events(StringName(key))
			InputMap.action_add_event(StringName(key), event)


# --- Applying -------------------------------------------------------------------------------

func _apply(section: StringName) -> void:
	if not _live:
		# A test copy only sets bus volumes and toggles: never the window, video or voice.
		if section == AUDIO:
			_apply_volumes()
		elif section == CONTROLS:
			_toggle_on.clear()
		return
	match section:
		AUDIO:
			_apply_volumes()
			Voice.set_push_to_talk(is_push_to_talk())
			Voice.set_mic_sensitivity(get_float(AUDIO, &"mic_sensitivity"))
			_apply_mic_device()
		VIDEO:
			_apply_video()
		CONTROLS:
			_toggle_on.clear()
		ACCESSIBILITY:
			get_tree().root.content_scale_factor = clampf(get_float(ACCESSIBILITY, &"text_scale"), 0.75, 2.0)


func _apply_volumes() -> void:
	SoundService.ensure_buses()
	for key: StringName in VOLUME_BUSES:
		var index: int = AudioServer.get_bus_index(VOLUME_BUSES[key])
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(get_float(AUDIO, key), 0.0001)))


func _apply_mic_device() -> void:
	var device: String = str(get_value(AUDIO, &"mic_device"))
	if AudioServer.get_input_device_list().has(device):
		AudioServer.input_device = device


func _apply_video() -> void:
	Engine.max_fps = maxi(get_int(VIDEO, &"max_fps"), 0)
	get_viewport().scaling_3d_scale = clampf(get_float(VIDEO, &"resolution_scale"), 0.5, 1.0)
	# Not from the editor: it would make every test window (Debug > Customize Run Instances) fullscreen.
	if DisplayServer.get_name() == "headless" or OS.has_feature("editor"):
		return
	var fullscreen: bool = get_bool(VIDEO, &"fullscreen")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_bool(VIDEO, &"vsync") else DisplayServer.VSYNC_DISABLED)


func _save() -> void:
	_file.set_value(META, &"version", FILE_VERSION)
	var error: int = _file.save(_path)
	if error != OK:
		push_warning("Settings: could not save %s (%s)." % [_path, error_string(error)])
