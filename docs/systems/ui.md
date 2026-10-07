# ui

Folder: `res://systems/ui/` · Autoload: `UI` · Size: L (built in slices across phases)

## Purpose
Everything drawn on screen: main menu (Host / Join / Settings / Quit), the HUD (health, inventory bar,
interaction prompt and hold ring, held-object hint, lift parts counter, toasts, who is speaking),
pause menu, settings screens, death/ghost screen and reprint status, the jacket closet screen, the
vendor screen text, and the run summary. Reads other systems' public APIs and EventBus; owns no game rules.

**Not responsible for:** game logic of any kind, settings storage (settings_input), 3D in-world screens owned by other systems (vendor machine display can use ui widgets).

## Public API
```gdscript
# Autoload UI
func show_screen(screen: StringName) -> void    # &"main_menu", &"pause", &"settings", &"closet", &"run_summary"
func close_screen() -> void
func is_screen_open() -> bool                   # player input is disabled while true
func toast(text: String, seconds: float = 3.0) -> void
func caption(text: String) -> void              # subtitle for an important sound; shown only if subtitles are on
func register_screen(screen: StringName, scene: PackedScene) -> void   # other systems can add screens
```
HUD widgets are separate scenes under `systems/ui/hud/` so they can be built one by one. The player
list and speaking icons size themselves from `Net.get_player_ids()` (never 4 fixed boxes). Inventory
bar draws `InventoryComponent.get_slot_count()` slots.

Accessibility: text scale, subtitles/captions (other systems emit `toast_requested` or call
`UI.caption(text)` for important sounds), high contrast, all from settings_input.

## EventBus
- Emits: none required (anyone may emit `toast_requested`; ui shows it).
- Listens: `game_state_changed`, `inventory_changed`, `player_died`, `player_reprinted`, `lift_part_delivered`,
  `player_speaking_changed`, `toast_requested`, `run_ended`, `cosmetic_unlocked`, `achievement_unlocked`, `settings_changed`.

## Data it owns and saves
Theme (`systems/ui/theme/lab_theme.tres`), fonts, icons. Saves nothing.

## Adding content
None: item icons, names and descriptions come from content data.

## Multiplayer
Local only; it reads synced state.

## Dependencies and stubs
game_flow, steam_session (host/join buttons), settings_input, inventory, death_respawn, cargo_lift.
Stub each with a fake object that has the same functions, so screens can be built in isolation.

## Test scene and GUT tests
Test scenes: `hud_test.tscn` (fake player with buttons to change health, slots, prompts, speakers 1 to 8), `menus_test.tscn`.
GUT tests: `test_inventory_bar_matches_slot_count`, `test_player_list_scales_to_8`, `test_toast_queue`,
`test_pause_disables_player_input`, `test_text_scale_applies`.

## Acceptance criteria
- [ ] Main menu can host (Steam and local) and join.
- [ ] HUD shows health, slots, prompt, lift parts and speakers for 1 to 8 players.
- [ ] Pause and settings work in multiplayer without pausing the game for others.
- [ ] Death screen shows ghost controls and reprint cost.

## Open design questions
- DEFAULT: no pausing the game in multiplayer (pause menu only opens a menu); solo pauses for real.

## Changelog
- 2026-10-07: spec created.
