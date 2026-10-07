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

class_name PlayerMovement extends Node              # child "Movement" of the player
signal mode_changed(mode: StringName)
func set_modifier(source_id: StringName, effect: MovementEffectData) -> void
func remove_modifier(source_id: StringName) -> void
func get_active_mode() -> StringName
func get_height() -> float
func is_crouching() -> bool
func is_grounded() -> bool
func apply_knockback(impulse: Vector3) -> void      # host calls; forwarded to owner

class_name MovementMode extends RefCounted          # base for building blocks
func enter(body: PlayerCharacter) -> void
func exit(body: PlayerCharacter) -> void
func physics_update(body: PlayerCharacter, input_dir: Vector2, delta: float) -> void

class_name PlayerSpawner extends Node               # put one in every playable scene
func spawn_all(spawn_points: Array[Node3D]) -> void # host
func spawn_player(player_id: int, xform: Transform3D) -> PlayerCharacter   # host
func despawn_player(player_id: int) -> void         # host
```
Movement modifiers combine: multipliers multiply, `can_jump` is false if any modifier says false,
the mode with the highest `mode_priority` wins. Mode name `wall_climb` loads
`systems/player/movement_modes/wall_climb_mode.gd` (file name = mode name + `_mode.gd`), so a new
mode is one new file and no list to edit. Launch modes: `walk` (default), `wall_climb` (Octo),
`slide` (Slug), `hop` (Frog), `hover` (Fly, short glides).

Height: Giraffe's `height_multiplier` makes the body taller; door frames block standing, so the player must crouch (crouch height also scales).

## EventBus
- Emits: `player_spawned`, `local_player_spawned`.
- Listens: `player_left` (despawn), `settings_changed` (sensitivity, FOV, reduce motion).

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

## Acceptance criteria
- [ ] Walk, sprint, jump, crouch feel responsive; 2+ local players see each other move smoothly.
- [ ] A MovementEffectData with `wall_climb` lets you climb the test wall, with no code change.
- [ ] Giraffe height test: can't walk through a low door standing, can while crouched.
- [ ] Nothing assumes 4 players; 8 local bodies can spawn.

## Open design questions
- DEFAULT: client-owned movement (feels good, easy). Cheating is possible but this is a co-op game among friends. **Zachary to confirm.**
- How strong should Frog's hop and Fly's hover be? Tune in playtests.

## Changelog
- 2026-10-07: spec created.
