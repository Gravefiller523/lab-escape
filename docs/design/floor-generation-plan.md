# Floor generation: design and implementation plan

Status: **All questions answered (Zachary, 2026-10-30), including the follow-ups in section 16b.
Waiting for the go to start step 2.** Nothing else in the project changes until then.
Written 2026-10-30 after reading the project on branch `feel/step-7`.

**Zachary's answers (2026-10-30):** a new department is rolled **every floor** (Q1); **Botany stays**, Biology
is dropped (Q2); jammed doors need **a crowbar to pry, or a puzzle that powers the door** (Q7); every other
question: go with the recommendation. The sections below are updated to match.

How to read this: section 1 is the short version. Section 2 says what already exists and what this
plan reuses. Sections 3 to 14 are the design. Section 15 is the build order with a "how to test it"
for each step. **Section 16 is the list of questions for you**, and section 17 is a table of every number
I had to make up. Anything marked **(Q12)** or **(V7)** points at a question or value you should check.

---

## 1. The short version

- We replace the current room-chain generator with a new one that builds a floor in the 12 steps you
  listed: elevator and welcome center, two main hallways, branches, loops, room types, damage, doors,
  parts, cameras, spawn markers, navigation, validation.
- It stays a **pure, host-only planner** (it only does bookkeeping on a grid, no 3D nodes), exactly like
  today's `LevelGenerator`. The host sends the finished plan to every PC, and every PC builds the same
  3D floor from it. This is how the project already works, so multiplayer stays host-authoritative.
- Floors are made of **tiles**: hand-made room and hallway scenes on a **3 m grid**, with doorways of a
  standard size, so any tile joins any other. Damage is a set of **overlay layers inside each tile**.
- **Departments are data.** Each department is one `DepartmentData` file listing its rooms, required
  rooms, props, look, hazards, incidents and enemies. Adding a department means adding files, not code.
- All tuning numbers go into one new file, `config/floor_gen_tuning.tres`, editable in the Inspector.
- A debug overlay shows the room graph, damage, parts, locks and cameras, with the seed on screen and a
  key to regenerate.
- Build order follows yours: tile standards and CSG blockout tiles, then layout plus debug view, then
  Robotics end to end, then Botany and Zoology, then tuning.

**Decided (2026-10-30):**
1. **(Q1)** Every floor rolls its own department (game_flow changes; boss floors and run length in 16b).
2. **(Q2)** The three departments are **Botany, Zoology, Robotics**. Your Biology list is re-themed for plants
   in section 8 (check it: F4).
3. **(Q3)** Keep the lift's 9 part types, give each a size and category, and add motor, control board and
   brake assembly as new part files.
4. **(Q5)** 3 m grid, 2.4 x 2.8 m doorways, 3.6 m ceilings; we check the feel in step 2.
5. **(Q7)** Jammed doors open with **a crowbar** or **a power puzzle** (section 7b).
6. **(Q18)** The old generator and its grey-box rooms retire once the new one works, and its tests are updated.

---

## 2. What exists today, and what this plan does with it

I read `docs/systems/level_gen.md`, `cargo_lift.md`, `world_io.md`, `game_flow.md`, `enemies.md`,
`objectives.md`, `carts.md`, the code in `systems/level_gen/`, `systems/cargo_lift/`, `systems/world_io/`,
`core/data/levels/`, `core/config/`, and the shared design decisions.

| What exists | Where | What this plan does |
|---|---|---|
| `LevelGenerator`: places a lift room at cell (0,0), then joins rooms to free doorways on a **12 m grid** | `systems/level_gen/level_generator.gd` | **Replaced** by a new `FloorGenerator` (same job, new rules). The old code stays until the new one works (Q18). |
| `FloorLayout` / `RoomPlacement`: the plan the host sends to everyone as a small dictionary | `systems/level_gen/` | **Extended**: it gets hallways, room types, damage, doors, parts, cameras and chosen markers. Still sent with `to_dict()`. |
| `Level` autoload: builds rooms from a layout, plugs unused doorways with wall pieces, finds markers | `systems/level_gen/level.gd` | **Reused.** `build()` learns to apply damage layers, doors and palettes. `get_markers()` returns only the markers the generator switched on. |
| `RoomDoorway`, `RoomMarker` (marker kinds are plain names) | `systems/level_gen/` | **Reused** as the door sockets and markers inside tiles. New marker kinds need no code. |
| `GreyboxRoom` and 4 grey-box rooms (12 m cells) | `systems/level_gen/rooms/` | **Retired** after step 3 (Q18). New tiles are CSG blockouts on the 3 m grid. |
| `RoomData`, `DepartmentData` content classes | `core/data/levels/` | **New fields added** (never renamed or removed, per CLAUDE.md). See section 4. |
| The cargo lift lives in `GameWorld` for the whole run; each floor is moved so its `lift` marker lines up with it | `systems/game_flow/game_world.gd` | **Reused as is.** This is why the shaft always lines up: the floor moves to the lift, not the other way round. |
| `CargoLift` picks 1 to 3 broken slots per floor and spawns each part at the `lift_part` marker farthest away (straight-line distance) | `systems/cargo_lift/cargo_lift.gd` | **Changed** (Q4): the generator picks the broken parts and where they go; the lift reads the plan. |
| `WorldDoor`, `WorldButton`, `WorldCrank`, wires between devices; enemies already open doors and path around locked ones | `systems/world_io/` | **Reused** for every door, the monitor buttons, and prying jammed doors. |
| Enemies bake **one navmesh for the whole floor on a background thread** and re-bake when a door changes | `systems/enemies/enemies.gd` | **Reused.** This is my navigation recommendation (section 12). |
| `SeededRng.make(run_seed, stream, index)` | `core/util/seeded_rng.gd` | **Reused** for every random roll, one stream per step. |
| `Config.feel` holds tuning in its own `.tres` file, editable live with the `tune` console command | `core/config/feel_tuning.gd` | **Copied as a pattern** for `Config.floor_gen`. |
| Objectives (keycards, locked doors) | `docs/systems/objectives.md` | **Spec only, not built.** Keycard doors need a home (Q10). |
| No `content/departments/` files yet; runs use a placeholder department | `systems/game_flow/` | Robotics, Botany, Zoology become the first real department files. |
| Runs go through departments in blocks (5 floors, then a boss floor; `RunState.department_index`, `floor_in_department`) | `systems/game_flow/` | **Changed** (Q1): each floor rolls its department with the run seed (`SeededRng(run_seed, &"floor_department", floor)`). Approved with your Q1 answer. |
| An `item_crowbar` exists (melee item) | `content/items/` | **Reused** to pry jammed doors (Q7). |

---

## 3. Tile standards

### Words used here
- **Tile**: one hand-made scene (a room, a hallway piece, or a fixed template) that the generator places.
- **Grid unit**: the size of one grid square. Every tile's footprint is a whole number of grid units.
- **Footprint**: the rectangle of grid squares a tile covers, seen from above.
- **Socket**: a `RoomDoorway` marker (a `Marker3D`) at a doorway on the tile's edge. Two tiles join
  where their sockets meet face to face.
- **Cap**: a wall piece that fills a socket nothing joined (the project already does this: "wall plugs").
- **CSG**: Constructive Solid Geometry. Godot nodes like `CSGBox3D` that let you build shapes from boxes
  and cut holes in them, right in the editor. Quick to make and change, perfect for blockouts.
- **Blockout**: a plain grey version of a level used to test layout before art exists.

### 3.1 Sizes (all proposed, please check: Q5)

| Standard | Proposed value | Why |
|---|---|---|
| Grid unit | **3 m** | A secondary hallway is 1 unit (3 m) wide, a main hallway 2 units (6 m). HL2's corridors are about 3 m wide. |
| Doorway | **2.4 m wide x 2.8 m tall** | Fits a double door (two 1.2 m leaves). The cart rule needs at least 1.6 m (`cart_width` 1.2 + 0.4). A group carrying the counterweight fits. |
| Ceiling height | **3.6 m** standard at every tile edge | The lift cage is 3.4 m tall. Large rooms may be taller inside, as long as their edges are 3.6 m (Q26). |
| Wall thickness | 0.3 m, centred on the footprint edge | Same as today's grey-box walls. |
| Floor height | 0 for every tile | Flat floors, one storey (today's default). Ramps only inside a tile, never at a socket. |
| Elevator footprint | 3 x 3 units (9 x 9 m) | The cage is 5 x 5 m inside plus walls and the 0.6 m shaft gap: 6.2 m, so 2 units (6 m) is too small. |

Today's `room_cell_size` is 12 m. It stays for the old rooms until they are retired. The new grid
unit is a separate number in the new tuning file, so nothing old breaks.

### 3.2 Room sizes (V2)

| Category | Footprints (grid units) | In metres |
|---|---|---|
| Small | 2x2, 2x3, 3x3 | 6x6 to 9x9 m (closets, bathrooms, cold storage) |
| Medium | 3x4, 4x4, 4x5 | 9x12 to 12x15 m (labs, offices) |
| Large | 5x6, 6x6, 6x8 | 15x18 to 18x24 m (assembly floor, test bay, greenhouse) |

Footprints are rectangles only for now (Q27).

### 3.3 Sockets
- A socket sits on the footprint edge, at floor height, **centred on one grid unit's edge**, facing out.
- Every socket is the standard doorway size. A socket that isn't standard (a vent, a crawlspace, a
  jump-only gap) must say so with a `connection` setting (`door`, `vent`, `crawl`, `jump`). Only `door`
  counts for carrying parts (section 10).
- **Every room tile has at least one socket on each of its 4 sides** (proposed rule, Q27). This lets
  the generator pick a room's footprint first and its type later (step 5), because any tile of the right
  size will fit whichever way it's turned.
- Sockets the generator doesn't use get a cap automatically.
- **Zachary 2026-10-30 (after playing step 2):** hallway pieces are **walled**, not open every unit. Straight
  pieces are 3 units long with one centred side doorway per side, or 5 long with two per side (units 2 and 4);
  a 1-unit filler has solid sides; corners, T junctions and crossings are solid wherever nothing joins; an
  end has one doorway in its end wall. Same for main (2 wide) and secondary (1 wide) hallways. Hallway ends
  are open edges (`RoomDoorway.open_edge`) so pieces join into one long hallway.

### 3.4 Markers inside tiles
All markers are `RoomMarker` nodes with a `kind` name and optional `params`. I reuse the kinds other
systems already read, so they keep working:

| Your name | Marker kind | Params | Read by |
|---|---|---|---|
| Door socket | (a `RoomDoorway`, not a marker) | `connection` | level_gen |
| Part spawn | `lift_part` (existing) | `max_size` (small/medium/large/huge), `visible_from_entrance` (bool) | cargo_lift |
| Security camera spot | `camera` (new) | `label` (optional) | security (new) |
| NPC spawn | `enemy_spawn` (existing) | none yet | enemies |
| Patrol point | `patrol` (new) | `route` (name, to group points) | enemies (later) |
| Prop spot | `prop_spawn` (existing) | `prop_id` (set by the generator, or fixed by the designer), `size` | physics_props |
| Cover spot | `cover` (new) | none | enemies (later) |
| Hazard spot | `hazard` (new) | `hazard_kinds` (which hazards fit here) | hazards (new, Q16) |
| Keycard spot | `keycard` (existing name in the spec) | none | keycards (Q10) |
| Sign spot | `sign` (new) | none | level_gen (room name sign) |

The other systems' markers (`printer`, `cart`, `vendor`, `upgrade_machine`, `charger`) keep working.
Where they go on the new tiles is Q19.

### 3.5 Tags on each tile (new `RoomData` fields, section 4)
- `department_ids`: departments it belongs to. Empty = shared (offices, storage, bathrooms...).
- `room_kind`: its room type, e.g. `robot_test_bay`, `office`. Already exists.
- `tile_role`: `room`, `main_hall`, `secondary_hall`, `template`.
- `size_category`: small, medium, large (checked against the footprint by a test).
- `damage_levels`: which damage levels it has overlays for (at least pristine and light).
- `part_categories`: which kinds of lift part make sense here (section 10.2).

### 3.6 Damage overlays inside a tile
Each tile has a `Damage` node with children named `Light`, `Heavy`, `Destroyed`. Each holds that level's
extra pieces: debris, broken fixtures, scorch decals, water planes, hanging cables, emergency lights.
`Level.build()` keeps the one for the room's level (and lower levels if the designer ticks "stack")
and deletes the rest. Tile lights go in a group `tile_light` so damage can make them flicker, go red or
turn off. Markers can carry `min_damage` / `max_damage` so a hazard spot only exists in damaged rooms.

### 3.7 Department look on shared tiles
Shared tiles use a few **named material slots** (`wall`, `floor`, `trim`, `accent`). When the floor is
built, the department's palette fills those slots, and `sign` markers get a room-name sign in the
department's style. That's how an office feels like a Robotics office on a Robotics floor.

---

## 4. Data (all new fields are additions, nothing renamed)

### 4.1 `DepartmentData` (existing class, new fields)
```gdscript
# Layout
@export var welcome_center_scene: PackedScene        # fixed template (desk, security room, 2 hallway connectors)
@export var room_types: Array[RoomTypeData]           # this department's rooms (see 4.3)
@export var required_room_kinds: PackedStringArray    # ALREADY EXISTS: e.g. ["assembly_floor", "robot_test_bay", "server_room"]
@export var shared_room_weight: float = 0.35          # how often a room slot gets a shared room instead
# Look
@export var palette: Dictionary                       # material slot name -> Material ("wall", "floor", "trim", "accent")
@export var signage_style: PackedScene                # how room-name signs look
@export var lighting: LightingStyleData                # colour, brightness, flicker presets for damage
# Props, hazards, story
@export var prop_pool: Array[WeightedIdData]          # props for prop_spawn markers (ids from content/props)
@export var hazard_kinds: PackedStringArray            # e.g. ["sparks", "fire", "malfunction"]
@export var incidents: Array[IncidentData]            # what can go wrong here (see 4.4)
# Enemies: ALREADY EXISTS as enemy_spawns (placeholder entries for now)
```
Old fields `rooms_per_floor_min/max`, `optional_room_chances`, `lift_breaks_min/max` are marked
`@deprecated` once the new generator uses the tuning file instead (Q4).

### 4.2 `RoomData` (existing class, new fields)
```gdscript
@export var tile_role: StringName = &"room"           # room, main_hall, secondary_hall, template
@export var size_category: StringName = &"medium"
@export var damage_levels: PackedStringArray = ["pristine", "light", "heavy", "destroyed"]
@export var part_categories: PackedStringArray = []   # e.g. ["mechanical", "electrical"]
@export var is_combat_room: bool = false              # designed as an arena (more enemy spawns)
```
`size_cells` already exists; for new tiles it counts **grid units** (3 m), and a `grid` setting tells
the two systems apart until the old rooms are gone.

### 4.3 `RoomTypeData` (new, small)
A room type, so departments can list them with weights without listing every tile:
`id` (e.g. `room_type_robot_test_bay`), `room_kind`, `display_name` (for signs and the map),
`weight`, `max_per_floor`, `size_categories` allowed, `part_categories` it suits.

### 4.4 `IncidentData` (new)
What happened on this floor: `id` (`incident_fabrication_fire`), `display_name`, `origin_room_kinds`
(which room types it can start in), `overlay_flavour` (`scorch`, `water`, `biohazard`), `hazard_kinds` it
adds near the origin, and `lighting` (e.g. red emergency light, darkness).

### 4.5 Elevator parts (Q3)
Parts are already data: each lift part is a `PropData` with a `lift_slot`, and the lift adds a slot for
every one. I add two fields to `PropData`:
- `part_size`: small, medium, large, huge. Decides which `lift_part` markers fit it and how likely it is
  on higher floors.
- `part_category`: e.g. `mechanical`, `electrical`, `electronic`, `power`. Matched against tile tags.

Example with the 9 existing parts (if you keep them):

| Part | Size | Category | Natural rooms |
|---|---|---|---|
| Fuse, button, light, vacuum tube | small | electrical / electronic | electronics lab, server room, fuse closets |
| Gear, lever, cable spool | medium | mechanical | machine shop, assembly floor, parts storage |
| Battery | medium | power | charging bay |
| Counterweight (80 kg) | huge | structural | assembly floor, loading areas |

### 4.6 `FloorGenTuning` (new, one file for every number)
`config/floor_gen_tuning.tres`, loaded as `Config.floor_gen`, the same way `Config.feel` works, so the
`tune` console command can change values while the game runs. Every value in section 17 lives here.
Values that grow with the floor use one small pattern: **base + per_floor x (floor - 1), capped at max**.
Part counts use your floor brackets (1-3, 4-7, 8+) as an editable list.

### 4.7 `FloorPlan` (the generator's output, extends today's `FloorLayout`)
Everything every PC needs to build the same floor: tiles (id, cell, turn), each tile's role, room type,
wing, damage level and lights; every connection (which two sockets, door type, keycard number);
the incident origin; the broken parts and their marker; chosen camera markers; chosen enemy, prop and
hazard markers (and the prop id for each); the seed, attempt number and the generation log.
Sent once with `to_dict()`. Proposed size: a few kilobytes, which is fine for one reliable message.

---

## 5. The generation pipeline

**Where it runs:** only on the host, when the lift leaves the previous floor (as today). It has the
whole lift ride (at least 8 s) to finish. It never touches the scene tree; it works on a grid in memory.

**Randomness:** each step gets its own stream: `SeededRng.make(floor_seed, &"floorgen_<step>", attempt)`.
So "same seed, same floor" always holds, and changing how one step rolls doesn't reshuffle the others.
`floor_seed` comes from the run seed and floor number, as today. The log line for every floor:
`[floorgen] floor 4 robotics seed 1837261 attempt 2: OK (38 tiles, 2 parts)`.

**Bookkeeping:** a grid dictionary `cell -> tile index` (overlaps are checked here, never with physics,
as you asked), plus a **graph**: each tile is a node, each joined pair of sockets is an edge with a length
in metres (the walking distance between the two sockets through the tile). Path distance from the
elevator is a shortest-path search on this graph (Dijkstra's algorithm, a standard way to find shortest
routes in a graph).

### Step 1: elevator, welcome center, security room
- Place the elevator template at cell (0,0) with its opening facing -z (the lift's gate side). The
  floor is lined up with the real lift afterwards, as today, so the shaft always lines up.
- Place the department's welcome center template against the opening. The template already contains the
  reception desk (facing the elevator), the security room (behind the desk, on the far wall), and the
  two main hallway connectors (left and right). Proposed template size: 8 x 6 units (24 x 18 m) (V2).
- These are fixed scenes, not random tiles. Until each department has its own, all use a generic one.

### Step 2: grow the two main hallways
- From each connector, grow a main hallway (2 units wide) out of main hallway pieces: straight, corner,
  T-junction, end. Length is rolled from a tunable range that grows with the floor (V3).
- It goes mostly straight; at each piece there's a small chance to turn (V3). It can't turn back toward
  the welcome center, and it stops early if it would hit something.
- ~~Main hallway pieces have a **side socket every 1 unit**~~ **Zachary 2026-10-30:** main hallways are built
  from walled 3-long and 5-long pieces (`main_hall_long_piece_share` picks between them) plus 1-unit fillers
  to hit the rolled length; branches attach only at their side doorways.

### Step 3: branches, single rooms and clusters
- **Zachary 2026-10-30:** walk along each main hallway; at **each side doorway** (the walled pieces set the
  spacing, so V4's "every 2-4 units" interval is gone) roll what goes there:
  **a single room**, **a cluster** (2 to 4 rooms joined by inner doors, one entrance), **a secondary
  hallway**, or nothing.
- Secondary hallways (1 unit wide) grow the same way, and can branch again up to a tunable **max depth**
  (V4). Their ends get a room or a cluster, so dead ends usually lead somewhere.
- At this point rooms are only **slots**: a size category and a footprint, no type yet.
- Each branch off a main hallway is a **wing** (e.g. "East wing B"). Wings are used for spreading parts
  and for the security map.
- Growth stops when the floor reaches its target size (V5), or when nothing else fits.

### Step 4: loops
- Look for pairs of open sockets on **different branches** that are close (within a few units, V6) with
  free cells between them. Join them with a short secondary hallway (a small grid path search).
- Add a small, tunable number (V6). Prefer loops that create a second route to a deep wing, so a blocked
  door later has a detour.

### Step 5: room types
- First, the department's **required rooms**: for each, pick a free slot that fits its size (prefer slots
  far enough from the welcome center to be worth exploring). If none fits, a nearby slot is resized
  or the attempt fails (and the floor regenerates).
- Then every other slot: department room (weight 1 - `shared_room_weight`) or shared room, filtered by
  size, `max_per_floor` and `min_floor`. Then pick a tile of that type and size, and turn it so one of its
  sockets meets the slot's entrance.

### Step 6: incident origin and damage
- Pick one of the department's incidents, then an origin room whose type fits it (e.g. a fabrication
  fire starts in the assembly floor). Proposed rule: at least half the farthest path distance from the
  elevator, so the arrival area is calm (Q13).
- Every room and hallway gets a damage score: **intensity (grows with floor) x falloff (by path
  distance from the origin) + a little noise**. Thresholds turn the score into pristine, light, heavy or
  destroyed (V7). Far from the origin, almost everything is pristine.
- The welcome center and security room never go above light (Q30).
- Damage then picks: overlay layer per tile, lighting (flicker, red emergency, dark), hazard spots
  switched on, and **blocked paths** (some destroyed hallways collapse, only where a loop gives a detour;
  see step 7 for doors).

### Step 7: doors and locks
Each connection gets one of your door types:

| Type | What the player sees | What it takes | Counts as passable for... |
|---|---|---|---|
| Open | A normal double door (`WorldDoor`, E to open) | nothing | everything |
| Broken open | Leaves hanging or missing | nothing | everything |
| Jammed: pry | Stuck door, leaves bent apart a little | hold E **while holding a crowbar** to pry it (section 7b) | everything, once a crowbar is reachable |
| Jammed: no power | Dead door panel, cables to the wall | solve its power puzzle (section 7b) | everything, once its power puzzle is reachable |
| Blocked by debris | Rubble and crates in the doorway | move the physics props away (each liftable by one player, Q8) | everything, once cleared |
| Keycard | Door with a card reader and a coloured light | the matching keycard from this floor (Q9) | everything, once unlocked |
| Collapsed (hallways only) | Ceiling fell in | impassable | nothing (only allowed with a detour) |

- Proposed: rooms get doors on their entrances; joins between hallways are open archways (Q6).
- Damage pushes the odds toward jammed, debris and broken open (V8).
- **Keycards**: pick a few doors to lock (count grows with floor, V9), only on room or wing entrances,
  never on a main hallway. For each lock in order, the keycard goes in a room reachable **from the
  elevator with only the earlier locks opened**. That guarantees every keycard is reachable before its
  door, even with several locks.
- **Jammed doors** use the same "reachable before the door" logic: a pry door needs a crowbar reachable
  without going through it; a power door needs its whole puzzle reachable without going through it.

### Step 7b: jammed doors (Zachary, Q7)
- **Pry doors** need the `item_crowbar` (the melee item that already exists). Look at the door with the
  crowbar in hand and hold E; the leaves creak apart over a few seconds (V15). Without a crowbar: "It's jammed.
  Something to pry it with?" On every floor that has a pry door on a needed route, the generator puts one
  crowbar in a reachable spot (an `item_spawn` marker), even if a player already carries one (F5).
- **Power doors** have a dead panel. A **power puzzle** brings them back. Proposed first version (F6):
  a **breaker box** in another room or hallway nearby, reachable without the door. Pull its lever (a
  `WorldButton` with a lever look) and the door's panel lights up and opens, wired with world_io. Proposed
  second version for later floors: the breaker is missing its **power cell** (a carryable prop, not a lift
  part), which is somewhere else on the floor; carry it to the breaker, then pull the lever.
- The generator draws a cable line on the walls (and on the security map) from the door to its breaker,
  so players can follow it.
- Mix of the two (F7): proposed half and half, with more power doors on Robotics floors.

### Step 8: broken elevator parts
1. **How many:** rolled from your brackets (1-3: 1-2 parts, 4-7: 2-3, 8+: 3-5), all tunable (V10).
2. **Which:** weighted by size; heavier and larger parts get more weight on higher floors (V10).
3. **Where**, rule by rule:
   - Never the welcome center, security room or a main hallway.
   - Path distance from the elevator at least 40% of the distance to the farthest room (tunable).
   - One part per main hallway's side when possible, then different wings.
   - Prefer branch-end rooms and side rooms.
   - Prefer rooms whose `part_categories` match the part, and a `lift_part` marker whose `max_size` fits.
   - **Carry path:** a route back to the elevator through `door` connections only (no vents, crawlspaces
     or jump gaps), where every door is open, broken open, pryable, clearable, or unlocked by a reachable
     keycard. Collapsed hallways don't count.
   - Keycards: at most 1 part behind a keycard door on floors 1-3, more later (V9).
   - Higher floors (Q14): at least one part near the incident origin.
   - Not all parts in combat or hazard rooms (Q15).
   - The marker must be on a surface. If it isn't flagged `visible_from_entrance`, add a cue: a small
     light, sparks, or a glow.
4. **If no spot works**, relax in your order: department fit, then wing spreading, then minimum
   distance. Every relaxation goes in the log. Still nothing: the floor regenerates.

### Step 9: security cameras
- From the `camera` markers, pick: some in each main hallway, one in or next to each part's room, and a
  few random ones (V11). Each gets a label like `CAM 04 EAST WING B`.
- Cameras in heavy or destroyed areas can be broken (V11); they show static.

### Step 10: props, NPCs and hazards
- **Props:** for each `prop_spawn` marker, pick a prop from the department's `prop_pool` (or keep the
  designer's fixed one). Damaged rooms swap some for debris.
- **NPC spawns:** pick which `enemy_spawn` markers are active, based on the existing enemy budget
  (`RunDifficulty.enemy_budget`, which already grows with floor and player count). The enemies system
  spawns the actual enemies, as today. Not every part room becomes a combat room (Q15).
- **Hazards:** switch on `hazard` markers in damaged rooms with hazards from the department and the
  incident (count grows with floor, V12).

### Step 11: navigation
See section 12. In short: build the floor, then bake one navmesh on a background thread (already built),
then spawn props and enemies.

### Step 12: validation
See section 13. If anything fails, the log says why, and the generator tries again with the next attempt
number (a new seed derived from the same floor seed, so it's still repeatable).

---

## 6. Elevator and welcome center (fixed, per department)
- One template per department: `welcome_center_robotics.tscn` etc., listed in the department file. A
  generic one stands in until each department has its own.
- Layout inside the template: the elevator opening on the near wall; the reception desk in the middle,
  facing the elevator; the security room behind the desk on the far wall, with a door (Q29); the left
  and right main hallway connectors (2 units wide).
- Also the natural place for the `printer` and `cart` markers (Q19), since everyone passes through.
- The template is just a tile with `tile_role = template`, so it uses the same standards and tests.

---

## 7. Security room

### 7.1 Map table
- A table with a screen on top (an emissive surface, like a projected display). The map is **drawn from
  the floor plan** (footprints, hallways, doors), not from a camera looking down, so it is clean.
- Drawn by a small 2D control inside a `SubViewport` (an off-screen picture Godot can draw and use as a
  texture), shown on the table's screen. The layout is drawn once; only the dots update.
- Shows: the elevator, **all players' positions** (Q11), and for each broken part, **the wing it is in**,
  shaded and blinking, not the exact room (Q11). Delivered parts disappear from the map.
- Style: dark background, department accent colour lines, room names in small caps, a slow scan line.
- Updates a few times a second (V13). Works on every PC from the same plan; positions come from what each
  PC already sees (players and props are already synced).

### 7.2 Camera monitors
- Several monitors (V11), each with **Prev** and **Next** buttons (`WorldButton`, pressed with E) wired to
  the monitor, so it reuses the door and button kit. The chosen camera per monitor is host state, sent to
  every PC like a door's state.
- Each camera is a `Camera3D` inside a `SubViewport`, shown on the monitor with a `ViewportTexture`.
- To keep it cheap:
  - A feed renders **only while it's on a monitor** and someone is **in or near the security room** (V13).
  - **Low resolution** (proposed 256 x 144) and **a reduced rate**: the viewport is set to "update once"
    on a timer (proposed 8 times a second) instead of every frame.
- Looks like security footage: a screen shader adds noise, scan lines and a slight colour tint; a
  label overlay shows `CAM 04 EAST WING B` and a timestamp. A broken camera shows animated static.
- Each PC renders its own monitors (pictures are never sent over the network).

New system for this, `systems/security/` (Q16 covers folders), so level_gen stays a generator.

---

## 8. Departments (expanded)

All three use the same shared pool: office, storage room, bathroom, break room, janitor closet, plus
shared hallway pieces. Shared rooms take the department palette and signs.

### Botany (Zachary, Q2: Botany stays; your Biology list re-themed for plants, check it: F4)
- **Required:** greenhouse / hydroponics bay (large), seed vault (small, the cold storage), decontamination
  airlock (small, two doors, sits between a hallway and a lab: a natural choke point).
- **Other:** plant cell culture lab, microscopy lab, soil and sample prep, autoclave room, growth chamber
  (sealed grow lights), irrigation pump room.
- **Props:** microscopes, centrifuges, fume hoods, sample racks, biohazard bins, potted plants (the
  `item_potted_plant` exists), seed trays, grow lights, nutrient tanks, watering carts.
- **Hazards:** toxic spores (damage over time, drifts), toxic gas, contaminated water, overgrown vines
  (debris made of plants in doorways).
- **Incidents:** overgrowth breach (origin: greenhouse; vines overlay), toxic spore release (growth
  chamber / cell culture lab), irrigation flood (pump room; water overlay), seed vault cooling failure
  (frost overlay).
- **Look:** clinical white with green accents and bright flat light; damage turns lights green-tinted and dim.
- **Natural parts:** electrical in the growth chamber and labs; mechanical and power in the pump room.
- **Upgrades:** DNA vials with plant mutations appear here (the design decision for Botany stays as is).

### Zoology
- **Required:** animal holding / enclosure room (large), veterinary surgery (medium), feed storage (small).
- **Other:** observation room with one-way glass, aquarium / tank room, habitat simulation room (large),
  quarantine pens.
- **Props:** cages, tanks, feeding equipment, tranquilizer stations, feed sacks, hay bales, vet trolleys.
- **Hazards:** broken enclosures (an enemy spawn plus debris), flooded tank rooms (water slows players,
  shorts out electrical parts' cue sparks).
- **Incidents:** enclosure breakout (holding room; claw marks, broken cages), tank rupture (aquarium;
  water overlay spreading to neighbours).
- **Look:** warmer, natural tones (wood, sand, moss green), warm light; damage gives broken skylights and
  dark corners.
- **Enemies:** the existing rat, bat, fly and kangaroo already belong here.

### Robotics (built first)
- **Required:** assembly / fabrication floor (large), robot test bay (large), server / control room
  (medium).
- **Other:** machine shop, parts storage, charging bay, electronics lab.
- **Props:** robotic arms, workbenches, conveyors, charging docks, component crates, tool carts,
  oil drums.
- **Hazards:** exposed wiring and sparks, malfunctioning machinery (a swinging arm zone), fires.
- **Incidents:** fabrication fire (assembly floor; scorch overlay, smoke), test bay malfunction (robot
  test bay; wrecked machinery), server room overload (server room; sparks, dark power cut).
- **Look:** industrial grey, safety yellow stripes, cold strip lights; damage gives red emergency lights.
- **Natural parts:** mechanical in machine shop and assembly; electronic in electronics lab and server
  room; power in charging bay.

Enemy types per department stay placeholders, as you asked.

---

## 9. Damage, in more detail
- Four levels: pristine, light, heavy, destroyed. Every tile has overlays for at least pristine and light.
  If a tile lacks a higher level, it uses its highest one and the log notes it.
- **The story:** damage falls off with path distance from the origin, so walking toward the origin feels
  like walking toward the incident. A little noise stops it from looking like perfect rings.
- **Lighting:** light = occasional flicker; heavy = red emergency lights, some lights off; destroyed =
  mostly dark, sparking fixtures. Done by switching the tile's `tile_light` nodes and swapping in
  emergency lights from the overlay.
  **Zachary 2026-10-30:** heavy = lights flicker more and stay dark longer between flickers; destroyed =
  lights off or a rare faint flicker, with the red emergency light on and now and then flickering. All
  tunable in `config/floor_gen_tuning.tres` ("Damage lighting"); built in step 2 as `TileLightFlicker`.
- **Hazards:** only in heavy and destroyed areas, more on higher floors.
- **Blocked paths:** collapsed hallways only where a detour exists; jammed and debris doors anywhere,
  because players can always open them. Main hallways never fully collapse (Q31).
- **Scaling:** intensity = base + per floor, capped (V7), so higher floors have bigger damaged areas.

---

## 10. Broken parts, carry paths and keycards

### 10.1 What counts as "reachable"
The validator walks the graph from the elevator. A connection is walkable if it's open, broken open,
debris (clear), keycard **once its keycard is reachable**, pry door **once a crowbar is reachable**, or
power door **once its breaker (and power cell, if any) is reachable**. Collapsed hallways and
non-door sockets (vents etc.) are not walkable while carrying a part.

### 10.2 Matching parts to rooms
A part fits a room if the room's `part_categories` includes the part's `part_category` and a `lift_part`
marker in the room allows the part's size. "Fall back to any eligible room" means: drop the category
match, keep the size match.

### 10.3 Changes to the cargo lift (Q4)
Today the lift picks 1 to 3 broken slots and spawns parts at the farthest `lift_part` markers by
straight-line distance. With this plan:
- The generator picks the broken parts and their markers (path distance, all your rules).
- `CargoLift.arrive()` reads the broken slots from the plan instead of rolling them.
- On `floor_ready`, the lift spawns each part at the marker the plan names.
- The respawn of lost parts ("every second, check each part still exists") picks a valid marker from the
  plan's list of backup spots, not just the farthest one.
- The battery charger marker also comes from the plan.
This is a change inside `systems/cargo_lift/`, which needs your OK per the project rules.

---

## 11. Multiplayer and determinism
- **Host only** runs the generator (rule 4 in CLAUDE.md: randomness only on the host).
- The host sends `plan.to_dict()` with the floor change, as today; joiners get it in the join handshake.
- **Every PC** builds the static floor from the plan: tiles, caps, damage layers, palette, signs, doors,
  monitors and the map. Node names come from the plan's order, so they match on every PC (doors need
  that for their state syncing).
- **Only the host** spawns networked things through their owners: parts (cargo_lift), keycards and
  debris (physics_props), enemies (enemies), hazards (if they need syncing).
- Door states, keycard locks, pry progress and monitor channels sync through `WorldDevice.push_state`.
- Regenerating with the debug key goes through the normal floor change, so clients follow.

---

## 12. Navigation: my recommendation

**Use the existing whole-floor bake on a background thread**, not pre-baked regions per tile.
**Measured 2026-10-31 (step 3):** about 50 ms for the biggest floors, so this stays.

- It already exists and works (`Enemies.bake_navigation`), including re-baking when a door opens, locks
  or breaks, and leaving out doors enemies can push open.
- Damage changes the floor (debris, collapsed hallways). A per-tile navmesh would have to match every
  damage layer and every door type; one bake after building just sees what's there.
- Per-tile regions also have to line up exactly at doorways in every rotation, which is fiddly.
- The risk is bake time on big floors. Step 3 measures it on the largest floors. If it's too slow, the
  fallback is per-tile regions joined at sockets, and nothing else in the plan changes.

**Order on floor load:** all PCs build the floor; the host bakes the navmesh; then `floor_ready` fires
and props, parts and enemies spawn. Today `floor_ready` fires before the bake finishes, so this needs a
small change in game_flow (wait for the host's bake) and enemies (start baking on `floor_built`). Both
are other systems' code (Q20).

---

## 13. Validation (after every attempt)
1. Every part is reachable and has a valid carry path back to the elevator (10.1).
2. Every keycard is reachable without its own door (or any later lock). The same for every crowbar
   (before the pry doors that need it) and every breaker and power cell (before their power door).
3. Every required room for the department is present.
4. No overlapping footprints (grid bookkeeping).
5. No door opens into a wall: every used socket meets another socket face to face; every unused socket
   gets a cap.
6. The floor is completable after damage: the elevator, every part, every keycard and the security room
   are connected with walkable connections.
7. Part rules held, or were relaxed in the allowed order (logged).
8. At least one part outside combat and hazard rooms.

**On failure:** log `attempt 3 failed: part prop_lift_gear has no carry path (collapsed hallway at
(14,-6))`, try the next attempt. After a tunable number of attempts (V14) it builds a **safe fallback
floor** (welcome center, two straight main hallways, required rooms at the ends, parts in end rooms, no
locks or collapses) and logs loudly, so a run can never get stuck (Q24).

**Bulk test:** a GUT test generates 500 seeds per department and floors 1 to 15 and checks all 8 rules.

---

## 14. Debug tools (built alongside, in step 3)
- **Overhead debug view** (proposed key **F3**, Q22): a 2D overlay drawn from the plan. Main hallways
  thick, secondary thin, rooms filled by damage colour (green, yellow, orange, red), the incident origin
  as a star, parts as numbered diamonds with their carry paths, locked doors as coloured padlocks with a
  line to their keycard, cameras as small triangles (crossed out if broken), wings outlined, loops
  highlighted, your position as an arrow. Mouse wheel zooms.
- **Seed on screen** in the corner of the overlay: `seed 1837261 / attempt 2 / floor 4 Robotics`.
- **Regenerate instantly** (proposed **F4**, host only): new random seed, same floor number, players
  back in the elevator.
- **Enter a seed:** a text box in the overlay, plus console commands `floorgen <seed>`,
  `floorgen dept <id>`, `floorgen floor <n>`, `floorgen log`.
- **Generation log:** every step, every choice that matters, every relaxation and every failed attempt.
  Shown in the overlay, printed to the Output panel, and saved to `user://floorgen/last_floor.log`.
- **Standalone test scene** `systems/level_gen/test/floorgen_viewer.tscn` (F6): generates floors without
  playing, with the same overlay and a 3D fly-around view, so layout can be checked fast.

---

## 15. Build order (one step at a time, each tested in the running game)

Each step is built on its own branch from `main`, with its own GUT tests, then merged with the merge
prompt after you've played it. I'll ask before every commit, push and merge.

### Step 1: this plan
You read it, answer the questions in section 16, and approve. **Stop here until you approve.**

### Step 2: tile standards and CSG blockout tiles
- Write `docs/systems/level_gen.md` updates: grid, doorway, ceiling, sockets, markers, tags, overlays.
- Add the new data fields (section 4) and `FloorGenTuning` with defaults.
- Blockout tiles (CSG, grey, with overlay layers as simple coloured boxes): elevator template, generic
  welcome center + security room, main hallway pieces (straight, corner, T, end), secondary hallway
  pieces (straight, corner, T, cross, end), and shared rooms in each size (office, storage, bathroom,
  break room, janitor closet). About 20 tiles.
- A **tile gallery** test scene that lays out every tile with sockets and markers drawn.
- GUT: every tile's sockets sit on the grid at the standard size, footprint matches its data, every room
  has a socket on each side, every tile has pristine and light overlays.
- **How to test:** open the tile gallery (F6), walk through each tile with the player, check doorways
  feel right and a cart fits. Tell me if 3 m and 2.4 m feel right.

### Step 3: layout generator and debug view
- `FloorGenerator` steps 1 to 4 and a simple step 5 (shared rooms only), the plan, `Level.build` for it,
  caps, the debug overlay, seed display, regenerate key, seed entry, log.
- Measure the navmesh bake time on the biggest floors (decides section 12).
- GUT: same seed same floor; no overlaps; every socket joined or capped; both main hallways exist;
  branch depth within the limit; loops within the limit; 500 seeds never crash.
- **How to test:** start a run, ride to floor 1, press F3 to see the map, walk both main hallways, press
  F4 a few times, type a seed you liked and get the same floor back. Then 2 game copies: both see the same floor.
- **Built 2026-10-31.** Measured on floor 18 (68-87 tiles, 27 rooms): planning about 9 ms, building about
  55 ms, the whole-floor navigation bake about 50 ms (about 1,200 polygons), so section 12's whole-floor bake
  stays. 500 seeds over floors 1-18 needed no fallback floor. Department per floor (F1-F3) is left to the
  next step (game_flow). Main hallways don't use T pieces yet; loops are straight 1-unit filler runs.

### Step 4: Robotics end to end (split into small steps, each played before the next)
- **Built 2026-10-31 (4a, with F1-F3):** a department rolled every floor (game_flow), the Robotics department
  and its 8 tiles, generator step 5 with required rooms, palettes and room signs. Botany and Zoology are
  placeholder department files (shared rooms only). Waiting for Zachary to play it.
- 4a: Robotics department file, its welcome center, its required and other room tiles; step 5 with
  required rooms. *Test: every Robotics floor has the assembly floor, test bay and server room (F3 shows them).*
- **Built 2026-10-31 (4b):** incidents and damage levels, real blockout debris, collapses only with a detour,
  placeholder sparks and fire (`systems/hazards`), loose debris props, damage on the F3 map, `floorgen origin` and
  `floorgen damage` debug commands. Waiting for Zachary to play it.
- 4b: incident and damage: overlays, lighting, hazards (placeholder sparks and fire). *Test: walk toward
  the origin and see damage grow; the F3 view matches.*
- 4c: doors: open, broken open, pry doors (crowbar), power doors (breaker box), debris, keycards, collapsed
  hallways. *Test: find a keycard, open its door; find the crowbar and pry a door; follow a cable to a breaker
  and power a door; clear debris; find the detour around a collapse.*
- 4d: parts: counts, picks, placement rules, carry paths, cargo_lift reading the plan. *Test: find every
  part, carry it back, fix the lift, ride up. Check parts make sense where they are.*
- 4e: cameras and the security room: map table and monitors. *Test: stand at the map, see the part wings
  and your dot move; cycle monitors with the buttons; broken cameras show static; frame rate stays steady.*
- 4f: props, NPC and hazard markers, navigation order, validation and fallback floor. *Test: enemies path
  through doors; props appear after the floor is ready; the bulk GUT test passes 500 seeds.*

### Step 5: Botany and Zoology
Mostly content: department files, welcome centers, room tiles, incidents (gas, flood), hazards,
palettes. New code only for new hazard kinds. *Test: play 3 floors of each; F3 view on 10 seeds each.*

### Step 6: tuning pass
Every number in `config/floor_gen_tuning.tres`, grouped and commented. Play floors 1, 4, 8 and 12 in
each department and adjust size, damage, parts, locks and cameras together. *Test: you play a run and
we change numbers live with `tune`.*

### Files and folders this touches (and who owns them)
| Folder | Owner | Change | Needs your OK? |
|---|---|---|---|
| `systems/level_gen/` | level_gen | most of the work | it's the system being built |
| `core/data/levels/`, `core/data/props/`, `core/config/`, `core/autoload/config.gd` | shared | **add** fields, classes, `Config.floor_gen` | additions are allowed; listed in merge notes |
| `content/departments/`, `content/rooms/`, `content/props/` | content | new files | no |
| `systems/security/` (new) | security | map table, monitors, cameras | new folder (Q16) |
| `systems/hazards/` (new) | hazards | placeholder hazards | new folder (Q16) |
| `systems/cargo_lift/` | cargo_lift | read parts from the plan | **yes** (Q4) |
| `systems/world_io/` | world_io | keycard reader device | **yes** (Q10) |
| `systems/game_flow/`, `systems/enemies/` | those systems | floor_ready after the nav bake | yes (Q20: approved) |
| `systems/game_flow/` | game_flow | a department rolled per floor; boss floors and run length (16b) | approved in Q1 |
| `systems/world_io/` | world_io | breaker box (lever) and power cell socket for power doors | approved with Q10 |
| `tests/unit/level_gen/` | level_gen | old tests updated when the old generator retires | **yes** (Q18) |

No paid tools are needed for any of this: CSG blockouts are made in Godot, and there are no AI-made
assets until art starts (then each Meshy or ElevenLabs asset goes in `docs/AI_CONTENT_LOG.md` for Steam's
AI-content disclosure, after checking the tool's commercial licence).

---

## 16. Questions for you

Each has my recommendation. You can answer "go with your recommendations" and then only list the ones
you want different.

**Big picture**
- **Q1. Department per floor or per block?** **Answered: a new department every floor** (F1 to F3).
- **Q2. Biology or Botany?** **Answered: keep Botany.**
- **Q3. Which elevator parts?** The lift already has 9 built part types with special rules (heavy
  counterweight, fragile vacuum tube, battery that needs charging). Your list: motor, cable spool, control
  board, fuse box, brake assembly, pulley. *Recommend:* keep the 9, give each a size and category, and add
  motor, control board and brake assembly as new content files (a new part type needs no code; the lift
  panel grows a row). Or tell me to swap to your 6.
- **Q4. Who picks the broken parts?** *Recommend:* the generator (it needs to know them to place them), and
  the floor brackets in the tuning file replace the department's `lift_breaks_min/max`. Needs a change in
  cargo_lift.
- **Q5. Grid and doorway sizes:** 3 m grid, 2.4 x 2.8 m doorways, 3.6 m ceilings (section 3.1).
  *Recommend:* yes, and we check the feel in step 2.

**Layout**
- **Q6. Doors everywhere?** *Recommend:* every room entrance has a door; joins between hallways are open
  archways.
- **Q13. Incident origin:** one per floor, at least half the farthest distance from the elevator?
  *Recommend:* yes.
- **Q26. Taller rooms:** may large rooms be taller inside (e.g. 6 m for the assembly floor) as long as the
  doorways are standard? *Recommend:* yes.
- **Q27. Room shapes:** rectangles only, every room tile with a socket on each side? *Recommend:* yes for now;
  L-shapes later.
- **Q28. Clusters:** 2 to 4 rooms, inner connections are doors. *Recommend:* yes.
- **Q29. Security room door:** always an ordinary open door, never locked? *Recommend:* yes.
- **Q30. Damage near the start:** welcome center and security room at most "light"? *Recommend:* yes.
- **Q31. Main hallways:** never fully collapse (debris is fine)? *Recommend:* yes.

**Doors and keycards**
- **Q7. Jammed doors:** **Answered: a crowbar to pry, or a puzzle that powers the door** (section 7b, F5 to F7).
- **Q8. Debris:** a pile of 4 to 8 physics props, each light enough for one player? *Recommend:* yes.
- **Q9. Keycards:** one keycard per door, colour-matched (red card, red door)? *Recommend:* yes, at most 3
  colours per floor.
- **Q10. Where keycard code lives:** objectives (not built yet) planned a keycard door. world_io now has
  doors with lock/unlock. *Recommend:* add a small `KeycardReader` device to world_io and a keycard prop;
  objectives can build on it later.

**Parts**
- **Q14. "Higher floors"** for "at least one part near the origin" and "more parts behind keycards":
  *Recommend:* floor 4 and up. "Near" = in a heavy or destroyed room, or within 15 m path of the origin.
- **Q15. One part on the floor:** your rule "never all parts in combat or hazard rooms" means a single
  part is always in a calm room. *Recommend:* yes, keep that literally.

**Security room**
- **Q11. The map:** "area" = the wing (the branch off a main hallway) shaded on the map; show every
  player's dot in their colour; a part's wing follows the part if someone moves it. *Recommend:* yes.
- **Q12. Cameras and monitors:** 4 monitors; 2 cameras per main hallway, 1 per part room, 2 random; feeds
  render only while someone is within 12 m of the security room. *Recommend:* yes, then tune.

**Other systems**
- **Q16. New folders:** `systems/security/` for the map and monitors, `systems/hazards/` for hazards
  (placeholder sparks, fire, gas, water that hurt or slow through the existing damage system).
  *Recommend:* yes.
- **Q17. Boss floors:** keep today's boss floor (the lift with the arena next to it), rebuilt on the new
  grid, not generated. *Recommend:* yes.
- **Q18. Retire the old generator:** once step 3 works, switch the old grey-box rooms off and update the
  old level_gen GUT tests to the new generator. *Recommend:* yes (the project rules need your OK to change tests).
- **Q19. Other markers:** printer and cart in the welcome center; vending machines in break rooms and
  offices; the upgrade machine in any medium room; the battery charger in electrical rooms (charging bay,
  electronics lab). *Recommend:* yes.
- **Q20. Floor load order:** game_flow waits for the host's navmesh before `floor_ready`, so props and
  enemies spawn after navigation is ready. *Recommend:* yes (small changes in game_flow and enemies).
- **Q21. NPCs:** enemies only for now (friendly scientists could use the same markers later)?
  *Recommend:* yes.
- **Q22. Debug keys:** F8 overlay, F9 regenerate (F7 is already used in the feel playtest).
  **CHANGED 2026-10-31 (Zachary's playtest):** F3 map, F4 new floor. F8 can't be used: the Godot editor stops
  a running game on F8 (F5 to F8 are its run keys). They are input actions (`debug_floor_map`,
  `debug_floor_regenerate`), so they can be rebound.
  *Recommend:* yes.
- **Q24. When every attempt fails:** build the safe fallback floor and log it. *Recommend:* yes.
- **Q25. Welcome centers:** one generic template until each department gets its own (Robotics in step 4).
  *Recommend:* yes.

**Answers (Zachary, 2026-10-30):** Q1 a new department every floor; Q2 keep Botany, drop Biology;
Q7 jammed doors need a crowbar or a power puzzle; every other question: the recommendation.

---

## 16b. Follow-up questions from those answers

**Answered (Zachary, 2026-10-30): all seven recommendations accepted.**

- **F1. Boss floors (from Q1).** *Recommend:* keep a boss floor after every 5 regular floors (floors 6,
  12, 18), with its department rolled among departments that have a boss (today only Zoology's giant rat).
- **F2. Repeats (from Q1).** *Recommend:* never the same department two floors in a row.
- **F3. Run length (from Q1).** Today a run is 3 departments x (5 floors + boss) = 18 floors.
  *Recommend:* keep 18 floors, as two new GameConfig numbers (`run_floor_count` 18, `boss_every_floors` 6)
  replacing `departments_per_run` and `floors_per_department`.
- **F4. Botany rooms (from Q2).** Section 8 re-themes your Biology list for plants: required greenhouse /
  hydroponics bay, seed vault, decontamination airlock. *Recommend:* as written; change any room you like.
- **F5. Crowbars (from Q7).** *Recommend:* every floor with a pry door on a needed route spawns one crowbar
  somewhere reachable before it, even if a player already has one.
- **F6. The power puzzle (from Q7).** *Recommend:* first version: a breaker box with a lever somewhere
  reachable, a cable line on the wall leading to it. From floor 4: the breaker is missing a power cell you
  have to find and carry to it first.
- **F7. Pry or power (from Q7).** *Recommend:* half and half, with more power doors on Robotics floors.

---

## 17. Numbers I made up (all go in `config/floor_gen_tuning.tres`)

Values you gave are marked **(yours)**. Everything else is my guess for you to check.

| # | Value | Proposed |
|---|---|---|
| V1 | Grid unit / doorway / ceiling / wall | 3 m / 2.4 x 2.8 m / 3.6 m / 0.3 m |
| V2 | Room sizes; welcome center; elevator | see 3.2; 8 x 6 units; 3 x 3 units |
| V3 | Main hallway length; turn chance | 10-14 units on floor 1, +1 per 2 floors, max 24; 10% per piece, at most 2 turns |
| V4 | Branch interval; branch odds; max depth | ~~every 2-4 units~~ at each side doorway (Zachary 2026-10-30); room 40%, cluster 20%, secondary hallway 30%, nothing 10%; depth 2 on floors 1-3, 3 on 4+ |
| V5 | Target rooms per floor | 10 + 1 per floor, max 28 (plus hallways) |
| V6 | Loops | 1 on floors 1-3, 2 on 4-7, 3 on 8+; join gap up to 4 units |
| V7 | Damage | intensity 0.35 + 0.06 per floor, max 1.0; falloff over 45 m of path; noise +-0.1; thresholds light 0.2, heavy 0.5, destroyed 0.8; collapse chance 50% for destroyed hallways that have a detour |
| V8 | Door types by damage (open / broken / jammed / debris) | pristine 95/5/0/0; light 75/10/10/5; heavy 40/20/25/15; destroyed 15/35/25/25 |
| V9 | Keycard doors; parts behind keycards | 0-1 on floors 1-3, 1-2 on 4-7, 2-3 on 8+; parts behind locks max 1 / 2 / 3 **(1 on low floors is yours)** |
| V10 | Parts per floor; heavy bias | 1-2 / 2-3 / 3-5 **(yours)**; size weight x (1 + 0.15 x (floor - 1) x size step); minimum distance 40% **(yours)** |
| V11 | Cameras; monitors; broken odds | 2 per main hallway, 1 per part, 2 random; 4 monitors; broken 40% in heavy, 100% in destroyed |
| V12 | Hazards | 1-2 on floor 1, +1 per 2 floors, max 10; only heavy and destroyed rooms |
| V13 | Feed and map rates | feeds 256 x 144 at 8 updates a second, only within 12 m of the security room; map dots 5 times a second |
| V14 | Validation attempts | 25, then the safe fallback floor |
| V15 | Pry time; debris pieces; power doors | 3 s with a crowbar; 4-8 props up to 15 kg each; power door share 50% (65% on Robotics); power cell version from floor 4 |
| V16 | Shared room share | 35% of non-required rooms |

---

## 18. Risks
- **Rotated tiles are the classic bug source** (sockets ending up one cell off). The existing
  `RoomShape` turning code is tested and reused, and the tile gallery plus a GUT test on every tile in
  every rotation catches mistakes early.
- **Too many tiles needed.** Each department needs roughly 10 to 15 tiles before floors feel varied.
  Blockouts are fast; art later replaces them one at a time without code changes.
- **Camera feeds cost frame rate.** Each feed is a second render of the level. Low resolution, low rate
  and only-when-watched should hold it; step 4e measures it.
- **Navmesh bake time** on big floors (section 12, measured in step 3).
- **Generation time.** GDScript is slow-ish, but there's a whole lift ride for it. If needed, it can run on
  a background thread, since it doesn't touch the scene tree.
- **Scope.** Step 4 is the biggest. It's split into 4a to 4f so you can play each part before the next.
