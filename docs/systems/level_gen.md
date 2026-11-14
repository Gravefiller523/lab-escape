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
class_name TileLightFlicker extends Node        # NEW 2026-10-30 (Zachary): damage lighting for one tile
func setup(tile: Node, level: StringName, tuning: FloorGenTuning = null) -> void
func step(delta: float) -> void                  # called every frame; tests call it directly
class_name BlockoutTile extends Node3D          # @tool: builds a CSG blockout tile (floor, ceiling, walls, holes, frames, lights)
func seal_socket(socket_name) -> bool          # NEW 2026-10-31: an unused door socket becomes plain wall (hole and frame go)
func is_socket_sealed(socket_name) -> bool
func refresh_emergency_slits(color) -> void    # NEW 2026-10-31: builds its red slits again (Level calls it after sealing)
func get_sockets() -> Array[RoomDoorway]        # NEW 2026-10-31
func socket_place(socket) -> Vector2i          # NEW 2026-10-31: (edge 0 N, 1 S, 2 W, 3 E or -1; grid unit along it)
@export var emergency_slits: StringName        # NEW 2026-10-31: "room", "hall" or "none" (dark filler)
@export var emergency_keep_out: Array[Rect2]   # NEW 2026-10-31: areas the slit rules leave alone (light them with markers)
class_name EmergencySlits extends RefCounted    # NEW 2026-10-31 (Zachary): red emergency slits low on a tile's walls
static func build(tile, tuning, color) -> Node3D        # builds the tile's "EmergencySlits" node
static func plan(tile, tuning) -> Array[Dictionary]     # where they go, without building (tests)
static func slit_point(tile, tuning, slit) -> Vector2
@export var size_units: Vector2i
@export var auto_lights: bool = true
@export var floor_hole: Rect2                   # e.g. under the cargo lift's own floor
static func slot_material(slot: StringName) -> Material

# NEW 2026-10-31 (floor generation step 3: the generator; regular floors in runs use it)
class_name FloorGenerator extends RefCounted    # pure, host only
static func generate(department: DepartmentData, floor_number: int, run_seed: int, player_count: int = 1, tuning: FloorGenTuning = null) -> FloorLayout
static func generate_from_seed(department: DepartmentData, floor_number: int, floor_seed: int, numbers: FloorGenTuning) -> FloorLayout
static func generate_for_run(department: DepartmentData, floor_number: int, run_seed: int, player_count: int) -> FloorLayout  # + report()
static func report(layout: FloorLayout) -> void  # prints "[floorgen] ..." lines, saves user://floorgen/last_floor.log
static func set_next_seed(floor_seed: int) -> void   # debug: the next floor uses this seed (F4, `floorgen <seed>`)
static func tile_pool(department: DepartmentData) -> Array[RoomData]
static func piece_kind(room: RoomData) -> StringName # straight / corner / t / cross / end, from its open sides
static var last_layout: FloorLayout
const LOG_PATH: String
class_name FloorLayout                          # NEW fields (sent with to_dict, old floors unchanged):
var grid: StringName                            # RoomData.GRID_LEGACY or GRID_TILE
var attempt: int; var is_fallback: bool
var wings: PackedStringArray                    # "West wing A"...; RoomPlacement.wing indexes it
var main_halls: Array[PackedInt32Array]         # placement indexes of each main hallway, from the welcome center
var loops: Array[Vector2i]                      # [placement a, placement b] joined by a loop hallway
var active_markers: Dictionary[StringName, PackedStringArray]   # kinds the plan picked markers for
var log_lines: PackedStringArray; var stats: Dictionary[String, int]   # host only (not sent)
func cell_size() -> float
static func marker_key(placement_index: int, path_in_room: String) -> String
class_name RoomPlacement
var wing: int = -1                              # NEW; RoomPlacement.make(id, at, steps, wing_index = -1)
class_name RoomShape
var markers: Array[Dictionary]                  # NEW: {"kind", "path"} read from the room scene
# Autoload Level
func get_floor_transform() -> Transform3D      # NEW: where the (moved, turned) floor is
func get_markers(kind)                          # CHANGED: only the markers the plan switched on, if it chose for that kind
func get_marker_by_key(key: String) -> RoomMarker   # NEW 2026-11-10 (step 4d): a marker by its FloorLayout.marker_key
func get_room_index_for_position(point: Vector3) -> int   # NEW 2026-11-10 (step 4e): the placement a point is in, or -1
# Level.build CHANGED: 3 m tile floors; an open hallway end nothing joins gets a "Cap..." wall (grid unit wide,
# ceiling high, wall material); an unused door socket on a tile is sealed (BlockoutTile.seal_socket: plain wall,
# no frame; CHANGED 2026-10-31), other rooms' doorways get a "Plug..." as before. Keys F3 (map) and F4 (new floor, host).
class_name FloorMapView extends Control         # draws a FloorLayout from above (layout, players, zoom)
var style: StringName                          # NEW 2026-11-10: "debug" (F3) or "security" (the security map table)
var accent_color: Color / var cameras: Array[Dictionary]   # NEW 2026-11-10
func cells_to_screen(cells: Vector2) -> Vector2 # NEW 2026-11-10: where a floor point (grid cells) is drawn
func room_screen_rect(index: int) -> Rect2      # NEW 2026-11-10: where a placement is drawn
class_name FloorgenOverlay extends CanvasLayer  # the F3 view: map, seed, seed box, log (owned by Level)
```
**Console (NEW 2026-10-31):** `floorgen <seed>` (this floor again with that seed), `floorgen floor <n>`,
`floorgen dept <department_id>`, `floorgen log`, `floorgen map`. Host and cheats only, like `floor`.
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
NEW 2026-10-31 (step 3): **regular floors in runs use `FloorGenerator`** (3 m tiles) while
`Config.floor_gen.use_floor_generator` is on (the default); boss floors keep the old generator above. Floor
seed = `hash("run_seed|floor_number")` (or the debug seed); each step has its own stream
`SeededRng.make(floor_seed, &"floorgen_<step>", attempt)` (`start`, `main_halls`, `branches`, `loops`,
`markers`, `fallback`). What it does (plan section 5):
1. Elevator at cell (0, 0) (open side -z), the welcome center joined to its whole open side (the
   department's own template if it has one, else the generic one).
2. A main hallway out of each welcome center connector: walled straight pieces (5-long with
   `main_hall_long_piece_share`, else 3-long, 1-long fillers for the rest), a corner now and then
   (`main_hall_turn_chance`, at most `main_hall_max_turns`, never back toward the welcome center), an end piece.
   Length rolled from V3, growing with the floor.
3. Branches at every side doorway (shuffled): room / cluster (2 to 4 rooms joined by their doorways) /
   secondary hallway / nothing (V4 weights). Secondary hallways (length `secondary_hall_length_min..max`,
   turns `secondary_turn_chance`, T splits `secondary_split_chance`) branch again up to
   `max_branch_depth_by_bracket`; their end doorway always gets a room. Each branch off a main hallway is a
   wing. Stops at the target room count (V5).
4. Loops (`loops_by_bracket`): free doorways of different wings facing each other across up to
   `loop_max_gap_units` empty cells are joined by 1-unit hallway fillers.
5. Simple: every room is a shared room tile, picked by weight when placed (department rooms come in step 4a).
   CHANGED 2026-10-31 (step 4a): **step 5 for real.** First each of the department's `required_room_kinds`
   (not "lift") goes at the free main hallway doorway farthest from the elevator where one of its tiles fits
   (an attempt fails if one fits nowhere). Then every other room: with `shared_room_weight` (or the tuning
   file's `shared_room_share`) a shared room, otherwise one of the department's `room_types` picked by weight
   (within `max_per_floor`, `min_floor` = run floor, `size_categories`), then a tile of that `room_kind`
   (shared room if none fits). The department's own welcome center tile is used if it has one.
Then a share of `prop_spawn` markers is switched on (`prop_spawn_share`). Checks: two main hallways of at
least `min_main_hall_units`, rooms at least `min_rooms_share` of the target; a failed attempt tries again,
after `max_attempts` the safe fallback floor (two short hallways with a room each) is built and logged loudly.
Hallway pieces are recognised by their open sides (`piece_kind`), so new pieces need no code.
NEW 2026-10-31 (step 4c): **doors and locks** (plan step 7). Every doorway into a room gets a door on the room's
socket (the deeper room if both are rooms); joins between hallways are open archways (Q6). Type from the worse
damage of the two sides (V8 `door_weights_*`): open (a double `WorldDoor`, E), broken open (one leaf hanging,
nothing to open), jammed (power with `power_door_share` / `power_door_share_by_department`, else pry), debris
(4-8 loose debris props in the doorway, moved by hand). Then `keycard_doors_*_by_bracket` open doors become
keycard doors, one colour each (`keycard_colours`, at most `keycard_colours_max`). Locks get their keys in
order, each somewhere reachable without it: one crowbar (`crowbar_item_id`) for all pry doors (F5), a power
cell (`power_cell_prop_id`) for power doors from `power_cell_from_floor` (F6), the matching keycard
(`prop_keycard_<colour>`) for each keycard door; spots: `keycard`, `item_spawn`, `prop_spawn` markers. A lock
whose key can't be placed reachably becomes a plain door (logged). The plan carries `doors` ([room, socket,
other side, type `FloorGenerator.DOOR_*`, extra]) and `door_items` ([kind, marker key, door]). `Level.build`
builds node `Door<n>` in the room (+X along the wall, +Z into the room) with the leaves and, on the approach
side (-Z), a `WorldPryPoint`, a `WorldBreaker` (with a cable and a dead panel) or a `WorldKeycardReader`, wired
to unlock and open both leaves. On `floor_ready` the host spawns the items and the doorway debris
(`Level.spawn_door_items()`). Locked doors are walls for enemies until opened (world_io). The F3 map draws
locked and blocked doors as coloured squares with lines to what opens them.

NEW 2026-10-31 (step 4b): **incident and damage** (plan step 6). The department's incident (`incidents`, by
weight; `incident_generic` if none) starts in a room it fits (`origin_room_kinds`) at least
`incident_min_distance_share` of the farthest walking distance from the elevator. Every tile's damage score =
intensity (V7, grows with the floor) x closeness to the origin by walking distance (fading over
`damage_falloff_metres`) + noise; thresholds give pristine / light / heavy / destroyed (capped at the tile's
`damage_levels`). The elevator and welcome center (with the security room) are at most `start_area_max_damage`.
Destroyed secondary hallway pieces collapse (`collapse_chance`) only where every other tile stays reachable;
main hallways never do. Then hazards (V12, heavy/destroyed rooms only, kinds from the marker, department and
incident) and prop spots (more used in damaged rooms, many get loose debris `prop_debris_chunk` /
`prop_debris_panel`). Streams `floorgen_damage`, `floorgen_hazards`. The plan carries `damage`, `incident_id`,
`origin`, `collapsed`, `marker_params` (copied into the markers' params by `Level.build`: `prop_id`,
`hazard_kind`). `Level.build` keeps only each tile's damage overlay, adds `TileLightFlicker` in the
department's `lighting` colours, and fills collapsed pieces with rubble. Debug: `floorgen origin
near|far|normal`, `floorgen damage light|heavy|destroyed|pristine|off` (both stay until changed). The F3 map
fills rooms by damage colour, stars the origin and crosses out collapsed pieces.

NEW 2026-10-31 (step 4a): `Level.build` dresses tile floors for their department: the department's `palette`
on every tile (and the caps), and a room-name sign at every `sign` marker (the marker's `text` param, else the
room type's `display_name`, else the tile's name; the department's `signage_style` scene if set, else a
label in its `accent_color`). The F3 map writes each room's name. `LevelService.room_display_name()`.

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
| Secondary hallway | 1 unit wide; pieces run along z |
| Hallway pieces (CHANGED 2026-10-30, Zachary) | walled. Straight pieces are 3 units long (one centred side doorway per side) or 5 long (two per side, on units 2 and 4); a 1-unit filler has solid sides; corners, T junctions and crossings are solid wherever nothing joins; an end has one doorway in its end wall |

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
| Emergency slit | `emergency_slit` (NEW 2026-10-31) | `corner` (bool: an L in an inside corner) | level_gen (EmergencySlits) |

Older kinds keep working: `lift`, `printer`, `cart`, `vendor`, `upgrade_machine`, `charger`, `item_spawn`,
`player_spawn`, `supply_counter`, `task`, `boss_spawn`, `minion_spawn`, `locked_door`. Placement (Q19):
printer and cart in the welcome center; vendors in break rooms and offices; upgrade machine in medium rooms.
Any marker may carry `min_damage` / `max_damage` params so it only exists in rooms that damaged.
NEW 2026-10-31 (Zachary's playtest), checked by tests:
- **Machines** (`vendor`, `printer`, `upgrade_machine`, `charger`) stand with their back to a wall and their
  **+Z axis pointing into the room** (the side those machines open to), at least 1 m clear of every doorway,
  never in a hallway.
- **Spawn spots** (`lift_part`, `prop_spawn`, `item_spawn`, `keycard`) sit high enough that the biggest thing
  they hold starts in free space with something to land on within 1 m (floor spots about 0.4-0.5 m up,
  desk and counter spots about 0.4 m above the top). The tiles' CSG walls and furniture are thin shells, so a
  part that starts inside a desk stays trapped there (that is how a fuse went missing).
- Every floor has a `charger` spot (the welcome center has one) and more `lift_part` spots than broken parts.
The elevator's `lift` marker faces so the cargo lift's gate (its -z side) looks out of the open side, toward
the welcome center.

**Damage overlays.** Every tile has a `Damage` node with children `Light`, `Heavy` and `Destroyed` (hidden).
Pristine is the tile itself. When the floor is built (step 4b) the room's level is shown and the rest
deleted. `BlockoutTile` fills an overlay you left empty with placeholder boxes. Tile lights are in the group
**`tile_light`**, the red emergency slits' lights (see "Emergency slits" below) in **`tile_emergency_light`**; the ceiling is in `tile_ceiling`. `TileStandards.show_damage()`
switches levels.
NEW 2026-10-31 (step 4b): overlays left empty get **real blockout debris** (no more coloured boxes): solid
rubble (material slot `rubble`, WORLD collision, solid only while the overlay is shown) always within 0.5 m
(hallways) or 1 m (rooms) of a wall, never in front of a doorway, in a cart lane, or on a machine or spawn spot
(`BlockoutTile.KEEP_CLEAR_MARKERS`); plus papers, ceiling tiles, cables and scorch marks with no collision.
`TileStandards.keep_damage(tile, level)` keeps one overlay and deletes the rest.
**Damage lighting** (NEW 2026-10-30, Zachary; `TileLightFlicker`, numbers in `Config.floor_gen`, "Damage
lighting"): pristine = steady; light = some lights blink now and then; heavy = some lights dead, the rest dim,
dark for a few seconds then flickering, red emergency slits steady; destroyed = most lights dead, the rest
dark with a rare faint flicker, a third of the red slits dead and the rest on and now and then flickering
(pristine and light: the slits are dark grooves). Looks only (not
networked); each light is seeded by its node path, so every PC shows the same pattern.
CHANGED 2026-10-31 (Zachary, "way more random"): each light has its own speed (`flicker_light_speed`), a
flicker is either one quick blink (`flicker_single_blink_chance`) or a burst of random switches
(`flicker_on_chance`, not strict on-off-on) at a random brightness per flash (`flicker_brightness`), and the
wait ranges are wider.

**Lift parts** (NEW 2026-11-10, step 4d; plan step 8; numbers in `Config.floor_gen`, "Lift parts (V10)"). The
generator picks the floor's broken lift parts and writes them into the plan (`FloorLayout.lift_parts`:
`[part prop id, marker key, room]`), with a carry path for each (`lift_part_paths`: rooms from the part back to
the elevator, through "door" connections only, never through a collapse), backup spots (`lift_part_backups`)
and the battery charger's spot (`charger_marker`). How many: `parts_min/max_by_bracket`. Which: one per lift
slot, drawn with weight `1 + part_size_bias_per_floor x (floor - 1) x size step`. Where: only in rooms (never
the elevator, welcome center, security room or a hallway), on a `lift_part` marker whose `max_size` fits, at
least `part_min_distance_share` of the farthest room's walking distance from the elevator, one room per part,
spread over the two main hallways' sides and then their wings, in a room whose `part_categories` has the part's
category, at a branch end when it can (`part_branch_end_weight`), at most
`parts_behind_keycards_max_by_bracket` parts behind keycard doors, one near the incident from
`part_near_incident_from_floor` (a heavy or destroyed room, or within `part_near_incident_metres`), and never
every part in a combat or hazard room. Room kind and then distance are relaxed when nothing fits (written in
the log); a part that fits nowhere is swapped for another kind; no part at all = the attempt fails. A part on a
marker that isn't `visible_from_entrance` gets a cue: a small warm light (`part_cue_color`, `part_cue_range`)
that goes out once the part is taken away. The cargo lift reads the plan (see cargo_lift.md); floors without a
plan (the old generator) keep the lift's own pick. F3 shows parts as numbered orange diamonds with their
carry paths.

**Emergency slits** (NEW 2026-10-31, Zachary; `EmergencySlits`, numbers in `Config.floor_gen`, "Emergency
slits"). The red emergency lights are small glowing slots low on the walls: 50 cm wide, 5 cm tall, 10 cm above
the floor, set into the wall, each with one small red light (no shadows, department `emergency_color`). An L
slit (25 cm along each wall, meeting in an inside corner) counts as one. No collision, nothing networked. Where
they go depends on the tile's `emergency_slits`:
- `"room"` (the default; rooms, the elevator, the welcome centers): L slits in the inside corners. Rooms up to
  9 m both ways light 2 opposite corners (the pair with more free corners), bigger rooms all 4. A corner is
  skipped when a wall is open there, a door frame is within 2 m along either wall, or furniture or a marker
  stands within 0.6 m of it. Walls over 12 m also get `round(length / 9) - 1` straight slits, which slide up to
  2 m out of the way of doors, furniture and other slits (4 m apart) or are left out. A room that ends up with
  none gets one straight slit. Areas in `emergency_keep_out` (a room inside the room) get none; light them with
  `emergency_slit` markers (a straight slit on a wall face, +Z out of the wall, or with params
  `{"corner": true}` an L whose arms run along +X and +Z). The welcome centers' security rooms have two.
- `"hall"` (every hallway piece): a straight piece lights units 0, 2, 4 with a slit on each side wall, facing
  each other (side doorways are on units 1 and 3, so they never clash); a corner gets an L in its outside
  corner; an end gets an L in both corners of its end wall (an arm that would run into the end doorway is
  left off); T and crossing pieces are dark.
- `"none"`: the dark fillers (`room_tile_main_filler_dark`, `room_tile_hall_filler_dark`, tag "dark"). The
  generator puts one between two straight hallway pieces, so the slits come every other unit all along a
  hallway (corners and ends may break the rhythm), and loops alternate lit and dark fillers.
Sealed doorways count as plain wall: `Level.build` builds each tile's slits again once its unused doorways are
sealed. The lights start off (a dark groove); `TileLightFlicker` turns them on in heavy rooms, and in
destroyed rooms leaves a third dead (seeded by the light's node path, so every PC matches) and flickers the rest.

**Material slots.** Geometry that should take the department's look has the metadata `material_slot` =
`wall`, `floor`, `trim` or `accent`. `TileStandards.apply_palette(tile, department.palette)` swaps them.
Blockout defaults: `systems/level_gen/tiles/materials/blockout_<slot>.tres`.

**The step 2 tiles** (`content/rooms/room_tile_*.tres`, scenes in `systems/level_gen/tiles/`):
templates `room_tile_elevator` (3x3), `room_tile_welcome_center` (8x6: reception desk facing the elevator,
security room on the far wall with a door, 2-unit connectors left and right, printer and cart markers);
main hallway `room_tile_main_straight` (2x3), `_main_straight_long` (2x5), `_main_filler` (2x1), `_main_corner`,
`_main_t` (2x2), `_main_end` (2x1); secondary hallway `room_tile_hall_straight` (1x3), `_hall_straight_long`
(1x5), `_hall_filler`, `_hall_corner`, `_hall_t`, `_hall_cross`, `_hall_end` (1x1); shared rooms `room_tile_janitor_closet` (2x2), `_bathroom` (2x3), `_storage_small` (3x3),
`_office` (3x4), `_break_room` (4x4), `_office_open` (4x5), `_storage_large` (5x6), `_cafeteria` (6x6).
NEW 2026-10-31 (step 4a), Robotics (`department_ids` = Robotics): `room_tile_robotics_welcome_center` (8x6),
`_robotics_assembly_floor` (6x8, required), `_robotics_test_bay` (6x6, required), `_robotics_server_room` (3x4,
required), `_robotics_machine_shop` (4x4), `_robotics_parts_storage` (4x5), `_robotics_charging_bay` (3x4, two
chargers), `_robotics_electronics_lab` (4x4). Palette materials in `assets/materials/robotics/`.

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
everyone runs `build`. NEW 2026-10-31: a tile floor's dictionary is a few kilobytes (rooms, wings,
main hallways, loops, active markers); the generation log stays on the host. F4 and `floorgen` go through
game_flow's normal floor change, so every PC follows. Static geometry is not networked. Dynamic things are spawned by their systems
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
NEW 2026-10-31: `systems/level_gen/test/floorgen_viewer.tscn` (F6): seed box, floor number, Generate, Next
seed, Bake navigation (shows the time), Tab between the map and the 3D floor (fly camera). Launch option
`benchmark` builds and bakes three floor-18 floors and prints the times. GUT
`tests/unit/level_gen/test_floor_generator.gd`: same seed same floor; elevator and welcome center first; no
overlaps; both main hallways; room share of the target; every socket joined or capped and every tile
reachable; dictionary round trip and size; loops and branch depth within limits; 500 seeds never crash and
never need the fallback; only the chosen prop spots are used; runs use the new generator and a seed comes back;
hallway pieces recognised.
NEW 2026-10-31: `tests/unit/level_gen/test_emergency_slits.gd`: slits never in a doorway or open edge, no ceiling
emergency light left, small rooms 2 corners and big rooms 4 (plus long-wall slits 4 m apart), corners next to a
door or furniture skipped (lit once the door is sealed), every hallway piece's slits, lit units alternate along
generated main hallways, destroyed slits dead the same way every time, the security room's own slits.
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
- DONE 2026-10-31 (step 4a): a department every floor (game_flow).
- 2026-10-31 (step 4a): Botany and Zoology are placeholder departments (shared rooms only, stand-in enemies;
  Botany's boss floors off) until their own rooms come (plan step 5). UPDATED 2026-11-13: all three now have their
  own rooms (step 5), and boss floors (4, 8 and 12 since 6a) roll among the departments that have a boss.
- 2026-10-31 (step 3): main hallway T pieces aren't used yet (main hallways don't split); secondary T
  pieces are. `DepartmentData.welcome_center_scene` isn't read: the generator picks a welcome center tile
  (RoomData, `room_kind` "welcome_center") that lists the department, else the generic one.
- 2026-10-31 (step 3): loops are straight runs of 1-unit fillers only (no L-shaped loops yet).
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
- 2026-10-30 (Zachary, after playing step 2): hallway pieces are walled and longer (3 and 5 units with 2 and 4
  side doorways, a 1-unit filler, walled corners, T junctions and ends), main and secondary alike. NEW
  `TileLightFlicker` and "Damage lighting" numbers in FloorGenTuning (heavy: darker with longer gaps;
  destroyed: nearly dark, red emergency light). FloorGenTuning `branch_interval_min/max` replaced by
  `main_hall_long_piece_share` (branches grow from side doorways). LightingStyleData keeps colours only.
- 2026-10-31 (Zachary): flickering much more random: per-light speed, single blinks or stuttering bursts,
  random on/off switches and random brightness per flash, wider timing ranges. NEW FloorGenTuning
  `flicker_light_speed`, `flicker_on_chance`, `flicker_brightness`, `flicker_single_blink_chance`.
- 2026-10-31 (floor generation step 4c, branch `system/level_gen-floorgen-step4c`): doors and locks (see above).
  NEW FloorLayout `doors`, `door_items`; `FloorGenerator.DOOR_*`; `Level.spawn_door_items()`; world_io devices
  `WorldPryPoint`, `WorldKeycardReader`, `WorldBreaker`; props `prop_keycard_red/blue/yellow`,
  `prop_power_cell`; FloorGenTuning `keycard_colours`, `crowbar_item_id`, `power_cell_prop_id`.
- 2026-10-31 (Zachary: higher floors bigger): rooms 10 + 1.65 per floor (cap 40), main hallways +1 unit per floor
  (cap 30), a fourth floor bracket from floor 12 (side-hallway depth 4, 4 loops). Measured averages: floor 1 10 rooms
  / 32 tiles, floor 6 18 / 50, floor 12 28 / 79, floor 18 38 / 97 (largest about 234 x 135 m); floor 18 plans in
  15-19 ms, builds in 110-130 ms, bakes navigation in 56-69 ms. A department room that doesn't fit now tries the
  department's other room types before a shared room.
- 2026-10-31 (Zachary): wider damage around the main incident (intensity 0.9 + 0.03 per floor, cap 1.3, over
  70 m, noise 0.12) and smaller incidents elsewhere (`minor_incidents_*_by_bracket` 1 / 1-2 / 2-3, peak 0.72 over
  25 m, spaced 40% of the farthest distance apart); a tile's damage is the worst of all incidents. NEW FloorLayout
  `minor_origins`, `minor_incident_ids` (sent). The F3 map shows them as smaller orange stars.
- 2026-10-31 (Zachary's playtest): the debug keys are now **F3** (map) and **F4** (new floor, host), input actions
  `InputActions.DEBUG_FLOOR_MAP` / `DEBUG_FLOOR_REGENERATE` (rebindable). F8 stopped the game: the Godot editor
  uses F5 to F8 while a game runs.
- 2026-10-31 (floor generation step 4b, branch `system/level_gen-floorgen-step4b`): incidents, damage levels,
  collapses, hazards (new system `hazards`), loose debris props, real blockout debris in overlays, damage on
  the F3 map, `floorgen origin` / `floorgen damage`. NEW FloorLayout `damage`, `incident_id`, `origin`,
  `collapsed`, `marker_params`, `damage_level()`; `TileStandards.keep_damage`, slot `rubble`,
  `RoomShape.markers` carry `params`. CHANGED `TileStandards.show_damage` (debris solid only when shown).
- 2026-10-31 (floor generation step 4a, branch `system/level_gen-floorgen-step4a`): generator step 5 (required
  rooms, department room types, shared share), Robotics tiles and department, Botany and Zoology placeholders,
  palettes and room-name signs in `Level.build`, room names on the F3 map. FloorLayout unchanged.
- 2026-10-31 (floor generation step 3, branch `system/level_gen-floorgen-step3`): NEW `FloorGenerator`,
  `FloorMapView`, `FloorgenOverlay` (F3 map, F4 new floor, `floorgen` commands), the floorgen viewer. NEW
  FloorLayout fields (grid, attempt, is_fallback, wings, main_halls, loops, active_markers; log_lines and
  stats host only), `RoomPlacement.wing`, `RoomShape.markers`, `Level.get_floor_transform()`. CHANGED
  `Level.build` (tile floors, caps), `Level.get_markers` (only markers the plan switched on). game_flow:
  regular floors use FloorGenerator. NEW tuning: use_floor_generator, min_rooms_share, min_main_hall_units,
  secondary hallway length, turn and split chances, prop_spawn_share. `charger` markers in the storage rooms
  and break room. Measured: floor 18 (68-87 tiles) plans in about 9 ms, builds in about 55 ms, and its
  navigation bakes in about 50 ms (about 1,200 polygons), so one whole-floor bake stays (plan section 12).
- 2026-10-19 (cargo_lift slots): NEW marker kind `charger` (where the lift's battery charger may go), one in
  `room_hall_grey` and one in `room_corridor_grey`.
- 2026-10-31 (step 4c fix, Zachary's playtest: doors floating at odd angles, the pry door only a black strip):
  the door leaves were built right but stayed behind when the game moved the floor to line it up with the lift
  (fixed in `WorldDoor`, see world_io). NEW `BlockoutTile.seal_socket` / `is_socket_sealed`: a tile's unused door
  socket is now plain wall instead of a frame around a grey plug. Tests `test_door_leaves_sit_shut_on_their_jambs`
  (a moved heavy-damage floor) and `test_every_door_type_on_every_side_and_turn`.
- 2026-10-31 (Zachary: emergency slits): the red emergency light is no longer one ceiling light in the heavy
  and destroyed overlays. NEW `EmergencySlits`: small red slits low on the walls, each with one small light
  (rooms: L slits in the inside corners, 2 opposite ones in rooms up to 9 m, all 4 in bigger ones, straight
  slits on walls over 12 m; hallways: a pair every other unit, an L in a corner's outside corner and both
  corners of an end wall, T and crossing pieces dark). Unlit = a dark groove; heavy = all on; destroyed = a
  third dead (seeded), the rest flicker. NEW `BlockoutTile.emergency_slits` ("room", "hall", "none"),
  `emergency_keep_out`, `refresh_emergency_slits`, `get_sockets`, `socket_place`; marker kind `emergency_slit`
  (the welcome centers' security rooms use two). NEW tiles `room_tile_main_filler_dark` and
  `room_tile_hall_filler_dark` (tag "dark", piece "straight1_dark"): the generator puts one between two straight
  hallway pieces, and loops alternate lit and dark fillers. Level.build builds each tile's slits after sealing
  its doorways (`_light_room`). NEW tuning group "Emergency slits". Tests `test_emergency_slits.gd`.
- 2026-11-10 (floor generation step 4d: lift parts, Q3, Q4, Q14, Q15, V9, V10): NEW generator step 8
  (`_place_parts`): part count by floor bracket, kinds drawn by size (bigger likelier higher up), placed on
  `lift_part` markers by the plan's rules (rooms only, far enough, spread over hallway sides and wings, room
  kind, branch ends, at most N behind keycards, one near the incident from floor 4, never all in combat or
  hazard rooms), relaxing room kind then distance (logged); a carry path back through door connections, backup
  spots and the charger spot. NEW FloorLayout `lift_parts`, `lift_part_paths`, `lift_part_backups`,
  `charger_marker`; NEW `Level.get_marker_by_key`; part cues (a small warm light) by parts on markers not
  `visible_from_entrance`; parts and carry paths on the F3 map; validation checks carry paths and Q15. NEW
  tuning `part_backup_spots`, `part_branch_end_weight`, `part_cue_color`, `part_cue_range`. Generator socket
  entries carry their `connection`; `_links(doors_only)`. Tests `test_lift_parts_plan.gd`.
- 2026-11-10 (floor generation step 4e: security room, plan step 9, Q11, Q12, V11, V13): NEW generator step 9
  (`_place_cameras`): `cameras_per_main_hall` cameras spread along each main hallway, `cameras_per_part_room` in
  or next to each lift part's room, `cameras_random` more; labels "CAM 04 EAST WING B"; broken by damage
  (`camera_broken_chance_heavy`/`_destroyed`). NEW FloorLayout `cameras` ([marker key, label, broken]); NEW
  `Level.get_room_index_for_position`; NEW `FloorMapView.style` ("debug"/"security"), `accent_color`, `cameras`,
  `cells_to_screen`, `room_screen_rect` (the security system's map table draws with it); cameras on the F3 map.
  The new `systems/security` builds the table and monitors (docs/systems/security.md).
- 2026-11-10 (floor generation step 4f: plan steps 10 to 12, Q15, Q19, Q20, Q21, Q24, V12, V14): NEW generator
  step 10 (`_pick_enemy_spawns`): `enemy_spot_share` of the enemy budget (RunDifficulty, so it grows with the floor
  and the players; `generate_from_seed` NEW `player_count`) in `enemy_spawn` spots switched on, never in the
  elevator or welcome center or within `enemy_spot_min_distance`, and never in one lift part's room (Q15). NEW
  `_validate` (section 13): locks open in some order, required rooms, no overlaps, joins face to face, the start,
  parts and keys reachable, part rules; failures are logged and retried. The fallback floor (Q24) now has the
  required rooms at its hallways' doorways, a room at each end, parts, cameras and enemy spots, and no damage,
  locks or collapses; NEW `FloorGenerator.debug_force_fallback` and console `floorgen fallback on|off`. Q19:
  `upgrade_machine` spots in the charging bay, server room and parts storage. Load order (Q20): enemies bake on
  `floor_built`, game_flow waits for it. Tests `test_floor_step_4f.gd`, `test_floor_rules_bulk.gd` (30 seeds per
  department) and the slow group `tests_slow/level_gen/test_floor_rules_bulk_500.gd` (500 per department, about
  a minute: `-gdir=res://tests_slow`).
- 2026-11-11 (floor generation step 5a: Botany, plan section 8, F4): the Botany department is real: its own welcome
  center (planters, a green stripe), 9 room tiles (greenhouse, seed vault, decontamination airlock, cell culture lab,
  microscopy lab, soil and sample prep, autoclave room, growth chamber, irrigation pump room), required rooms
  greenhouse, seed vault and airlock, room types with part categories, a clinical white and green palette
  (`assets/materials/botany/`), green emergency slits, a prop pool with DNA vials, 4 incidents (overgrowth breach,
  spore release, irrigation flood, seed vault cooling failure) and hazards (toxic spores, toxic gas, water). NEW
  `IncidentOverlays` (`systems/level_gen/tiles/incident_overlays.gd`): damaged tiles wear the nearest incident's
  `overlay_flavour` (vines, spores, flood, frost, scorch, wreckage; Robotics' scorch and wreckage now show too).
  NEW tuning `debris_prop_ids_by_department` and `debris_props_for()`: Botany's loose debris and debris doorways
  are mostly vines (NEW prop `prop_debris_vines`). The airlock is an ordinary small room with a door on each side
  for now (a true two-door choke point between a hallway and a lab needs generator support; later). Tests
  `test_botany.gd`.
- 2026-11-11 (floor generation step 5b: Zoology, plan section 8): the Zoology department is real: its own welcome
  center (hay bales, a moss stripe), 7 room tiles (animal holding, veterinary surgery, feed storage, observation
  room with one-way windows, aquarium, habitat simulation, quarantine pens), required rooms animal holding, vet
  surgery and feed storage, room types with part categories, a wood, sand and moss palette
  (`assets/materials/zoology/`), amber emergency slits, a prop pool (crates, meat, feed sacks, hay), 2 incidents
  (enclosure breakout: NEW overlay flavour "claws"; tank rupture: the "flood" overlay and water hazards), hazards
  (broken enclosures, water) and debris (NEW props `prop_debris_hay`, `prop_debris_feed_sack`,
  `prop_debris_cage_bars`). It keeps the giant rat boss floors and its rat, bat, fly and kangaroo. Generator: a room
  with a broken enclosure hazard also gets its enemy spawn spots switched on (never the calm part room). Not done:
  the plan's "broken skylights and dark corners" damage look. Tests `test_zoology.gd`.

- 2026-11-12 (roadmap WP10, content only): `department_botany` now spawns its own enemies (mushroom zombie, flytrap, spore shooter, vine creeper) and uses `loot_botany_small` and `stock_botany_vending`. Its boss floors stay off until the Mushroom Man (WP13).

- 2026-11-12 (roadmap WP11, content only): `department_robotics` now spawns its own enemies (roomba, turret, drone, flock camera) and uses `loot_robotics_small` and `stock_robotics_vending`. Its boss floors stay off until Robobrain (WP13).

- 2026-11-13 (floor generation step 6a: runs of 12 floors, a boss every 4): `config/floor_gen_tuning.tres` re-spreads
  every floor-number curve over 12 floors (the script's defaults are the old 18-floor ones): `floor_brackets`
  1, 3, 6, 8 (parts 1-2 on floors 1-2, 2-3 on 3-5, 3-5 from 6; keycard doors, parts behind keycards, smaller
  incidents, branch depth and loops follow the same brackets); per floor x1.5 for main hallway length, damage
  intensity, part size bias and hazards; rooms 10 on floor 1, about 27 by floor 11 (`target_rooms_per_floor`
  1.7). The "from floor 4" rules (a part near the incident, missing power cells) stay at floor 4, the first boss
  block boundary. Tests over floors 1-18 now cover 1-12; the bulk check covers 1-12.
- 2026-11-13 (step 6b, Botany's airlock): NEW tile role "connector" (`TileStandards.ROLE_CONNECTOR`): a short passage
  with exactly two doorways, no size category, no lift parts. Botany's decontamination airlock
  (`room_tile_botany_decon_airlock`, same id) is now one: 1 x 2 units with a doorway at each end. The generator puts
  it between a hallway and a lab: the required airlock goes at a main hallway doorway with a lab behind it, and labs
  listed in `airlock_room_kinds` that hang off a hallway sit behind one now and then (`airlock_chance`, within the
  airlock's max_per_floor). An airlock nothing fits behind is taken back out (`_unplace_last`). Connectors get doors
  like rooms, so an airlock has a door at each end. NEW tuning `airlock_room_kinds`, `airlock_chance`,
  `airlock_kind`. Test `test_airlocks_sit_between_a_hallway_and_a_lab`.
- 2026-11-13 (step 6b, Zoology's damage look): NEW `DamageLooks` (`systems/level_gen/tiles/damage_looks.gd`), picked per
  department in NEW tuning `damage_looks_by_department` (Zoology: "skylights"): heavy and destroyed tiles get 1-2
  holes cut in the ceiling (CSG) with a pale shaft and a dim downlight through each and a ceiling panel hanging
  down, plus 2-4 dark corners (a shadowy volume and a dead light fitting). Looks only, seeded. Test
  `test_damaged_zoology_rooms_get_skylights_and_dark_corners`.
- 2026-11-13 (step 6b, navigation warning): checked that the enemies' bake no longer reads the blockout tiles' visual
  meshes (it reads their collision faces since roadmap WP3, 2026-11-11), so Godot's "slow parse" warning is gone: the
  walkable area matches the old way within 0.4% and bake time is the same (about 20-50 ms a floor). NEW test
  `test_navigation_bake.gd` locks that in for every department; the two level_gen tests no longer excuse the warning.
- 2026-11-13 (step 6c, tuning from data): NEW debug tool `FloorStats` (`systems/level_gen/debug/floor_stats.gd`) and its
  runner scene `test/floor_stats_runner.tscn` (headless: N floors per department per floor number, a CSV and a markdown
  summary). NEW `FloorLayout.stats["longest_path_m"]` (the walk from the elevator to the farthest tile). Tuning:
  `floor_brackets` (1, 3, 6, 8) -> (1, 4, 6, 9) so floors 1-3 are all the gentlest bracket (floor 3 had a jump in parts,
  keycard doors and loops). Report with before and after tables: `docs/design/floor-stats-6c.md`.
  Also (Zachary's OK) the enemies' spawner budget follows the run's floor and `enemy_budget_per_floor` is 0.2 in
  `config/game_config.tres`, so enemies per room stay about 0.5 on every floor. `FloorStats` counts spawned enemies too.
- 2026-11-14 (roadmap WP22 art rollout; made by the roadmap thread with Zachary's OK, since the floor generator's plan is finished): NEW `BlockoutTile.art_mesh` (Mesh, optional) and `BlockoutTile.ART_NAME`. When set, the tile builds as before, then hides its CSG combiners (the generated shell and ceiling, and its own CSG pieces such as the pens), whose collision stays, and shows the mesh as child `Art` of `Generated`. The mesh must fit the tile: origin at its corner, the same walls, doorways and big pieces. First user: `tile_zoology_animal_holding` with `assets/models/zoology/room_zoology_animal_holding.mesh` (from `assets/source/look_target_models.py`). Lights, markers, damage overlays and emergency slits are unchanged. Test: `tests/unit/level_gen/test_tile_art.gd` (2).

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
- 2026-11-14 (roadmap WP22 art rollout, same OK): every department tile and all 25 shared tiles (hallways, elevator, offices, break room, cafeteria, bathroom, storage, janitor closet, generic welcome centre) now have an `art_mesh`. NEW: the `Art` node carries the material slot `"art"` (added to `TileStandards.MATERIAL_SLOTS`), so `DepartmentData.palette["art"]` (each department's palette material, NEW in the three department files) colours a shared tile's walls, ceiling and floor in that department's colours. Fix: `seal_socket` on a tile with a model now also adds a wall piece over the doorway gap (`ArtPatch_<socket>`, mesh `assets/models/shared/wall_patch.mesh`, `BlockoutTile.ART_PATCH_PREFIX`, `WALL_PATCH_PATH`) with the model's material; before, a sealed doorway showed a hole in the model (the hidden CSG still blocked it). Tests: `test_tile_art.gd` (+2).
- 2026-11-14 (art phase WP26, same OK): `_light_room` gives ceiling lights soft shadows that fade out with distance when the department's `lighting.shadows` is on (`SHADOW_FADE_BEGIN` 14 m, `SHADOW_FADE_LENGTH` 6 m), and adds a slowly pulsing `WarningLight` in every `warning_light_every`-th room when `warning_light_color` is set (Robotics).
