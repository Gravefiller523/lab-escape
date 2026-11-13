# objectives

Folder: `res://systems/objectives/` · Size: M · Phase 2 (keycards and hamster wheel are a stretch goal for the Phase 1 slice)

## Purpose
Floor goals besides finding parts: **keycards and locked doors**, and **co-op floor tasks** such as the
2-player crane game (rewards a gear/lift part) and the hamster wheel (charges a fuse). Tasks are data
plus a scene built from shared task pieces, so new tasks are mostly new scenes and files.

**Not responsible for:** the lift (cargo_lift), environment puzzles done with items (items' use targets), enemy behaviour.

## Public API
```gdscript
class_name LockedDoor extends Node3D
signal unlocked()
@export var key_prop_id: StringName          # e.g. &"prop_keycard_red"; empty = opened by a task signal
func is_unlocked() -> bool
func unlock() -> void                        # host

class_name KeycardReader extends Node3D       # a slot next to the door; drop the keycard in
@export var door: LockedDoor

class_name FloorTask extends Node3D           # root of every task scene
signal progress_changed(progress: float)      # 0..1
signal completed()
var task_data: FloorTaskData
func get_participants() -> Array[int]
func get_progress() -> float
func complete() -> void                       # host
func setup(data: FloorTaskData) -> void        # NEW 2026-11-13: before adding it to the tree
func is_done() -> bool                         # NEW
func add_work(player_ids: Array[int], seconds: float) -> void   # NEW, host: they worked this long together
 var reward_offset: Vector3             # NEW: where the reward appears, in the task's space

class_name TaskStation extends Node3D         # building block: a place a player stands/operates (crane controls, wheel)
signal occupant_changed(player_id: int)
func get_occupant() -> int
 var size: Vector3                      # NEW 2026-11-13: its box (centred in x and z, from the floor up)
func get_occupants() -> Array[PlayerCharacter] # NEW: the living players in it (every PC, from synced positions)
func contains(point: Vector3) -> bool          # NEW

class_name HamsterWheelTask extends FloorTask # NEW 2026-11-13 (tasks/hamster_wheel.gd)
func get_belt_speed() -> float
func get_runners() -> Array[PlayerCharacter]

# NEW 2026-11-13: autoload Objectives (objectives.gd, ObjectivesService)
func get_tasks() -> Array[FloorTask]
func place_task(task_id: StringName, xform: Transform3D) -> FloorTask        # host: for everyone (console, tests)
func plan_floor(floor_number: int, department: DepartmentData, player_count: int, run_seed: int) -> Array   # host
func has_space(world_node: Node3D, xform: Transform3D) -> bool
```
NEW 2026-11-13 (roadmap WP15), how it works: on each floor that isn't a boss floor, the host picks
`RunDifficulty.floor_task_count(players)` tasks (weighted, `min_players` filtered, from the department's `task_ids`;
STUB: a department with none uses every task) with `SeededRng.make(run_seed, &"tasks", floor)`, finds each a spot,
and sends [task_id, transform, floor] to every PC (`_place_rpc`); a late joiner asks once connected. Every PC puts the
task scenes under the Objectives node as `Task_<n>`, so the tasks' own RPCs line up. A task syncs its progress a few
times a second while it changes, and its whole state to a late joiner. Spots: `task` markers; STUB (level_gen): until
tiles have them, `prop_spawn` markers outside the lift room, on the floor found below the marker, turned whichever of
four ways has a clear 2.8 x 2.6 x 4.6 m box (`TASK_SPACE_*`). Tasks are cleared when the next floor loads or the run
ends. Reward kinds made so far: `loot` (rolls `FloorTaskData.reward_loot_id` at the task). The others print a warning.
**The hamster wheel** (`task_hamster_wheel`): a running belt inside a big ring. The belt carries you out of the back
at `params.belt_speed` (3.2 m/s, below walking speed), so you have to keep running into the panel at its front to stay
on. Each runner on it is a second of work per second (`work_seconds` 24, up to `max_participants` 4 at once); full,
it pays out `loot_task_hamster_wheel` (gems, maybe a large gem or a sandwich). The belt pushes only the body each PC
owns; the host counts runners from synced positions, so it works the same for every player.
Task reward kinds (`FloorTaskData.reward`): `lift_part` (spawns a lift part at the task's reward point),
`fuse` (spawns a fuse prop for a fuse box), `keycard`, `door_open` (unlocks linked doors).
Placement (host, on `floor_ready`): `RunDifficulty.floor_task_count(player_count)` tasks chosen from the
department's `task_ids`, filtered by `min_players` ≤ player count, placed at `task` markers.
RNG: `SeededRng.make(run_seed, &"tasks", floor_number)`.

## EventBus
- Emits: `floor_task_completed`, `door_unlocked` (all).
- Listens: `floor_ready` (spawn tasks, doors, keycards at markers).

## Data it owns and saves
Uses `FloorTaskData`. Keycards are props tagged `keycard`. Saves nothing.

## Adding content
New tasks: a `FloorTaskData` `.tres` + scene made from `FloorTask` and `TaskStation` pieces; add its id
to a department's `task_ids`. New keycard colours: a new prop. No code unless a task needs a new kind
of station.

## Multiplayer
Host decides progress and completion; progress, occupants and door states are synced. Hamster wheel:
the runner's speed (from their synced movement) charges progress on the host.

## Dependencies and stubs
interaction, physics_props, level_gen markers (stub by hand), player. Debug: registers the `task` spawner.

## Test scene and GUT tests
Test scene: a locked door with a red keycard, a hamster wheel, a fuse box; 2 local players.
GUT tests: `test_keycard_in_reader_unlocks`, `test_wrong_keycard_ignored`, `test_wheel_charges_with_speed`,
`test_task_completion_spawns_reward`, `test_task_count_scales_with_players` (1, 4, 8), `test_min_players_filter`.

## Acceptance criteria
- [ ] Keycard door and hamster-wheel task work on 2 PCs in the Zoology slice.
- [ ] More players get more tasks (from config).
- [ ] A new task scene + data file appears in runs without code.

## Open design questions
- DEFAULT: with many players, add more task copies rather than bigger tasks (`extra_floor_task_every_players`).
- Crane game needs exactly 2 players; in solo it is filtered out (min_players = 2).

## Changelog
- 2026-10-07: spec created.
- 2026-11-13 (roadmap WP15): built the floor task framework and the hamster wheel (see Public API). NEW autoload `Objectives` (project.godot, after Security). FloorTaskData NEW `work_seconds`, `reward_loot_id`, `params`, and reward kind `loot`. Keycards and locked doors stay with level_gen and world_io, which already make them, so `LockedDoor` and `KeycardReader` are not built here. Tests: `tests/unit/objectives/test_hamster_wheel.gd` (8) and the full-run test (every PC, the late joiner too, has the same tasks in the same places and hears when one is finished).
