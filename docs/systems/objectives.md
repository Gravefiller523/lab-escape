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

class_name TaskStation extends Node3D         # building block: a place a player stands/operates (crane controls, wheel)
signal occupant_changed(player_id: int)
func get_occupant() -> int
```
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
