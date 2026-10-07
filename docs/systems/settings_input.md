# settings_input

Folder: `res://systems/settings_input/` · Autoload: `Settings` · Size: S · Phase 1b

## Purpose
Stores and applies the player's settings (audio volumes, microphone, video, mouse, accessibility) and
lets them rebind keys. Saves to `user://settings.cfg` on their own PC.

**Not responsible for:** the settings screen's look (ui draws it using this API), the cosmetic/profile save (save_load), the list of action names (foundation's `InputActions`).

## Public API
```gdscript
func get_value(section: StringName, key: StringName) -> Variant
func set_value(section: StringName, key: StringName, value: Variant) -> void   # applies, saves, emits settings_changed
func reset_section(section: StringName) -> void
# Shortcuts other systems use every frame:
func get_mouse_sensitivity() -> float
func is_invert_y() -> bool
func get_fov() -> float
func get_volume_linear(bus: StringName) -> float     # &"Master", &"Music", &"SFX", &"Voice", &"UI"
func is_push_to_talk() -> bool
func get_reduce_motion() -> bool                     # head bob and camera shake off
func get_camera_shake_scale() -> float
# Rebinding:
func rebind(action: StringName, event: InputEvent) -> void
func reset_bindings() -> void
func get_binding_text(action: StringName) -> String  # "E", "Mouse 1"
```

Settings (section/key, default):
- audio: master 1.0, music 0.7, sfx 1.0, voice 1.0, ui 0.8, mic_device "Default", push_to_talk `Config.game.voice_push_to_talk_default`, reduce_voice_effects false
- video: fullscreen true, vsync true, fov 85, max_fps 0, resolution_scale 1.0
- controls: mouse_sensitivity 0.25, invert_y false, toggle_crouch false, toggle_sprint false
- accessibility: subtitles true (captions for important sounds), reduce_motion false, camera_shake 1.0,
  text_scale 1.0, high_contrast_glow false (stronger gem/part glow colours)

## EventBus
- Emits: `settings_changed(section)`.
- Listens: none.

## Data it owns and saves
`user://settings.cfg` (Godot `ConfigFile`), with `[meta] version=1`. Unknown keys are kept; missing keys use defaults.

## Adding content
None. New settings: add a default in the defaults table and a getter if it's read often.

## Multiplayer
Local only. Nothing is synced. (Push-to-talk is read by voice locally.)

## Dependencies and stubs
Foundation only. Others can stub it by reading the defaults table.

## Test scene and GUT tests
Test scene: a bare settings panel with a slider per setting and a rebind button.
GUT tests: `test_defaults_when_no_file`, `test_set_value_saves_and_reloads`, `test_rebind_replaces_event`,
`test_reset_bindings_restores_input_actions_defaults`, `test_volume_applies_to_audio_bus`.

## Acceptance criteria
- [ ] Changing a setting applies at once and survives a restart.
- [ ] Every action in `InputActions` can be rebound; reset works.
- [ ] Accessibility options exist and are read by player (reduce motion) and ui (text scale, subtitles).

## Open design questions
- DEFAULT: settings are per PC, not Steam-Cloud synced.

## Changelog
- 2026-10-07: spec created.
