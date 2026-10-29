extends GutTest
## Tests for settings_input (docs/systems/settings_input.md). Each test uses its own settings file in
## user:// (never the player's real settings.cfg). Key bindings are global, so after_each puts the
## real ones back.

const TEST_PATH: String = "user://test_settings.cfg"


func before_each() -> void:
	_delete_file()


func after_each() -> void:
	_delete_file()
	# Back to the player's own bindings and volumes (the tests changed the global ones).
	Settings.load_file()


func _delete_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _settings() -> SettingsService:
	var settings := SettingsService.new()
	settings.use_file(TEST_PATH)
	add_child_autofree(settings)
	return settings


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func test_defaults_when_no_file() -> void:
	var settings := _settings()
	var defaults: Dictionary[StringName, Dictionary] = SettingsService.defaults()
	for section: StringName in defaults:
		for key: StringName in defaults[section]:
			assert_eq(settings.get_value(section, key), defaults[section][key], "%s/%s is its default" % [section, key])
	assert_eq(settings.get_mouse_sensitivity(), 0.066, "HL2-like default (2026-10-29)")
	assert_eq(settings.get_fov(), 74.0, "HL2-like default (2026-10-29)")
	assert_false(FileAccess.file_exists(TEST_PATH), "reading doesn't make a file")


func test_set_value_saves_and_reloads() -> void:
	var settings := _settings()
	settings.set_value(SettingsService.CONTROLS, &"mouse_sensitivity", 0.6)
	settings.set_value(SettingsService.ACCESSIBILITY, &"subtitles", false)
	var reloaded := _settings()
	assert_eq(reloaded.get_mouse_sensitivity(), 0.6, "survives a restart")
	assert_false(reloaded.is_subtitles_on())


func test_set_value_emits_settings_changed() -> void:
	var settings := _settings()
	watch_signals(EventBus)
	settings.set_value(SettingsService.VIDEO, &"fov", 100.0)
	assert_signal_emitted_with_parameters(EventBus, "settings_changed", [SettingsService.VIDEO])


func test_unknown_keys_are_kept() -> void:
	var file := ConfigFile.new()
	file.set_value("future", "new_thing", 42)
	file.save(TEST_PATH)
	var settings := _settings()
	settings.set_value(SettingsService.AUDIO, &"music", 0.3)
	var check := ConfigFile.new()
	check.load(TEST_PATH)
	assert_eq(check.get_value("future", "new_thing", 0), 42, "a setting from a newer version isn't lost")
	assert_eq(check.get_value("meta", "version", 0), SettingsService.FILE_VERSION)


func test_reset_section_restores_defaults() -> void:
	var settings := _settings()
	settings.set_value(SettingsService.CONTROLS, &"invert_y", true)
	settings.set_value(SettingsService.AUDIO, &"music", 0.1)
	settings.reset_section(SettingsService.CONTROLS)
	assert_false(settings.is_invert_y(), "controls back to default")
	assert_eq(settings.get_value(SettingsService.AUDIO, &"music"), 0.1, "other sections untouched")


func test_rebind_replaces_event() -> void:
	var settings := _settings()
	settings.rebind(InputActions.JUMP, _key(KEY_J))
	var events: Array[InputEvent] = InputMap.action_get_events(InputActions.JUMP)
	assert_eq(events.size(), 1, "only the new key")
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_J)
	assert_eq(settings.get_binding_text(InputActions.JUMP), "J")
	InputMap.action_erase_events(InputActions.JUMP)
	_settings()
	assert_eq(settings.get_binding_text(InputActions.JUMP), "J", "loaded again after a restart")


func test_rebind_to_a_mouse_button() -> void:
	var settings := _settings()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_XBUTTON1
	click.pressed = true
	settings.rebind(InputActions.USE, click)
	assert_eq(settings.get_binding_text(InputActions.USE), "Mouse 4")


func test_reset_bindings_restores_input_actions_defaults() -> void:
	var settings := _settings()
	settings.rebind(InputActions.JUMP, _key(KEY_J))
	settings.rebind(InputActions.slot_action(3), _key(KEY_Z))
	settings.reset_bindings()
	assert_eq(settings.get_binding_text(InputActions.JUMP), "Space")
	assert_eq(settings.get_binding_text(InputActions.slot_action(3)), "3")
	assert_eq(settings.get_binding_text(InputActions.PRIMARY), "Mouse 1")
	_settings()
	assert_eq(settings.get_binding_text(InputActions.JUMP), "Space", "the reset was saved too")


func test_every_action_can_be_rebound() -> void:
	var settings := _settings()
	for action: StringName in SettingsService.rebindable_actions():
		assert_true(InputMap.has_action(action), "%s exists" % action)
		settings.rebind(action, _key(KEY_K))
		assert_eq(settings.get_binding_text(action), "K", "%s rebound" % action)


func test_volume_applies_to_audio_bus() -> void:
	var settings := _settings()
	settings.set_value(SettingsService.AUDIO, &"music", 0.5)
	var index: int = AudioServer.get_bus_index(&"Music")
	assert_gte(index, 0, "the Music bus exists")
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.5, 0.001)
	assert_eq(settings.get_volume_linear(&"Music"), 0.5)


func test_reduce_motion_turns_camera_shake_off() -> void:
	var settings := _settings()
	settings.set_value(SettingsService.ACCESSIBILITY, &"camera_shake", 0.5)
	assert_eq(settings.get_camera_shake_scale(), 0.5)
	settings.set_value(SettingsService.ACCESSIBILITY, &"reduce_motion", true)
	assert_eq(settings.get_camera_shake_scale(), 0.0)


func test_toggle_sprint_switches_on_a_tap() -> void:
	var settings := _settings()
	settings.set_value(SettingsService.CONTROLS, &"toggle_sprint", true)
	Input.action_press(InputActions.SPRINT)
	assert_true(settings.is_action_on(InputActions.SPRINT), "tap: on")
	Input.action_release(InputActions.SPRINT)
	assert_true(settings.is_action_on(InputActions.SPRINT), "still on after letting go")
	Input.action_press(InputActions.SPRINT)
	assert_false(settings.is_action_on(InputActions.SPRINT), "tap again: off")
	Input.action_release(InputActions.SPRINT)


func test_screen_rebinds_with_the_next_key() -> void:
	var settings := _settings()
	var screen := (load("res://systems/settings_input/settings_screen.tscn") as PackedScene).instantiate() as SettingsScreen
	screen.use_settings(settings)
	add_child_autofree(screen)
	screen.start_rebind(InputActions.DROP)
	assert_eq(screen.get_rebinding_action(), InputActions.DROP, "waiting for a key")
	get_viewport().push_input(_key(KEY_G))
	assert_eq(screen.get_rebinding_action(), &"", "done")
	assert_eq(settings.get_binding_text(InputActions.DROP), "G")
	screen.start_rebind(InputActions.DROP)
	get_viewport().push_input(_key(KEY_ESCAPE))
	assert_eq(settings.get_binding_text(InputActions.DROP), "G", "Esc cancels")
