# level_gen

Folder: `res://systems/level_gen/` · Autoload: `Level` · Size: L · Phase 1b

## Purpose
Builds each floor from a library of **pre-built rooms** (RoomData + scene) using the department's
bundle. The host generates a **layout** (which rooms, where, which way round) with the seed and sends
it to everyone; every PC then builds the same floor. Rooms carry **markers** that say where enemies,
vendors, printers, carts, props, lift parts and tasks can go. Every room follows **cart rules**.

**Not responsible for:** spawning anything at the markers (each owning system does it on `floor_ready`),
the run and floor order (game_flow), the lift (cargo_lift).

## Public API
```gdscript
class_name RoomPlacement extends RefCounted
var room_id: StringName
var cell: Vector3i
var rotation_steps: int                  # 0..3, times 90 degrees

class_name FloorLayout extends RefCounted
var department_id: StringName
var floor_number: int
var floor_seed: int
var placements: Array[RoomPlacement]
var is_boss_floor: bool                   # NEW 2026-10-18
func to_dict() -> Dictionary             # small: sent to clients
static func from_dict(data: Dictionary) -> FloorLayout

class_name LevelGenerator extends RefCounted     # pure: no scene tree, easy to test
static func generate(department: DepartmentData, floor_in_department: int, floor_number: int, run_seed: int, player_count: int, config: GameConfig = null) -> FloorLayout
static func generate_boss_floor(department: DepartmentData, floor_number: int, run_seed: int, config: GameConfig = null) -> FloorLayout
# NEW 2026-10-18
static func room_pool(department: DepartmentData, floor_in_department: int) -> Array[RoomData]
static func doorway_links(layout: FloorLayout, cell_size: float) -> Array[Dictionary]   # every doorway, and whether the room next door joins it

# Autoload Level
signal floor_built()
func build(layout: FloorLayout, parent: Node = null) -> void   # every PC; clears the old floor. CHANGED 2026-10-18: parent (default: the current scene)
func clear() -> void
func get_layout() -> FloorLayout
func get_markers(kind: StringName) -> Array[RoomMarker]   # sorted by room order then name (same on every PC)
func get_room_for_position(position: Vector3) -> RoomData
func get_room_nodes() -> Array[Node3D]           # NEW 2026-10-18: the built rooms, in placement order
func use_config(config: GameConfig) -> void     # NEW 2026-10-18: tests only
const FLOOR_SCENE: String                       # NEW 2026-10-18: the scene game_flow loads for every floor

class_name RoomMarker extends Marker3D           # placed inside room scenes
@export var kind: StringName                     # see list below
@export var params: Dictionary = {}              # e.g. {"prop_id": "prop_crate"} for a fixed prop
class_name RoomDoorway extends Marker3D          # on a room's edge; width checked against cart rules
@export var width: float = 3.0              # CHANGED 2026-10-18: 3 m default
@export var height: float = 3.0             # NEW 2026-10-18: the opening (and wall plug) height

# NEW 2026-10-18
class_name GreyboxRoom extends Node3D           # @tool: builds floor and walls, with gaps at its RoomDoorways
class_name LevelFloor extends Node3D            # the floor scene: light, spawners, stub lift/boss buttons
class_name RoomShape extends RefCounted         # internal: a room's footprint and doorways in cells
```
NEW 2026-10-18, grid rules: a room scene's origin is the corner of its footprint with the smallest x and z,
at floor height; the footprint covers `size_cells` cells along +x and +z. Doorways sit on the edge, in the
middle of a cell's edge. `RoomPlacement.cell` is the turned footprint's smallest corner.
Marker kinds (strings, so new ones need no code here): `player_spawn`, `enemy_spawn`, `prop_spawn`,
`item_spawn`, `vendor`, `supply_counter`, `printer`, `cart`, `lift`, `lift_part`, `keycard`,
`locked_door`, `task`, `boss_spawn`, `minion_spawn`.

**Generation (host):** RNG `SeededRng.make(run_seed, &"level_layout", floor_number)`. Room pool =
department's `room_ids` + rooms with empty `department_ids`, filtered by `min_floor`, `enabled`.
Place a `start` room, grow outward through matching doorways on a grid of `room_cell_size`, add
`required_room_kinds` (start, lift), roll `optional_room_chances` (supply, cafeteria, hr, armory), fill
up to `rooms_per_floor_min..max`, seal unused doorways with wall plugs. Pools are sorted by id so the
same seed always gives the same layout.
CHANGED 2026-10-18 (Zachary: every floor starts in the elevator): the lift room at cell (0, 0) (players arrive in it); fillers (`normal`, `corridor`) joined to random
free doorways; then the rolled special rooms; then any other required kinds at the free doorway
farthest from the lift (`required_room_kinds` default is now `["lift"]`; "start" counts as "lift"). Unused doorways get wall plugs when the floor is built (not in the layout). A boss
floor is the lift room with a `boss_arena` joined to it. `player_count` isn't used yet.

**Cart rules every room must follow** (checked by a GUT test over every room scene):
- every `RoomDoorway.width` ≥ `Config.game.cart_width` + 0.4 m;
- no steps taller than 0.25 m on walking routes: use ramps (no stairs between doorways);
- a clear path at least as wide as the doorway between every pair of doorways (designer checklist, not auto-checked);
- the lift room fits a cart plus `max_players` players.

## EventBus
- Emits: none (`floor_ready` is game_flow's, after `floor_built` on every PC).
- Listens: none (game_flow calls `generate` and `build`).

## Data it owns and saves
Uses `RoomData`, `DepartmentData`. Saves nothing.

## Adding content
New rooms: a scene (geometry + nav region + doorways + markers) and a `RoomData` `.tres`; add its id to
a department's `room_ids` (or leave `department_ids` empty for shared rooms). New special room kinds
are just a new `room_kind` name in data and an entry in `optional_room_chances`. **No code**, unless
the generator must treat a kind specially. A new department reuses everything.

## Multiplayer
Only the host runs `generate`. It sends `layout.to_dict()` (a few hundred bytes) to every client;
everyone runs `build`. Static geometry is not networked. Dynamic things are spawned by their systems
on the host. Reconnecting players receive the current layout on join.

## Dependencies and stubs
net_core (host check). Stub rooms: three grey-box rooms (start, corridor, lift) with doorways and markers.
Debug: `seed`, `floor <n>`, and a `show_markers` toggle.
DONE 2026-10-18: five shared grey-box rooms in `content/rooms/` (scenes in `systems/level_gen/rooms/`):
`room_lift_grey` (the elevator: 8 player spawns, the `lift` marker, one doorway), `room_hall_grey`,
`room_corridor_grey` (1x2), `room_arena_grey` (2x2). Halls and corridors have a `lift_part` marker.
(`room_start_grey` was dropped the same day: floors start in the lift room.) `seed` and `floor` are game_flow's console commands; `show_markers` isn't done
(the viewer scene shows them).
- STUBS in `LevelFloor`: crates at `prop_spawn` markers (physics_props should do it); for cargo_lift: the
  department's `lift_parts_per_floor` lift parts (`lift_part_prop_id`) at the `lift_part` markers farthest from
  the lift, and a "Depart" button at the `lift` marker that only leaves once the parts and every player are in
  the lift room (`LevelFloor.lift_blocker()` says what's missing, as a toast to whoever pressed it); no lift
  on boss floors; and a "Defeat the boss" button at `boss_spawn` markers (bosses).

## Test scene and GUT tests
Test scene `systems/level_gen/test/gen_viewer.tscn`: generate with a seed field and "next seed" button, top-down camera, markers drawn as coloured gizmos.
GUT tests: `test_same_seed_same_layout`, `test_required_rooms_always_present`, `test_room_count_in_range`,
`test_no_overlapping_rooms`, `test_all_doorways_connected_or_sealed`, `test_layout_round_trips_dict`,
`test_markers_sorted_same_order`, `test_every_room_follows_cart_rules` (loads every room scene),
`test_new_room_file_used_without_code`.

## Acceptance criteria
- [ ] Zoology floors 1 to 5 generate from Zoology rooms; the boss floor uses the arena.
  *Needs Zoology rooms. With the grey-box rooms: floors and the arena work (GUT, 30 seeds).*
- [ ] Host and 2 clients see identical floors. *Host and 1 client match (2 game instances, 2026-10-18).*
- [ ] A cart can be pushed from the start room to the lift on every generated floor (playtest 10 seeds).
  *Needs carts. Every room is reachable through connected doorways (GUT).*
- [x] New rooms and departments need no code changes. *(GUT: a registered RoomData is used)*

## Open design questions
- DEFAULT: floors are flat (one storey) for Phase 1; multi-storey rooms later (size_cells.y exists for it).
- How big should a floor be? Defaults 6 to 10 rooms; tune in playtests.
- DEFAULT 2026-10-18: rooms have no navigation region yet (enemies will add them).

## Changelog
- 2026-10-07: spec created.
- 2026-10-18: built (Phase 1b). Changes marked above.
- 2026-10-18 (Zachary): every floor starts in the elevator (lift room first), the lift part spawns far away
  and must be carried back. DepartmentData: NEW `lift_part_prop_id`, `required_room_kinds` default `["lift"]`.
  Test: `tests/integration/test_floor_lift_stub.gd`.
- 2026-10-19 (cargo_lift branch): REMOVED `Level.FLOOR_SCENE` and `LevelFloor` (floors are built into game_flow's
  game world, moved and turned so the lift room lines up with the cargo lift). `get_room_for_position` works on a
  moved floor. `room_lift_grey` just holds the lift (its `lift` marker; players arrive inside the lift).
- 2026-10-23 (death_respawn branch): `printer` markers in `room_lift_grey` and `room_arena_grey`.
- 2026-10-23 (upgrade_machine branch): `upgrade_machine` markers in `room_hall_grey` and `room_corridor_grey`.
- 2026-10-23 (vendors branch): `room_hall_grey` got a `vendor` marker (Vendors picks up to vendors_per_floor of them).
- 2026-10-19 (cargo_lift slots): NEW marker kind `charger` (where the lift's battery charger may go), one in
  `room_hall_grey` and one in `room_corridor_grey`.

## HANDOFF
**Built (2026-10-18):** autoload `Level` (`LevelService`), `LevelGenerator`, `FloorLayout`, `RoomPlacement`,
`RoomMarker`, `RoomDoorway`, `RoomShape`, `GreyboxRoom`, the floor scene `level_floor.tscn` (`LevelFloor`),
five grey-box rooms and the viewer scene `test/gen_viewer.tscn` (seed box, "Next seed", "Boss floor",
markers as coloured balls). 10 GUT tests.

**How it fits together:** game_flow's host calls `LevelGenerator.generate` (or `generate_boss_floor`) when a
floor starts and sends `layout.to_dict()` with the run. Every PC loads `Level.FLOOR_SCENE`, then game_flow
calls `Level.build()`. On `floor_ready` the host spawns players at `player_spawn` markers (and, as a stub,
props at `prop_spawn` markers). Joiners get the layout in net_core's join handshake.

**Foundation / project.godot changes:** autoload line `Level` (before GameFlow). Content: 5 RoomData files.

**Other system touched (on this branch):** game_flow: floors come from level_gen; its grey-box stub floor is gone.

**For the next systems:**
- **cargo_lift:** put the lift in the `room_lift_grey` scene (or spawn it at the `lift` marker), spawn the
  parts (see LevelFloor's stub: farthest `lift_part` markers first) and remove LevelFloor's stub. Every floor
  starts in the lift room. Emit `lift_departed` on every PC.
- **physics_props:** spawn props at `prop_spawn` markers on `floor_ready` (the `prop_id` param) and
  remove LevelFloor's stub.
- **enemies:** `enemy_spawn` markers; add navigation regions to rooms.
- **bosses:** the arena's `boss_spawn` and `minion_spawn` markers; remove the "Defeat the boss" stub.
- **Content:** Zoology rooms go in `content/rooms/` with `department_ids = [department_zoology]`.
