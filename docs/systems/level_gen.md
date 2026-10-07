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
func to_dict() -> Dictionary             # small: sent to clients
static func from_dict(data: Dictionary) -> FloorLayout

class_name LevelGenerator extends RefCounted     # pure: no scene tree, easy to test
static func generate(department: DepartmentData, floor_in_department: int, floor_number: int, run_seed: int, player_count: int) -> FloorLayout
static func generate_boss_floor(department: DepartmentData, floor_number: int, run_seed: int) -> FloorLayout

# Autoload Level
signal floor_built()
func build(layout: FloorLayout) -> void          # every PC; clears the old floor
func clear() -> void
func get_layout() -> FloorLayout
func get_markers(kind: StringName) -> Array[RoomMarker]   # sorted by room order then name (same on every PC)
func get_room_for_position(position: Vector3) -> RoomData

class_name RoomMarker extends Marker3D           # placed inside room scenes
@export var kind: StringName                     # see list below
@export var params: Dictionary = {}              # e.g. {"prop_id": "prop_crate"} for a fixed prop
class_name RoomDoorway extends Marker3D          # on a room's edge; width checked against cart rules
@export var width: float = 2.0
```
Marker kinds (strings, so new ones need no code here): `player_spawn`, `enemy_spawn`, `prop_spawn`,
`item_spawn`, `vendor`, `supply_counter`, `printer`, `cart`, `lift`, `lift_part`, `keycard`,
`locked_door`, `task`, `boss_spawn`, `minion_spawn`.

**Generation (host):** RNG `SeededRng.make(run_seed, &"level_layout", floor_number)`. Room pool =
department's `room_ids` + rooms with empty `department_ids`, filtered by `min_floor`, `enabled`.
Place a `start` room, grow outward through matching doorways on a grid of `room_cell_size`, add
`required_room_kinds` (start, lift), roll `optional_room_chances` (supply, cafeteria, hr, armory), fill
up to `rooms_per_floor_min..max`, seal unused doorways with wall plugs. Pools are sorted by id so the
same seed always gives the same layout.

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

## Test scene and GUT tests
Test scene `systems/level_gen/test/gen_viewer.tscn`: generate with a seed field and "next seed" button, top-down camera, markers drawn as coloured gizmos.
GUT tests: `test_same_seed_same_layout`, `test_required_rooms_always_present`, `test_room_count_in_range`,
`test_no_overlapping_rooms`, `test_all_doorways_connected_or_sealed`, `test_layout_round_trips_dict`,
`test_markers_sorted_same_order`, `test_every_room_follows_cart_rules` (loads every room scene),
`test_new_room_file_used_without_code`.

## Acceptance criteria
- [ ] Zoology floors 1 to 5 generate from Zoology rooms; the boss floor uses the arena.
- [ ] Host and 2 clients see identical floors.
- [ ] A cart can be pushed from the start room to the lift on every generated floor (playtest 10 seeds).
- [ ] New rooms and departments need no code changes.

## Open design questions
- DEFAULT: floors are flat (one storey) for Phase 1; multi-storey rooms later (size_cells.y exists for it).
- How big should a floor be? Defaults 6 to 10 rooms; tune in playtests.

## Changelog
- 2026-10-07: spec created.
