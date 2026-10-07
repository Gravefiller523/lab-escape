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
func start_run(seed: int = 0) -> void          # host; 0 = random (or Config.game.debug_run_seed)
func end_run(result: StringName) -> void       # host; &"escaped", &"wiped", &"abandoned"
func go_to_break_room() -> void                # host (and after hosting/joining)
func return_to_main_menu() -> void             # local; leaves the lobby
func debug_go_to_floor(floor_number: int, department_id: StringName = &"") -> void   # host, cheats only
```
`RunState` (`class_name RunState extends RefCounted`):
```gdscript
var seed: int
var department_ids: Array[StringName]      # order for this run
var floor_number: int                      # 1-based across the whole run
var department_index: int
var floor_in_department: int               # 1..floor_count, then the boss floor
var is_boss_floor: bool
func to_dict() -> Dictionary
static func from_dict(data: Dictionary) -> RunState
```
`RunDifficulty` (`class_name RunDifficulty extends RefCounted`), all reading `Config.game`:
```gdscript
static func enemy_budget(floor_number: int, player_count: int) -> int
static func enemy_health_multiplier(player_count: int) -> float
static func boss_health_multiplier(player_count: int) -> float
static func floor_task_count(player_count: int) -> int
```

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
- `Net.set_joining_open(true)` only in BREAK_ROOM.

## Dependencies and stubs
- net_core (host checks, roster), level_gen (generate/build), break_room scene, ui main menu scene.
- Stub: a fake level_gen that builds one empty box room with a lift marker, so the state machine can be tested alone.

## Test scene and GUT tests
Test scene `systems/game_flow/test/flow_test.tscn`: buttons for each transition, shows state and run data.
GUT tests:
- `test_state_order_menu_breakroom_run_floor`
- `test_floor_six_is_next_department_after_boss` (5 floors + boss, with floors_per_department from config)
- `test_department_order_is_same_for_same_seed`
- `test_new_department_file_joins_rotation` (register a DepartmentData in the test; it appears)
- `test_team_wipe_ends_run_and_returns_to_break_room`
- `test_difficulty_scales_with_player_count` (1, 4 and 8 players)

## Acceptance criteria
- [ ] Main menu → Break Room → elevator → floors 1-5 → boss → next department → … → back to Break Room works in solo and with 2 local players.
- [ ] Adding a DepartmentData file adds it to runs with no code changes.
- [ ] Same seed gives the same department order.
- [ ] Difficulty reads player count; tested with 1, 4 and 8.

## Open design questions
- DEFAULT: department order follows `order_hint` (launch: Botany, Zoology, Robotics in some order the team picks). Random order could be a later option.
- DEFAULT: after the final boss the run ends as "escaped" (no endless mode yet).

## Changelog
- 2026-10-07: spec created.
