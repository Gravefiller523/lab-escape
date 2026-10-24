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
# NEW 2026-10-24 (built):
func open(from: StringName) -> void                 # opens the Settings screen; Back returns to `from` (UI.SCREEN_PAUSE / UI.SCREEN_MAIN_MENU)
var return_screen: StringName                         # where Back goes (set by open)
func get_float(section, key) -> float / get_int(section, key) -> int / get_bool(section, key) -> bool   # typed get_value
func is_subtitles_on() -> bool                       # ui.caption reads it
func is_action_on(action: StringName) -> bool        # sprint/crouch with the toggle settings (player calls it every physics tick)
static func defaults() -> Dictionary[StringName, Dictionary]
static func rebindable_actions() -> Array[StringName]   # every InputActions action, slot keys included
static func event_text(event: InputEvent) -> String
func load_file() -> void                             # read the file again and apply everything
func use_file(path: String) -> void                  # tests only: another file, never applied to the window or voice
const SCREEN_SETTINGS: StringName = &"settings"      # the UI screen it registers
class_name SettingsScreen extends Control             # systems/settings_input/settings_screen.gd
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
- [x] Changing a setting applies at once and survives a restart.
- [x] Every action in `InputActions` can be rebound; reset works.
- [x] Accessibility options exist and are read by player (reduce motion) and ui (text scale, subtitles). *Text scale and subtitles work; reduce motion and camera shake are stored and readable, but the player has no head bob or camera shake yet.*

## Open design questions
- DEFAULT: settings are per PC, not Steam-Cloud synced.

## Changelog
- 2026-10-07: spec created.
- 2026-10-24: built (Phase 1b). Changes marked above. The `Settings` autoload (`systems/settings_input/settings.gd`,
  `class_name SettingsService`) loads `user://settings.cfg` at startup and applies it: bus volumes (Master, Music, SFX,
  Voice, UI), push-to-talk, mic sensitivity (NEW key `audio/mic_sensitivity`, default `Config.game.voice_mic_sensitivity`)
  and mic device to voice, FOV, max FPS, 3D resolution, fullscreen and VSync, text scale (the window's
  `content_scale_factor`, so every menu and the HUD grow), and key bindings (saved in a `[bindings]` section as
  `var_to_str` of the event; only rebound actions are stored). Fullscreen and VSync are not applied when running from
  the editor, so 2-window tests stay windowed. The screen has tabs Audio, Video, Controls (with rebinding: click,
  press a key or mouse button, Esc cancels) and Accessibility, and a Reset button per tab and for keys. Voice's
  MicSensitivityPanel moved from the pause menu to Settings > Audio; Back saves its value.

## HANDOFF

**Done:** everything in the spec. 14 GUT tests in `tests/unit/settings_input/` (the spec's five, plus reload,
the signal, unknown keys kept, reset, mouse-button names, every action rebindable, reduce motion, the sprint
toggle, and the screen's rebinding). Test scene: `systems/settings_input/test/settings_test.tscn` (F6; F1 reopens).

**Other systems touched (small hooks, as the ui and player specs asked):**
- ui: Settings buttons in the main and pause menus; `UI.caption` only shows with subtitles on; the main menu's
  `host`/`join` launch options run once per game start (they used to run again when the menu was rebuilt).
- player: mouse sensitivity, invert Y, FOV (live) and the sprint/crouch toggles come from Settings.
  `PlayerTuning.mouse_sensitivity` and `fov` are marked `@deprecated` (kept, not used).

**Foundation changes:** none. **project.godot:** autoload `Settings` (after GameFlow). **EventBus:** none new
(emits the existing `settings_changed`).

**Not done / for later (OPEN):**
- `audio/reduce_voice_effects`: saved, but voice doesn't read it yet (voice: soften mutation voice effects for
  this listener when it's on).
- `accessibility/high_contrast_glow`: saved, nothing reads it yet (glowing gems are gone; use it for DNA vials,
  data drives or lift parts later).
- Head bob and camera shake don't exist yet: whoever adds them reads `get_camera_shake_scale()` (0 with reduce motion).
- Rebinding allows the same key on two actions (no warning yet).
- The screen uses Godot's default look until ui adds `lab_theme.tres`.
