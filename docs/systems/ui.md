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
func get_open_screen() -> StringName            # NEW 2026-10-17: &"" if none
func leave_game() -> void                       # NEW 2026-10-17: leave the lobby and go back to the main menu
func get_toast_text() -> String                 # NEW 2026-10-17: the toast on screen now (tests)
func use_flow(flow: GameFlowStub) -> void       # NEW 2026-10-17: tests only
const SCREEN_MAIN_MENU: StringName = &"main_menu"   # NEW 2026-10-17
const SCREEN_PAUSE: StringName = &"pause"           # NEW 2026-10-17
```
NEW 2026-10-17: the autoload script is `systems/ui/ui.gd` (`class_name UIService`, a CanvasLayer).
The game's start scene (`run/main_scene`) is `systems/ui/main_menu_background.tscn`, which opens the main menu.

NEW 2026-10-17, **scene changes (STUB for game_flow, `systems/ui/stubs/game_flow_stub.gd`):** after
`SteamSession.lobby_created` or `lobby_joined` *while on the main menu*, the ui loads
`break_room.tscn`. After `connection_lost`, `Net.join_refused` or "Leave game" *while in the Break Room*,
it goes back to the main menu and shows why. Any other scene (systems' test scenes) is left alone;
only a toast is shown. When game_flow exists, it takes this over.
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

NEW 2026-10-17 (Phase 1a slice): `systems/ui/test/menus_test.tscn` (the main menu scene; or just
press F5). Main menu launch options after `--`: `host`, `join`, `host_steam`, `port=7790`.
GUT tests (`tests/unit/ui/test_ui.gd`): `test_toast_queue`, `test_pause_disables_player_input`,
NEW `test_host_local_from_menu_goes_to_break_room`, `test_connection_lost_returns_to_menu`,
`test_join_refused_returns_to_menu`, `test_test_scenes_are_left_alone`. The HUD tests come with the HUD.

## Acceptance criteria
- [x] Main menu can host (Steam and local) and join. *(Local host/join checked with 2 windows; Steam
  host checked on Zachary's PC; joining over Steam needs the two-PC test.)*
- [ ] HUD shows health, slots, prompt, lift parts and speakers for 1 to 8 players.
- [ ] Pause and settings work in multiplayer without pausing the game for others.
- [ ] Death screen shows ghost controls and reprint cost.

## Open design questions
- DEFAULT: no pausing the game in multiplayer (pause menu only opens a menu); solo pauses for real.

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: Phase 1a slice built: main menu, small pause menu, toasts, the main scene and the
  game_flow scene-change stub. Added `get_open_screen`, `leave_game`, `get_toast_text`, `use_flow`.
- 2026-10-17 (voice branch): the Esc menu shows voice's `MicSensitivityPanel` (mic sensitivity slider and level bar).
- 2026-10-18 (debug_console branch, asked by Zachary): when you play solo, the Esc menu also shows "Testing on one PC"
  (address, port, Host local, Join local), so a test scene run with F6 can become a 2-window test. The scene stays
  open. Test: `test_pause_menu_hosts_local_in_test_scenes`.
- 2026-10-18 (game_flow branch): `GameFlowStub` now passes the ui's calls on to the GameFlow autoload
  (`go_to_break_room`, `return_to_main_menu`); `is_in_break_room` is true in every scene GameFlow runs, so
  losing the host on a floor also goes back to the menu.

## HANDOFF
**Done (Phase 1a slice):** the `UI` autoload; main menu (Host game (Steam), join hint for invites and
"Join game", Join by lobby id for testing, a "Testing on one PC" section with address, port, Host
local and Join local, Quit, Steam sign-in status); a small Esc pause menu (Resume, Leave game, Quit;
the game keeps running for others); toasts (queued, also from `EventBus.toast_requested`); going to
the Break Room after hosting/joining and back to the menu after leaving or losing the host. 6 GUT
tests, all pass. Checked with 2 windows (local) and a real Steam lobby on Zachary's PC.

**Not done yet (later phases):** the HUD (health, inventory bar, interaction prompt, lift parts,
speakers for 1 to 8 players), settings screens, the death/ghost screen, the closet screen, the run
summary, vendor text, captions/subtitles (toast for now), text scale and high contrast, and a
theme (`lab_theme.tres`; Godot's default look for now).

**Stubbed:** game_flow's scene loading (`GameFlowStub`).

**Known limits:** Esc opens the pause menu only when you have a body; the player's own Esc stub (frees
the mouse) still runs first, which is harmless. Steam joining is only tested on one PC so far.

**For the next systems:**
- **game_flow:** take over scene changes from `GameFlowStub` (go to the Break Room after hosting or joining,
  back to the menu after `connection_lost`), then delete the stub.
- **settings_input:** add a Settings button to the main and pause menus with `UI.register_screen`.
