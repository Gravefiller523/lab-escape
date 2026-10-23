# game_flow

Folder: `res://systems/game_flow/` · Autoload: `GameFlow` · Size: M · Phase 1b

## Purpose
The game's big state machine. It knows whether we are in the main menu, the Break Room, riding the
elevator, on a floor or in a boss fight, and it moves everyone between them. It owns the **run**:
the seed, the floor number, the order of departments, and **difficulty scaling** (`RunDifficulty`).
It loads and unloads the main scenes.

**Not responsible for:** building floors (level_gen), the lift logic (cargo_lift), death rules
(death_respawn), UI screens (ui).

## Public API
```gdscript
enum State { BOOT, MAIN_MENU, BREAK_ROOM, ELEVATOR_RIDE, LOADING_FLOOR, ON_FLOOR, BOSS_FIGHT, RUN_SUMMARY }

func get_state() -> State
func get_run() -> RunState                     # null outside a run
func get_current_department() -> DepartmentData   # null outside a run
func is_in_run() -> bool
func start_run(run_seed: int = 0) -> void      # host; 0 = random (or Config.game.debug_run_seed). CHANGED 2026-10-18: parameter renamed (seed is a GDScript built-in)
func end_run(result: StringName) -> void       # host; &"escaped", &"wiped", &"abandoned"
func go_to_break_room() -> void                # host (and after hosting/joining)
func return_to_main_menu() -> void             # local; leaves the lobby
func debug_go_to_floor(floor_number: int, department_id: StringName = &"") -> String   # host, cheats only. CHANGED 2026-10-18: returns what it did (for the console)

# NEW 2026-10-18
func get_state_name() -> String                 # "ON_FLOOR" etc.
func describe() -> String                       # one line about the state and run (console, test scenes)
func department_order(run_seed: int) -> Array[StringName]   # the departments a run with this seed visits
func get_department(department_id: StringName) -> DepartmentData   # includes the placeholder department
func floors_in(department: DepartmentData) -> int   # regular floors before its boss floor
func total_floors(run: RunState) -> int
func place_on_floor(run: RunState, floor_number: int) -> bool   # moves a RunState to a floor of the whole run
func use_test_setup(net: NetService, config: GameConfig, scene_loader: Callable) -> void   # tests only
const RESULT_ESCAPED, RESULT_WIPED, RESULT_ABANDONED   # run_ended results
const MAIN_MENU_SCENE, BREAK_ROOM_SCENE, FLOOR_SCENE, LOADING_SCENE   # FLOOR_SCENE: CHANGED 2026-10-18, was STUB_FLOOR_SCENE
```
`RunState` (`class_name RunState extends RefCounted`):
```gdscript
var run_seed: int                          # CHANGED 2026-10-18: was `seed` (a GDScript built-in); to_dict() still uses "seed"
var department_ids: Array[StringName]      # order for this run
var floor_number: int                      # 1-based across the whole run
var department_index: int
var floor_in_department: int               # 1..floor_count, then the boss floor
var is_boss_floor: bool
func get_department_id() -> StringName       # NEW 2026-10-18
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> RunState
```
`RunDifficulty` (`class_name RunDifficulty extends RefCounted`), all reading `Config.game`:
```gdscript
static func enemy_budget(floor_number: int, player_count: int, config: GameConfig = null) -> int
static func enemy_health_multiplier(player_count: int, config: GameConfig = null) -> float
static func boss_health_multiplier(player_count: int, config: GameConfig = null) -> float
static func floor_task_count(player_count: int, config: GameConfig = null) -> int
```
CHANGED 2026-10-18: each takes an optional config (tests); null reads `Config.game`. The formulas:
budget = `base_enemy_budget` x (1 + `enemy_budget_per_floor` x (floor - 1)) x (1 + `enemy_budget_per_extra_player` x (players - 1)),
rounded; health = 1 + per_extra_player x (players - 1); tasks = `floor_tasks_base` + one per
`extra_floor_task_every_players` players beyond the first 2.

## EventBus
- Emits: `game_state_changed`, `run_started`, `run_ended`, `floor_loading`, `floor_ready`, `boss_floor_started`.
- Listens: `elevator_start_accepted` → start run; `lift_departed` → next floor; `boss_defeated` →
  next department or escape; `team_wiped` → end run; `player_reprinted`/`player_died` (nothing yet).

## Data it owns and saves
Owns `RunState`. Saves nothing (runs are not saved; quitting abandons the run).

## Adding content
None directly. Departments in a run are picked from `ContentRegistry.get_all(&"department")` where
`in_run_rotation` is true, sorted by `order_hint` (ties shuffled by the seed). A new department joins
runs automatically.

## Multiplayer
- Host decides every state change and sends `(new_state, run_state.to_dict())` to clients (reliable RPC).
  Clients then load the same scene and emit the same events.
- Floor loading: host asks level_gen to generate a layout, sends it, and waits until every client
  reports "built" before emitting `floor_ready` (with a timeout that kicks a stuck client).
- ~~`Net.set_joining_open(true)` only in BREAK_ROOM.~~ CHANGED 2026-10-18: joining stays open during runs
  (decision: mid-run joiners spectate and spawn at the next floor), so game_flow never closes it.
- NEW 2026-10-18, how a scene change works (`_transition`), in an order that never sends anyone
  updates for things they don't have: (1) every PC stops sending player updates
  (`PlayerCharacter.stop_syncing()`) and the host goes to a loading screen, which removes its bodies
  and props on every PC; (2) 0.15 s later the clients load the new scene and report; (3) when they all
  have it (or after `floor_load_timeout`), the host loads it, then floors start with `floor_ready`.
- NEW 2026-10-18: a player who joins gets the current state and run from the host and loads that scene
  before the connection opens (net_core's joining handshake, `Net.set_join_handlers`); on a floor they
  spectate until the next one. A scene change only waits for the clients that were there when it began.
- NEW 2026-10-18: GameFlow is only "in charge" once it has loaded the main menu or the Break Room (or
  the game started in one). In other scenes (systems' test scenes, GUT) it ignores EventBus events.

## Dependencies and stubs
- net_core (host checks, roster), level_gen (generate/build), break_room scene, ui main menu scene.
- Stub: a fake level_gen that builds one empty box room with a lift marker, so the state machine can be tested alone.
  DONE 2026-10-18, then REPLACED the same day by level_gen's floor scene: `stubs/stub_floor.tscn` (`StubFloor`): a grey box room with 3 crates and a button that
  stands in for cargo_lift ("Depart", emits `lift_departed` on every PC) or, on boss floors, bosses
  ("Defeat the boss", emits `boss_defeated`). It spawns players and crates on `floor_ready`.
- STUB (department content): with no DepartmentData in the rotation, runs use one placeholder
  department (`department_placeholder`, `floors_per_department` floors + a boss floor).
- Console commands (NEW 2026-10-18): `seed` (replaces the console's stub), `floor <n> [department_id]`,
  `end_run [result]` (cheats), `flow` (state and run).

## Test scene and GUT tests
Test scene `systems/game_flow/test/flow_test.tscn`: buttons for each transition, shows state and run data.
Test scene done 2026-10-18 (buttons stay on screen across scene changes; launch options `host`, `join`, `port=`).
GUT tests (`tests/unit/game_flow/`, all pass; NEW ones marked):
- `test_state_order_menu_breakroom_run_floor`
- `test_floor_six_is_next_department_after_boss` (5 floors + boss, with floors_per_department from config)
- `test_department_order_is_same_for_same_seed`
- `test_new_department_file_joins_rotation` (register a DepartmentData in the test; it appears)
- `test_team_wipe_ends_run_and_returns_to_break_room`
- `test_difficulty_scales_with_player_count` (1, 4 and 8 players)
- NEW: `test_client_follows_the_host_through_the_run`, `test_late_joiner_gets_the_current_floor`,
  `test_run_state_survives_the_network`, `test_deeper_floors_have_bigger_budgets`

## Acceptance criteria
- [x] Main menu → Break Room → elevator → floors 1-5 → boss → next department → … → back to Break Room works in solo and with 2 local players.
  *(GUT with two PCs, and 2 headless game instances driven from the main menu through a whole run, 2026-10-18; Zachary to play it.)*
- [x] Adding a DepartmentData file adds it to runs with no code changes. *(GUT)*
- [x] Same seed gives the same department order. *(GUT)*
- [x] Difficulty reads player count; tested with 1, 4 and 8. *(GUT)*

## Open design questions
- DEFAULT: department order follows `order_hint` (launch: Botany, Zoology, Robotics in some order the team picks). Random order could be a later option.
- DEFAULT: after the final boss the run ends as "escaped" (no endless mode yet).
- DEFAULT 2026-10-18: a department's regular floors are its `floor_count`; 0 means use Config
  `floors_per_department`.
- DEFAULT 2026-10-18: a PC that doesn't finish loading in `floor_load_timeout` seconds is not kicked; the
  floor starts without waiting for it.
- ~~OPEN 2026-10-18 (net_core): mid-floor joiners got everything before loading the floor.~~ FIXED 2026-10-18:
  net_core's joining handshake asks GameFlow for the state and run (`_join_info`), and the joiner loads that
  scene (`_prepare_for_join`) before the connection opens. Joining the Break Room uses it too.

## Changelog
- 2026-10-07: spec created.
- 2026-10-18: built (Phase 1b). Changes marked above: `run_seed` naming, the scene-change order, the
  stub floor, the placeholder department, console commands, the NEW helper functions. New GameConfig
  numbers: `elevator_ride_seconds`, `run_summary_seconds`, `floor_load_timeout`.
- 2026-10-18: joiners go through net_core's handshake instead of a sync RPC after joining (the old way
  lost the floor's players and props and printed errors).
- 2026-10-18 (level_gen branch): floors come from level_gen (`FLOOR_SCENE` = `Level.FLOOR_SCENE`; the host
  generates the layout and it travels with the run and in the join handshake). The grey-box stub floor is gone.
  `use_test_setup` takes an optional floor builder.
- 2026-10-18: the placeholder department needs 1 lift part per floor (`prop_lift_part_zoology`).
- 2026-10-18 fixes (Zachary: stuck loading floor 3): going floor to floor, a client could build the new floor into
  the old scene (same file) and end up in an empty one; it now waits for the new scene node. Several Depart
  presses at once only move one floor. After 4 s the host gets a toast naming who is still loading.
  Test: `test_two_lift_presses_go_up_one_floor`.
- 2026-10-19 (cargo_lift branch, Zachary's design): one scene, the game world (`WORLD_SCENE`, `GameWorld`), stays
  loaded from the Break Room to the end of a run, with the cargo lift in it. Levels (the Break Room, floors) load
  around the lift while it rides (`_ride_to`: props outside the lift are dropped, every PC builds the level,
  arrival after `lift_ride_seconds` and when all have built). `lift_departed` drives everything: Break Room →
  start_run, floor → next floor, boss floor (the lift works once the boss is beaten) → next department or
  escaped. end_run brings everyone into the lift and rides back to the Break Room. REMOVED: the loading screen,
  the scene-change transition between floors, `FLOOR_SCENE`/`LOADING_SCENE`; `use_test_setup` now takes a
  level builder. NEW: `get_last_run_result()`, `WORLD_SCENE`, `LEVEL_BREAK_ROOM`, `LEVEL_FLOOR`. Joiners load
  the world and the current level in the join handshake. STUBS in GameWorld: crates at prop_spawn markers
  (physics_props), "Defeat the boss" button (bosses), the HUD prompt.
- 2026-10-19 (ui branch): the HUD prompt and crosshair stub in GameWorld is gone (the ui HUD shows them).
- 2026-10-23 (bosses branch): the "Defeat the boss" button stub in GameWorld is gone (the bosses system spawns the boss).
- 2026-10-19 (cargo_lift slots): the host picks how many lift slots break each floor (`_lift_break_count`:
  `SeededRng(run_seed, &"lift_break_count", floor)` between the department's `lift_breaks_min` and `lift_breaks_max`)
  and passes it to `CargoLift.arrive`. REMOVED the private `PLACEHOLDER_LIFT_PART_ID` const.

## HANDOFF
**Built (2026-10-18):** autoload `GameFlow` (`GameFlowService`, `systems/game_flow/game_flow.gd`),
`RunState`, `RunDifficulty`, a loading screen, the stub floor and the test scene. Breaks a run into
Break Room → elevator ride (`elevator_ride_seconds`) → floors (each: loading, then `floor_ready`) →
boss floor → next department … → run summary (`run_summary_seconds`) → Break Room.

**Foundation / project.godot changes:** autoload line `GameFlow` (after DebugConsole). GameConfig:
`elevator_ride_seconds`, `run_summary_seconds`, `floor_load_timeout`. No new EventBus signals.

**Other systems touched (on this branch):**
- ui: `GameFlowStub` now passes the ui's calls on to GameFlow (menu ↔ Break Room, and back to the
  menu from any GameFlow scene when the host is lost).
- player: NEW `PlayerCharacter.stop_syncing()` (used before every scene change).
- break_room: the "game_flow isn't built yet" text is gone; the doors still reopen in its own test scene.

**Stubs:** floors (level_gen), the lift (cargo_lift), the boss (bosses) and department content, see
"Dependencies and stubs". The steam_session `_GAME_STATE_BREAK_ROOM` constant (2) matches
`GameFlowService.State.BREAK_ROOM`; steam_session can switch to the enum.

**For the next systems:**
- **level_gen:** replace `STUB_FLOOR_SCENE` with a floor scene that builds `LevelGenerator.generate(...)`;
  the host should generate the layout and put it in the transition (GameFlow sends `run_data` today).
  Spawn players and props on `floor_ready`, not in `_ready` (see the transition order).
- **cargo_lift:** emit `lift_departed` on every PC when the lift leaves; GameFlow loads the next floor.
- **bosses:** emit `boss_defeated` on every PC; GameFlow moves on or ends the run as "escaped".
- **death_respawn:** emit `team_wiped` on every PC; GameFlow ends the run as "wiped".
- **ui:** a run summary screen can listen to `run_ended` (the summary lasts `run_summary_seconds`).
