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
func get_hud() -> Hud                           # NEW 2026-10-19: the HUD
func get_nameplates() -> Nameplates             # NEW 2026-10-19: names above other players' heads

class_name Hud extends Control                  # NEW 2026-10-19 (systems/ui/hud/hud.gd), child of UI
func get_prompt_text() -> String                # the "E: ..." prompt on screen now
func get_lift_text() -> String                  # the lift panel's text ("" when hidden)
static func lift_text(needed: int, fixed: int, missing: Array[String], waiting_for_boss: bool, riding: bool, in_break_room: bool) -> String
func use_sources(controller: InteractionController, lift: CargoLift) -> void   # tests only
# Fixed child names for widgets other systems add later: HealthSlot (bottom left), InventorySlot (bottom middle).

class_name Nameplates extends Node3D            # NEW 2026-10-19 (systems/ui/hud/nameplates.gd), child of UI
func get_plate(player_id: int) -> Node3D        # null for you, or before their body exists
func is_name_visible(player_id: int) -> bool
func get_alpha(player_id: int) -> float          # how faded in the name is (0 to 1)
func is_speaker_visible(player_id: int) -> bool
func use_net(net: NetService, config: GameConfig) -> void   # tests only
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

NEW 2026-10-19, the HUD (Zachary): a crosshair dot; the interaction prompt ("E: Pick up crate") under it and a
bar that fills while you hold E; a lift panel in the top-right corner ("LIFT PARTS 1/3" and the parts still
missing, "LIFT FIXED: Everyone in, then press Go.", or "Beat the boss to fix the lift."; hidden while riding and in
the Break Room). The HUD only shows in game_flow's game world while you have a body (other systems' test scenes
draw their own prompt). **Nameplates:** every other player's name floats above their head, facing you, and fades in
when you come within `Config.game.nameplate_range` (5 m) and fades out when you move away (over
`nameplate_fade_seconds`, 0.4 s; the speaker icon fades with it); walls hide it. While they talk
(`EventBus.player_speaking_changed`) a speaker icon shows next to their name (left side). Your own name never shows.
Names come from `Net.get_display_name` (Steam name; "Player <id>" when testing locally without names).

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
  *Prompt, lift parts and speakers (nameplates) done 2026-10-19 (GUT + 2 game copies); health and slots wait for damage and inventory.*
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
- 2026-10-18: fix (found by Zachary): a joiner's main menu stayed on screen ("Connecting...") because the
  handshake loads the host's scene first. The menu now closes whenever game_flow leaves the menu state, and
  on "lobby joined". Test: `test_main_menu_closes_once_you_are_in_the_game`.

- 2026-10-19 (Zachary): HUD basics: crosshair, prompt, hold bar, lift panel, empty HealthSlot / InventorySlot, and
  nameplates (name above the head within 5 m, speaker icon next to it while talking). NEW: `get_hud()`,
  `get_nameplates()`, `Hud`, `Nameplates`, GameConfig `nameplate_range` (5). Removed game_flow's HUD stub in
  GameWorld. Tests (`tests/unit/ui/test_hud.gd`): `test_lift_text_lists_missing_parts`,
  `test_lift_panel_follows_the_lift`, `test_prompt_shows_what_you_look_at`, `test_names_show_only_within_range`,
  `test_speaker_icon_shows_next_to_the_name_while_talking`, `test_plate_goes_when_the_player_leaves`.
- 2026-10-19 (Zachary): names and the speaker icon fade out past 5 m and back in as you approach. NEW: GameConfig
  `nameplate_fade_seconds` (0.4), `Nameplates.get_alpha()`. Test: `test_names_fade_out_and_back_in`.
- 2026-10-24 (settings_input): Settings buttons in the main and pause menus (`Settings.open(...)`, screen `&"settings"`); the mic sensitivity panel moved from the pause menu to Settings > Audio; `caption()` only shows with Settings > Accessibility > Subtitles on (still as a toast); the main menu's `host`/`join` launch options run once per game start (`static var _launch_options_used`), not every time the menu is rebuilt. Text scale is done by settings_input (the window's content_scale_factor).

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

**HUD basics (2026-10-19):** `systems/ui/hud/hud.gd` (`Hud`), `nameplates.gd` (`Nameplates`), `speaker_icon.svg`
(placeholder art). Both are children of the UI autoload. Foundation changes: GameConfig `nameplate_range` (5), `nameplate_fade_seconds` (0.4).
No project.godot changes, no new EventBus signals. Other system touched: game_flow (GameWorld's prompt/crosshair
stub removed). For the next systems: **damage** puts its health bar in the HUD's `HealthSlot`, **inventory** its
bar in `InventorySlot`; **death_respawn** should hide a ghost's nameplate (Nameplates needs a "is this body
visible" check from player: OPEN). Not done: the player list, settings screens, text scale.
