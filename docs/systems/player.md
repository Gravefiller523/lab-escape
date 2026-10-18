# player

Folder: `res://systems/player/` · Size: L · Phase 1a (walking) and 1b (movement modes)

## Purpose
The first-person scientist: walking, sprinting, jumping, crouching, camera and mouse look, and the
body other players see. Movement can be changed by upgrades through **movement modifiers** and
**movement modes** (wall climb, slide, hop), which are reusable building blocks. Has named
**attach points** where mutation parts and cosmetics are added. Spawns player bodies and syncs them.

**Not responsible for:** health (damage component on the player), inventory (inventory component),
picking things up (interaction, physics_props), what upgrades do (upgrades decides, player just obeys modifiers).

## Public API
```gdscript
class_name PlayerCharacter extends CharacterBody3D
var player_id: int
func is_local() -> bool
func get_camera() -> Camera3D
func get_aim_origin() -> Vector3
func get_aim_direction() -> Vector3
func get_hold_point() -> Node3D                     # where held props float (used by physics_props)
func get_attach_point(point: StringName) -> Node3D  # &"head", &"face", &"back", &"left_arm", &"right_arm", &"legs", &"feet", &"body"
func get_movement() -> PlayerMovement
func teleport(xform: Transform3D) -> void           # host calls; tells the owning PC to move
func set_input_enabled(enabled: bool) -> void       # local; menus and console turn input off
func set_body_visible(visible: bool) -> void        # ghosts while dead
static func of(node: Node) -> PlayerCharacter       # climbs parents until it finds one
static func find(player_id: int) -> PlayerCharacter # null if not spawned
var tuning: PlayerTuning                            # NEW 2026-10-17: movement numbers (player_tuning.tres)
func set_input_override(input: PlayerInputState) -> void   # NEW 2026-10-17: tests only
const GROUP: StringName = &"players"                # NEW 2026-10-17: every body is in this group

class_name PlayerMovement extends Node              # child "Movement" of the player
signal mode_changed(mode: StringName)
func set_modifier(source_id: StringName, effect: MovementEffectData) -> void
func remove_modifier(source_id: StringName) -> void
func get_active_mode() -> StringName
func get_wanted_mode() -> StringName                # NEW 2026-10-17: what the modifiers ask for, even if that mode has no file yet
func get_speed_multiplier() -> float                # NEW 2026-10-17 (also jump, gravity, height)
func can_jump() -> bool                             # NEW 2026-10-17
static func load_mode(mode_name: StringName) -> MovementMode   # NEW 2026-10-17: null if no file
func get_height() -> float
func is_crouching() -> bool
func is_grounded() -> bool
func apply_knockback(impulse: Vector3) -> void      # host calls; forwarded to owner

class_name MovementMode extends RefCounted          # base for building blocks
func enter(body: PlayerCharacter) -> void
func exit(body: PlayerCharacter) -> void
func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void
# CHANGED 2026-10-17: takes a PlayerInputState (move, jump_pressed, sprint, crouch) instead of
# input_dir, because modes need jump/crouch/sprint too and tests can fill one in by hand.

class_name PlayerSpawner extends Node               # put one in every playable scene
@export var spawn_points: Array[Node3D]             # NEW 2026-10-17
@export var container: Node3D                       # NEW 2026-10-17: where bodies go (default: parent)
@export var auto_spawn: bool = true                 # NEW 2026-10-17: see "Spawning" below
func spawn_all(spawn_points: Array[Node3D]) -> void # host
func spawn_player(player_id: int, xform: Transform3D) -> PlayerCharacter   # host
func despawn_player(player_id: int) -> void         # host
func get_body(player_id: int) -> PlayerCharacter    # NEW 2026-10-17
func use_net(net: NetService) -> void               # NEW 2026-10-17: tests only
```
NEW 2026-10-17 **Spawning** (with `auto_spawn` on, host only): bodies spawn when the scene starts and
when a player joins or reconnects, **except players waiting for the next floor** (mid-run joiners,
see net_core). On `floor_ready` every connected player without a body is spawned, which is when
waiting players appear. When a player leaves, their body is removed. When the connection changes
(hosting, joining, leaving), each PC drops its old bodies and the host spawns fresh ones.
Movement modifiers combine: multipliers multiply, `can_jump` is false if any modifier says false,
the mode with the highest `mode_priority` wins. Mode name `wall_climb` loads
`systems/player/movement_modes/wall_climb_mode.gd` (file name = mode name + `_mode.gd`), so a new
mode is one new file and no list to edit. Launch modes: `walk` (default), `wall_climb` (Octo),
`slide` (Slug), `hop` (Frog), `hover` (Fly, short glides).

Height: Giraffe's `height_multiplier` makes the body taller; door frames block standing, so the player must crouch (crouch height also scales).

## EventBus
- Emits: `player_spawned`, `local_player_spawned` (on every PC, when a body enters the level).
- Listens: `player_left` (despawn), `settings_changed` (sensitivity, FOV, reduce motion; STUB until settings_input).
  NEW 2026-10-17: also `player_joined`, `player_reconnected` (spawn) and `floor_ready` (spawn waiting players).

## Data it owns and saves
Movement tuning numbers (walk speed, jump height, crouch height) live as exported fields on the player
scene's root, with a `player_tuning.tres` resource so they're tweakable without code. Saves nothing.

## Adding content
New movement modes: a new `<name>_mode.gd` in `movement_modes/` (a new building block; code).
Mutations that only use existing modes and multipliers need no code.

## Multiplayer
- **Each player's PC is the multiplayer authority of its own player node** (see CLAUDE.md §6, the one
  exception to host authority). It moves itself instantly. A `MultiplayerSynchronizer` sends position,
  rotation, aim pitch, crouch and animation state to everyone (~30 times a second, interpolated on others).
  NEW 2026-10-17: the owner writes `sync_position`, `sync_yaw`, `sync_pitch` and `sync_crouch`; others
  slide toward them (`remote_smoothing` in the tuning file) and jump if more than
  `remote_snap_distance` away. No animation state yet (no model).
- NEW 2026-10-17: host-to-owner calls (`teleport`, knockback) are `any_peer` RPCs that only accept the
  host (peer 1) as sender, because the owner, not the host, is the node's authority.
- The host sanity-checks: a position jump larger than possible speed allows is corrected by `teleport()`.
- Spawning: only the host spawns players, through a `MultiplayerSpawner` in the scene. The player
  node is named by player id so its node path is the same on every PC.
- Modifiers are applied on every PC (the owner needs them for movement, others for visuals and height).

## Dependencies and stubs
net_core (ids, authority), settings_input (mouse settings: stub with defaults). Needs a test level: a grey-box floor with a ramp, a door frame and a wall to climb.

## Test scene and GUT tests
Test scene `systems/player/test/movement_test.tscn`: grey-box course (ramp, low door, climbable wall,
gap to hop), number keys to toggle each test MovementEffectData on and off.
GUT tests: `test_modifiers_multiply`, `test_highest_priority_mode_wins`, `test_can_jump_false_blocks_jump`,
`test_remove_modifier_restores_defaults`, `test_mode_file_found_by_name`, `test_find_by_player_id`.
NEW 2026-10-17 (`tests/unit/player/test_movement.gd`): `test_missing_mode_file_falls_back_to_walk`,
`test_walking_moves_forward`, `test_crouch_lowers_height_and_stands_back_up`, `test_height_multiplier_makes_body_taller`.
NEW 2026-10-17 (`tests/unit/player/test_player_spawning.gd`, real ENet, each test "PC" is a SubViewport
with its own physics): `test_solo_spawns_own_body`, `test_joining_player_gets_a_body_on_every_pc`,
`test_client_movement_reaches_host`, `test_host_pulls_back_impossible_moves`, `test_leaving_player_body_is_removed`,
`test_mid_run_joiner_spawns_on_next_floor`, `test_eight_bodies_can_spawn`.
NEW 2026-10-17, test scene: built in code (floor, crates, ramp, a 1.5 m door, a tall wall), Host/Join/Leave
buttons, STUB "Start run" and "Next floor" buttons for game_flow, keys 1 (fast), 2 (no jump), 3 (Giraffe x1.4),
launch options `-- host` / `-- join`.

## Acceptance criteria
- [x] Walk, sprint, jump, crouch feel responsive; 2+ local players see each other move smoothly.
  *(Built and tested in code; 3 local instances spawned and saw each other. "Feel" and "smooth" need Zachary's eyes.)*
- [ ] A MovementEffectData with `wall_climb` lets you climb the test wall, with no code change. *Phase 1b: no wall_climb mode yet.*
- [x] Giraffe height test: can't walk through a low door standing, can while crouched. *(Height and crouch scaling built and unit-tested; door check by eye with key 3.)*
- [x] Nothing assumes 4 players; 8 local bodies can spawn. *(test_eight_bodies_can_spawn)*

## Open design questions
- DEFAULT: client-owned movement (feels good, easy). Cheating is possible but this is a co-op game among friends. **Zachary to confirm.**
- How strong should Frog's hop and Fly's hover be? Tune in playtests.

- NEW 2026-10-17: missing mode files (e.g. `wall_climb` before Phase 1b) fall back to walk with a plain
  printed message, not a warning. Later: should the content validation test check `movement_mode`
  names against the files in `movement_modes/`?

## Changelog
- 2026-10-07: spec created.
- 2026-10-18 (physics_props branch): physics interpolation is on for the project (smooth motion between physics
  steps on high-refresh screens). The local camera is top-level and follows the body's interpolated position in
  `_process`, with mouse look applied directly; teleports and snaps call `reset_physics_interpolation()`.
- 2026-10-17 (physics_props branch): bodies now collide with props (PROPS added to the collision mask), so
  players bump into props and can stand on them. physics_props adds a collision exception for the prop you hold.
- 2026-10-17: Phase 1a (walking) built. `MovementMode.physics_update` takes a `PlayerInputState`.
  Added `PlayerTuning` (`player_tuning.tres`), `PlayerInputState`, the sync_* values, the modifier
  getters, `get_wanted_mode`, `load_mode`, the spawner's exports and auto-spawning (including mid-run
  joiners waiting for `floor_ready`), `get_body`, and the test-only `set_input_override` and `use_net`.
- 2026-10-18: fix: when the host leaves while you're in a level, the level's PlayerSpawner no longer tries to
  spawn you as it is unloaded (it ignores `player_joined` when out of the tree). Test: `test_unloaded_level_spawns_nobody`.
- 2026-10-18: fix (Steam test): a prop moving into you could push you through a wall and off the map. After each
  move, if your body crossed a wall (a ray at `WALL_CHECK_HEIGHT` = 0.5 m, WORLD layer), the move is undone.
  Test: `test_a_prop_cannot_push_you_through_a_wall`.

## HANDOFF
**Done (Phase 1a, walking):** `PlayerCharacter` (`player.tscn`): walk, sprint (forward only), jump,
crouch (with headroom check), gravity, mouse look, camera, a grey capsule body with a blue visor so
you can see which way others face, the hold point, rough attach point markers, client-owned movement
synced ~30 times a second with smoothing, the host speed check (pulls back impossible moves),
`teleport` and knockback. `PlayerMovement` with modifiers (multiply, can_jump, mode priority) and
modes loaded by file name. `walk` is the only mode. `PlayerSpawner` with auto-spawning, including
the mid-run joining rule. 17 GUT tests, all pass. Checked with 3 local instances.

**Not done yet (later phases):** movement modes `wall_climb`, `slide`, `hop`, `hover` (Phase 1b);
real attach point positions (only rough markers on a capsule); cosmetics; animations and a real model;
reading settings from settings_input (it uses `player_tuning.tres` values for mouse sensitivity and FOV);
a real pause menu (Esc just frees the mouse, clicking takes it back).

**Known bugs / limits:** the speed check only looks at sideways movement (falling is allowed to be fast).
Not tested on real Steam between two PCs yet. Players do collide with each other.

**Stubbed:** settings (`_on_settings_changed` does nothing yet); the test scene's "Start run" and
"Next floor" buttons stand in for game_flow.

**For the next systems:**
- **break_room:** put a `PlayerSpawner` in the scene with `spawn_points` set. That's all you need for bodies.
- **interaction / physics_props:** use `get_aim_origin()`, `get_aim_direction()`, `get_hold_point()`
  and `PlayerCharacter.of(node)`.
- **ui / debug_console:** call `set_input_enabled(false)` on the local body while a menu is open.
- **upgrades:** call `get_movement().set_modifier(upgrade_id, effect)` on every PC.
- **game_flow:** emit `floor_ready` after the floor is built; the spawner spawns everyone then.
