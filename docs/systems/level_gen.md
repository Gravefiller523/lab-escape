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

# NEW 2026-10-30 (floor generation step 2: tile standards and blockout tiles; nothing in gameplay uses them yet)
class_name RoomDoorway
const CONNECTION_DOOR / CONNECTION_VENT / CONNECTION_CRAWL / CONNECTION_JUMP: StringName
@export var connection: StringName = &"door"   # door, vent, crawl, jump. Only "door" counts for carrying parts
@export var open_edge: bool = false            # no wall along this grid unit's edge (hallway ends)
class_name RoomShape
static func cell_size_for(room: RoomData) -> float   # 3 m for grid "tile_3m", 12 m for the old rooms
# RoomShape.of() now caches by room id AND cell size; doorway entries also carry "connection" and "open_edge".
class_name LevelGenerator
static func room_pool(...)                      # CHANGED: only rooms with grid "legacy_12m" (the 3 m tiles never enter it)
class_name TileStandards extends RefCounted     # the names every tile uses (roles, damage levels, groups, slots, marker kinds)
static func overlay_of(tile: Node, level: StringName) -> Node3D
static func show_damage(tile: Node, level: StringName) -> void
static func apply_palette(root: Node, palette: Dictionary) -> void   # "wall"/"floor"/"trim"/"accent" -> Material
class_name BlockoutTile extends Node3D          # @tool: builds a CSG blockout tile (floor, ceiling, walls, holes, frames, lights)
@export var size_units: Vector2i
@export var auto_lights: bool = true
@export var floor_hole: Rect2                   # e.g. under the cargo lift's own floor
static func slot_material(slot: StringName) -> Material
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

## Tile standards (NEW 2026-10-30, floor generation step 2)
The new floor generator (docs/design/floor-generation-plan.md) builds floors from **tiles**: hand-made
room, hallway and template scenes on a **3 m grid**, so any tile joins any other. The old 12 m grey-box
rooms keep working until the new generator replaces them (Q18): a `RoomData.grid` setting tells them apart
(`legacy_12m`, the default, or `tile_3m`). All sizes below are numbers in `config/floor_gen_tuning.tres`
(`Config.floor_gen`), section "Tile standards".

| Standard | Value |
|---|---|
| Grid unit | **3 m**. Every footprint is a whole number of units; `size_cells` counts units. |
| Doorway (socket) | **2.4 m wide x 2.8 m tall** |
| Ceiling | **3.6 m** at every tile edge (large rooms may be taller inside later, Q26) |
| Walls | **0.3 m** thick, **centred on the footprint edge** |
| Floors | flat, at height 0 (ramps only inside a tile, never at a socket) |
| Elevator | 3 x 3 units (the lift cage plus its shaft gap is 6.6 m wide) |
| Welcome center | 8 x 6 units |
| Main hallway | 2 units wide; pieces run along z (2 units across x) |
| Secondary hallway | 1 unit wide; pieces are 1 x 1 unit |

**Room sizes** (`RoomData.size_category`, checked against the footprint by a test; either way round counts):

| Category | Footprints (units) |
|---|---|
| small | 2x2, 2x3, 3x3 |
| medium | 3x4, 4x4, 4x5 |
| large | 5x6, 6x6, 6x8 |

**Scene layout.** Root at the footprint corner with the smallest x and z, footprint along +x and +z. For a
blockout, put `BlockoutTile` on the root and set `size_units`; it builds the floor, ceiling, walls, doorway
holes and frames, and lights with CSG (collision on the WORLD layer, so players, voice muffling and the
enemies' navigation bake see them). Hand-placed pieces (furniture, inner walls) are CSG nodes in the scene.

**Sockets** are `RoomDoorway` nodes, **direct children of the root**:
- on the footprint edge, at floor height, **centred on one grid unit's edge**; width 2.4, height 2.8;
- `connection`: `door` (default), `vent`, `crawl` or `jump`; only `door` counts for carrying parts;
- `open_edge = true` means the tile has no wall along that unit (hallway ends, the elevator's opening and the
  welcome center's connectors). Two open edges joined look like one space; an open edge against a wall with a
  doorway is closed by that wall; an unused open edge will get a cap one grid unit wide (step 3);
- **every room tile has at least one socket on each of its 4 sides** (so any room fits any slot of its size,
  turned any way). Hallway pieces and templates don't have to.

**Tags** (`RoomData`, NEW): `grid`, `tile_role` (`room`, `main_hall`, `secondary_hall`, `template`),
`size_category` (rooms only; empty for the rest), `damage_levels`, `part_categories`, `is_combat_room`.

**Markers** (`RoomMarker`, kinds listed in `TileStandards.MARKER_KINDS`; add new kinds there too):

| Name | Kind | Params | Read by |
|---|---|---|---|
| Part spawn | `lift_part` | `max_size` (small/medium/large/huge), `visible_from_entrance` (bool) | cargo_lift |
| Security camera | `camera` (new) | `label` (optional) | security (step 4e) |
| NPC spawn | `enemy_spawn` | none yet | enemies |
| Patrol point | `patrol` (new) | `route` (points with the same route form one patrol) | enemies (later) |
| Prop spot | `prop_spawn` | `prop_id` (fixed by the designer, or picked from the department's `prop_pool`), `size` | physics_props |
| Cover spot | `cover` (new) | none | enemies (later) |
| Hazard spot | `hazard` (new) | `hazard_kinds` (which fit here), `min_damage` / `max_damage` | hazards (step 4b) |
| Keycard spot | `keycard` | none | keycards (step 4c) |
| Sign spot | `sign` (new) | `text` (optional; otherwise the room type's name) | level_gen (room-name sign) |
| Security room | `security_map`, `security_monitor` (new) | none | security (step 4e) |

Older kinds keep working: `lift`, `printer`, `cart`, `vendor`, `upgrade_machine`, `charger`, `item_spawn`,
`player_spawn`, `supply_counter`, `task`, `boss_spawn`, `minion_spawn`, `locked_door`. Placement (Q19):
printer and cart in the welcome center; vendors in break rooms and offices; upgrade machine in medium rooms.
Any marker may carry `min_damage` / `max_damage` params so it only exists in rooms that damaged.
The elevator's `lift` marker faces so the cargo lift's gate (its -z side) looks out of the open side, toward
the welcome center.

**Damage overlays.** Every tile has a `Damage` node with children `Light`, `Heavy` and `Destroyed` (hidden).
Pristine is the tile itself. When the floor is built (step 4b) the room's level is shown and the rest
deleted. `BlockoutTile` fills an overlay you left empty with placeholder boxes (yellow, orange, red; heavy
adds a red emergency light). Tile lights are in the group **`tile_light`** (damage makes them flicker, dim or
go out); the ceiling is in `tile_ceiling`. `TileStandards.show_damage()` switches levels.

**Material slots.** Geometry that should take the department's look has the metadata `material_slot` =
`wall`, `floor`, `trim` or `accent`. `TileStandards.apply_palette(tile, department.palette)` swaps them.
Blockout defaults: `systems/level_gen/tiles/materials/blockout_<slot>.tres`.

**The step 2 tiles** (`content/rooms/room_tile_*.tres`, scenes in `systems/level_gen/tiles/`):
templates `room_tile_elevator` (3x3), `room_tile_welcome_center` (8x6: reception desk facing the elevator,
security room on the far wall with a door, 2-unit connectors left and right, printer and cart markers);
main hallway `room_tile_main_straight` (2x1, a side doorway every unit), `_main_corner`, `_main_t` (2x2),
`_main_end` (2x1); secondary hallway `room_tile_hall_straight`, `_hall_corner`, `_hall_t`, `_hall_cross`,
`_hall_end` (1x1); shared rooms `room_tile_janitor_closet` (2x2), `_bathroom` (2x3), `_storage_small` (3x3),
`_office` (3x4), `_break_room` (4x4), `_office_open` (4x5), `_storage_large` (5x6), `_cafeteria` (6x6).

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
NEW 2026-10-30: `systems/level_gen/test/tile_gallery.tscn` (F6): a hand-joined sample (elevator, welcome
center, both main hallways, a side hallway, an office) plus every 3 m tile on its own; sockets as arrows
(green door, cyan open edge), markers as labelled balls, a cart, and you as a player. Keys: 1-4 damage
level, C ceilings, M arrows/markers, O overview camera, T next tile, Y back to the elevator, P test palette.
GUT `tests/unit/level_gen/test_tile_standards.gd`: footprints match data, sockets on the grid at the standard
size, a socket on every side of every room, size categories, damage overlays, known marker kinds, every tile
in all 4 turns, the lift faces the welcome center, the old generator never uses tiles, tiles are solid
WORLD geometry with a 2.8 m doorway and 3.6 m ceiling, overlays switch, palettes fill slots, tuning helpers.
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
- 2026-10-30 (step 2): walls are centred on the footprint edge, so where two tiles meet both build the same
  wall in the same place. Fine with one grey material; when art tiles come, decide whether art tiles build
  half walls or the generator skips one side.
- 2026-10-30 TODO (F3, game_flow, later step): `run_floor_count` 18 and `boss_every_floors` 6 go into
  GameConfig and replace `departments_per_run` / `floors_per_department` when game_flow rolls a department
  every floor. Not changed in step 2.

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
- 2026-10-30 (floor generation step 2, branch `system/level_gen-floorgen-step2`): NEW tile standards (3 m
  grid, 2.4 x 2.8 m sockets, 3.6 m ceilings, overlays, material slots, marker kinds), `TileStandards`,
  `BlockoutTile`, 19 blockout tiles, the tile gallery. NEW `RoomDoorway.connection` / `open_edge`,
  `RoomShape.cell_size_for`. CHANGED `RoomShape.of` caches per cell size; `LevelGenerator.room_pool` only
  uses `legacy_12m` rooms, so today's floors generate exactly as before. Data: NEW RoomData `grid`,
  `tile_role`, `size_category`, `damage_levels`, `part_categories`, `is_combat_room`; DepartmentData
  `welcome_center_scene`, `room_types`, `shared_room_weight`, `palette`, `signage_style`, `lighting`,
  `prop_pool`, `hazard_kinds`, `incidents`; NEW `RoomTypeData`, `IncidentData`, `LightingStyleData`; PropData
  `part_size`, `part_category` (filled in for the 9 lift parts); NEW `FloorGenTuning` as `Config.floor_gen`.
  Why: the plan's step 2, so the new generator (step 3) has standard tiles to join.
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
