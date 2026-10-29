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
func stop_syncing() -> void                         # NEW 2026-10-18: stop sending this body's updates (game_flow, before a scene change)
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
const LADDER_MODE: StringName = &"ladder"          # NEW 2026-10-24
func get_mode_object() -> MovementMode              # NEW 2026-10-24: the mode running now (tests)
func add_ladder(ladder: Ladder) -> void / remove_ladder(ladder: Ladder) -> void   # NEW 2026-10-24: Ladder calls these
func get_ladder() -> Ladder                         # NEW 2026-10-24: the ladder you can climb now, or null
func is_on_ladder() -> bool                         # NEW 2026-10-24
func let_go_of_ladder() -> void                     # NEW 2026-10-24: jump off (no regrab for ladder_regrab_seconds)
func get_top_speed() -> float                       # NEW 2026-10-24: fastest the active mode goes sideways (the host speed check uses it)

class_name MovementMode extends RefCounted          # base for building blocks
func top_speed(body: PlayerCharacter) -> float     # NEW 2026-10-24: default sprint x speed multiplier; slide and hop go faster
func enter(body: PlayerCharacter) -> void
func exit(body: PlayerCharacter) -> void
func physics_update(body: PlayerCharacter, input: PlayerInputState, delta: float) -> void
# CHANGED 2026-10-17: takes a PlayerInputState (move, jump_pressed, sprint, crouch) instead of
# input_dir, because modes need jump/crouch/sprint too and tests can fill one in by hand.
# NEW 2026-10-24: PlayerInputState.jump_held (true while jump is held; Fly glides with it).

class_name WalkMovementMode extends MovementMode     # NEW 2026-10-24: walk; hover, hop, slide and wall_climb extend it
static func wish_direction(body, input) -> Vector3   # the keys as a flat world direction
static func jump_speed(body) -> float / gravity_of(body) -> float
# steps a mode can change: _speed, _grip, _jump_speed, _jump, _fall, _after_move

class_name Ladder extends Area3D                     # NEW 2026-10-24: systems/player/ladder.tscn, a climbable ladder
@export var height: float = 3.0 / width: float = 0.7 / color: Color   # origin = bottom middle, faces +Z
func get_top_y() -> float / get_facing() -> Vector3 / get_across() -> Vector3
static func of(node: Node) -> Ladder

# PlayerCharacter, NEW 2026-10-24:
func get_look_pitch() -> float                      # radians, + up / - down (ladders use it)
func set_look_pitch(radians: float) -> void         # tests

# NEW 2026-10-29 (HL2 feel step 1):
static func WalkMovementMode.apply_friction(velocity, friction, stop_speed, delta) -> Vector3
static func WalkMovementMode.accelerate(velocity, wish_dir, wish_speed, accel, delta) -> Vector3
static func WalkMovementMode.air_accelerate(velocity, wish_dir, wish_speed, accel, wish_cap, delta) -> Vector3
static func StairStepper.try_step(body, motion, max_height) -> float   # metres stepped up, 0 = no step
class_name CameraFeel extends RefCounted            # landing dip/punch, bob, roll (own camera only)
class_name Footsteps extends RefCounted             # signal stepped(surface: SurfaceType, volume_db, landing)
func PlayerCharacter.get_footsteps() -> Footsteps / add_camera_step(height) / notify_landed(fall_speed)
func PlayerCharacter.apply_floor_settings() / has_legroom_to_stand() -> bool / get_allowed_speed(seconds) -> float

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
mode is one new file and no list to edit. Launch modes (all built 2026-10-24): `walk` (default),
`wall_climb` (Octo: walk into a wall to climb; W up, S down, no keys hangs on, Ctrl lets go, a push over the top),
`slide` (Slug: builds up speed the longer it moves, from its slow start to 1.25 x sprint speed over
`slide_build_up_seconds`; stopping or hitting something loses it; low grip, slopes pull downhill; top speed
`slide_max_speed` x sprint: 2.0, building up over 8 s and lost over 3 s, Zachary's tuning 2026-10-24),
`hop` (Frog: walks slowly; hold jump to charge, let go to leap: a fuller charge leaps higher, further and faster;
little air steering so the leap carries you), `hover` (Fly: hold jump while
falling to glide slowly for up to hover_seconds; landing refills). All their numbers are in `player_tuning.tres`.
**Ladders** (NEW 2026-10-24) beat any mode: inside a Ladder's climb area, in the air or moving forward
(not looking down), you climb (`ladder` mode): forward up (down when looking down past
`ladder_look_down_degrees`), crouch down, left/right along it, jump pushes off, forward at the top steps off.

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
- [x] A MovementEffectData with `wall_climb` lets you climb the test wall, with no code change. *(2026-10-24: key 6 in the test scene; GUT test_wall_climb_goes_up_and_over_a_wall; 2 local instances saw a client climb a 5 m wall.)*
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
- 2026-10-18 (game_flow branch): NEW `stop_syncing()`: game_flow calls it on every body before a scene change,
  so no PC gets updates for a body it no longer has (Godot prints errors for those).
- 2026-10-19 (cargo_lift branch): fix: a host `teleport()` ("Start anyway", bringing everyone into the lift) was
  undone by the host's speed check. The check now expects the jump. Test: `test_host_teleport_is_not_undone_by_the_speed_check`.

- 2026-10-23 (upgrades branch): `PlayerMovement.get_speed_multiplier()` also multiplies damage's `move_speed` stat.
- 2026-10-23 (death_respawn branch): NEW `set_ghost(ghost: bool)` and `is_ghost()`: a dead player's body is hidden, its
  collision is off and it doesn't move (death_respawn calls it on every PC; its camera is death_respawn's).
- 2026-10-24 (settings_input): mouse sensitivity, invert Y, FOV (also live, on `settings_changed`) and the sprint/crouch toggles come from `Settings` (`get_mouse_sensitivity`, `is_invert_y`, `get_fov`, `is_action_on`). `PlayerTuning.mouse_sensitivity` and `fov` are `@deprecated` (kept, not used).
- 2026-10-24: movement modes built: `hover` (Fly), `hop` (Frog), `wall_climb` (Octo), `slide` (Slug), and ladders (`Ladder`, `ladder` mode). Walk became `WalkMovementMode` with overridable steps. NEW: `PlayerInputState.jump_held`, `PlayerCharacter.get_look_pitch` / `set_look_pitch`, the ladder functions on PlayerMovement, tuning groups Ladders, Hover, Hop, Wall climb, Slide. items' mutated plant now grows a real Ladder. Test scene keys 4 to 7 and a ladder platform.
- 2026-10-24 (Zachary): Slug builds up speed while it keeps moving, up to 1.25 x the normal sprint speed (`slide_max_speed` 1.25, NEW `slide_build_up_seconds` 5, `slide_lose_seconds` 1); stopping or getting blocked loses it. Octo: S climbs down and Ctrl lets go (was the other way round). NEW `MovementMode.top_speed()` and `PlayerMovement.get_top_speed()`: the host speed check now allows each mode's own top speed (slug 8.75 m/s, frog `hop_max_speed`). Checked with 2 local instances: a client slug at full speed is never pulled back.
- 2026-10-24 (Zachary, later): Slug top speed raised to 1.75 x the normal sprint speed (`slide_max_speed` 1.75, 12.25 m/s). The host speed check follows it through `top_speed()`.
- 2026-10-24 (Zachary's tuning): `slide_max_speed` 2.0 (14 m/s), `slide_build_up_seconds` 8, `slide_lose_seconds` 3. The slug tests now read these numbers instead of assuming them.
- 2026-10-24 (Zachary): Frog reworked: no automatic hops, walks at `hop_walk_speed_multiplier` (0.5); jumping happens on release: hold jump to charge (`hop_charge_seconds` 1), a full charge leaps `hop_charge_height_multiplier` (1.6) x higher and `hop_charge_forward_multiplier` (2) x faster forward; `hop_forward_speed` 7, `hop_air_control` 0.1 (the leap isn't braked mid-air), `hop_max_speed` 15 (the host speed check allows it). Removed the unused `hop_auto_hops` and `hop_small_height`. The hop mode has `is_charging()` and `get_charge()` (for a HUD bar later). A full-charge leap goes about 12 m; 2 local instances saw it land in the same place.
- 2026-10-29 (feel step 0): `player_tuning.tres` is also `Config.feel.player`: `config/feel_tuning.tres` points at the same file, so the player scene and Config share one instance and the `tune player.<name>` console command changes movement live. No values changed.
- 2026-10-29 (HL2 feel step 1.1 to 1.3, branch feel/step-1): walking is Source-style. NEW static `WalkMovementMode.apply_friction`, `accelerate`, `air_accelerate` and hook `_air_wish_cap(body)` (Fly's glide returns INF). On the ground: friction (NEW `ground_friction` 4, `stop_speed` 2.5) then accelerate (`ground_acceleration` now Source-style, 10). In the air nothing brakes you; `air_acceleration` (now 10) with NEW `air_wish_speed_cap` 0.76 bends your path, and air strafing builds speed (Zachary's choice: full Source-style). `_grip` scales friction too. NEW jump buffer and coyote time (`jump_buffer_seconds`, `coyote_seconds`, both 0.1); you can jump while crouched; holding jump never hops again; a jump pressed on the exact landing tick skips that tick's friction. HL2 numbers: walk 4.8, sprint 7.5, crouch 1.9, jump 0.9 m, gravity 15.24 (the world's `physics/3d/default_gravity` too, was 9.8). Mouse look uses `screen_relative`. Tests: `test_source_movement.gd`, `test_jump_feel.gd`, `test_feel_metrics.gd`. NEW playtest level `systems/player/test/feel_playtest.tscn` with an on-screen list from `playtest_checklist.txt`.
- 2026-10-29 (HL2 feel step 1.4 to 1.8, branch feel/step-1): CHANGED the body's collision shape is a `CylinderShape3D` (was the scene's capsule; `apply_height` handles both) so its flat bottom stands on edges like HL2's box. NEW `StairStepper.try_step(body, motion, max_height)` (`systems/player/stair_stepper.gd`): before each walk move, "lift, move, put down" with `body_test_motion`, onto level geometry only (WORLD layer, never props). NEW tuning group "Stairs and floors": `step_height` 0.45, `floor_snap_length` 0.45, `floor_max_angle_degrees` 46, `wall_min_slide_angle_degrees` 5, `camera_step_smooth_seconds` 0.08; NEW `PlayerCharacter.apply_floor_settings()`, `add_camera_step(height)` (the camera glides over steps), `has_legroom_to_stand()`; `platform_floor_layers` leaves out props, so a thrown crate can't fling you. Crouch-jump: crouching in the air tucks your legs up (NEW `allow_crouch_jump`, `air_crouch_transition_speed`), so a 1.4 m ledge is reachable. Ladders: the top-out climbs at normal speed and lets go once you stand on top. NEW `CameraFeel` (`systems/player/camera_feel.gd`): landing dip and HL2's landing punch on hard falls, view bob and strafe roll (both 0 = off, as in HL2), all scaled by the camera shake setting; NEW tuning group "Camera feel". NEW `Footsteps` (`systems/player/footsteps.gd`, `PlayerCharacter.get_footsteps()`, signal `stepped(surface, volume_db, landing)`): footstep, push-off and landing sounds for every body, local or remote, from position and the floor under it; NEW tuning group "Footsteps" (`footstep_stride` 1.7, sprint 2.1, crouch 1.2, `footstep_volume_db` -6, crouch -18, `footstep_min_speed`, `landing_sound_min_speed`). CHANGED host speed check: judged over `speed_check_window` (0.5 s) instead of every update (the slack used to add up to any speed); the allowed speed can grow past top speed by `speed_check_growth` (8 m/s per second) for bunny hopping, up to `speed_check_max_speed` (22.5); knockback raises it. NEW `PlayerCharacter.get_allowed_speed(seconds)`. Tests: `test_stairs.gd`, `test_camera_feel.gd`, `test_footsteps.gd`, `test_speed_check.gd`, more in `test_jump_feel.gd`.
- 2026-10-29 (Zachary's step 1 playtest): stops slid a little too far, so `ground_friction` 4 -> 6 (stop from a walk about 0.28 s and 0.6 m, was 0.4 s and 0.9 m). `slide_grip` 0.2 -> 0.133 so the slug still slides as far as before.

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
Checked on real Steam between two PCs (2026-10-18). Players do collide with each other.

**Stubbed:** settings (`_on_settings_changed` does nothing yet); the test scene's "Start run" and
"Next floor" buttons stand in for game_flow.

**For the next systems:**
- **break_room:** put a `PlayerSpawner` in the scene with `spawn_points` set. That's all you need for bodies.
- **interaction / physics_props:** use `get_aim_origin()`, `get_aim_direction()`, `get_hold_point()`
  and `PlayerCharacter.of(node)`.
- **ui / debug_console:** call `set_input_enabled(false)` on the local body while a menu is open.
- **upgrades:** call `get_movement().set_modifier(upgrade_id, effect)` on every PC.
- **game_flow:** emit `floor_ready` after the floor is built; the spawner spawns everyone then.

**Movement modes (2026-10-24):** `hover`, `hop`, `wall_climb`, `slide` and ladders are built (see "Public API"; controls as of the later 2026-10-24 changelog line).
The mutation files already named these modes, so Fly, Frog, Octo and Slug move differently with no content
changes. 13 new GUT tests in `tests/unit/player/test_movement_modes.gd` (every mutation's mode has a file, glide
speed and glide time, hop forward throw and small hops, Octo up and over a wall / hang / let go / plain walkers
can't climb, slug keeps sliding and slides downhill under the speed cap, ladder up and off the top, look down to
climb down, jump off, ladder beats a mutation mode). 2 local instances: a client hopping as Frog and climbing a
5 m wall as Octo was seen in the same place on the host, and the host's speed check never pulled it back.
Test scene: keys 4 Fly, 5 Frog, 6 Octo, 7 Slug (the real mutation numbers), a 3 m platform with a ladder.
**Other systems touched:** items' `mutated_plant.gd` grows a real `Ladder` (after its grow animation) instead
of steps; its test `test_water_grows_plant_ladder` now checks for `Vine/Ladder`.
**For level_gen / room makers:** drop `systems/player/ladder.tscn` into a room, set `height`, put its back
against a wall or ledge (it faces +Z). Nothing networked: every PC has the same ladder.
**OPEN / tune in playtests:** how strong the glide, hops, climb speed and slide grip feel (all in
`player_tuning.tres`); Octo climbs anything solid, including crates and other players; no climbing animations
or sounds yet; the slug leaves no slime trail.
