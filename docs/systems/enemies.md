# enemies

Folder: `res://systems/enemies/` · Autoload: `Enemies` · Size: L · Phase 1b (Zoology), Phase 2 (Botany, Robotics)

## Purpose
Every regular enemy, built from **shared AI states** (idle, patrol, chase, attack, flee) plus small
**per-enemy behaviour nodes** (a kangaroo's jump, a bat's swoop). Also the per-floor **spawner** that
spends a difficulty budget on the department's enemy pool, and navigation across generated rooms.

**Not responsible for:** bosses (bosses builds on this), loot (loot listens to `enemy_killed`), health (damage), difficulty numbers (game_flow's `RunDifficulty`).

## Public API
```gdscript
# Autoload Enemies
func spawn(enemy_id: StringName, xform: Transform3D) -> Enemy        # host
func get_alive() -> Array[Enemy]
func despawn_all() -> void                                          # host, between floors
func get_spawner() -> EnemySpawner                                   # NEW 2026-10-19
func bake_navigation(root: Node3D) -> NavigationRegion3D             # NEW 2026-10-19, host: navmesh for everything solid under root
func spawn_floor(floor_in_department: int, department: DepartmentData, run_seed: int, markers: Array[RoomMarker]) -> Array[Enemy]   # NEW, host
static func plan_spawns(pool: Array[WeightedIdData], floor_in_department: int, budget: int, rng: RandomNumberGenerator) -> Array[StringName]   # NEW
static func pool_for(department: DepartmentData) -> Array[WeightedIdData]   # NEW (STUB: empty pool = every enemy)

class_name EnemySpawner extends Node3D       # NEW 2026-10-19: MultiplayerSpawner holder (the autoload has one; tests make their own)
func spawn(enemy_id: StringName, xform: Transform3D, health_multiplier: float = 1.0, rng_seed: int = 0) -> Enemy
func get_alive() -> Array[Enemy]
func despawn_all() -> void

class_name Enemy extends CharacterBody3D
var data: EnemyData
func get_health() -> HealthComponent
func get_target() -> PlayerCharacter        # null if none
func set_target(player: PlayerCharacter) -> void
func get_state() -> StringName                 # NEW 2026-10-19
func is_dead() -> bool                        # NEW
func has_state(state: StringName) -> bool     # NEW
func pursuit_state() -> StringName            # NEW: "swarm" if it has it, else "chase"
func update_target() -> PlayerCharacter       # NEW, host: from Perception (remembers a lost player 3 s)
func move_towards(point: Vector3, speed_scale: float, delta: float) -> void   # NEW, host: navmesh path or straight
func stop() -> void                           # NEW
func face(point: Vector3, delta: float) -> void   # NEW
func try_attack() -> bool                     # NEW, host: hit the target (cooldown, range)
 var flying: bool, hover_height: float, attack_knockback: float, hurtbox_radius: float, hurtbox_height: float, start_state: StringName   # NEW
var altitude_override: float                  # NEW: flying, e.g. a bat's dive
var rng: RandomNumberGenerator                # NEW: SeededRng(run_seed, &"enemy_ai", net id)
static func of(node: Node) -> Enemy

class_name EnemyState extends Node           # building block; children of the StateMachine node
func can_enter(enemy: Enemy) -> bool
func enter(enemy: Enemy) -> void
func exit(enemy: Enemy) -> void
func physics_update(enemy: Enemy, delta: float) -> StringName      # name of the next state, or &"" to stay

class_name EnemyBehaviour extends Node       # small per-enemy extras, e.g. JumpAttackBehaviour
func on_state_changed(enemy: Enemy, state: StringName) -> void
func on_attack(enemy: Enemy, info: DamageInfo) -> void   # NEW 2026-10-19, host: change the hit (more knockback...)

class_name Perception extends Node           # sight cone, hearing, nearest visible player
func get_visible_players() -> Array[PlayerCharacter]
func get_nearest_visible_player() -> PlayerCharacter   # NEW 2026-10-19
func is_valid_target(candidate: Variant) -> bool       # NEW: alive, not freed
static var players_invisible: bool                     # NEW: test scenes
```
Shared states in `systems/enemies/states/`: `idle`, `patrol`, `chase`, `attack_melee`,
`attack_ranged`, `flee`, `swarm` (flies/rats moving as a group). An enemy scene lists which states it uses.
DONE 2026-10-19: `idle`, `patrol`, `chase`, `swarm`, `attack_melee`, `flee` (`attack_ranged` waits for a ranged enemy,
Phase 2). Behaviours: `JumpAttackBehaviour` (kangaroo leap and big kick), `SwoopBehaviour` (bat dives to head height).
Sync: CHANGED to host -> everyone RPCs (~20/s, interpolated) instead of a MultiplayerSynchronizer. Dead enemies fall
over on every PC and are removed after 2 s. The four Zoology enemies (`content/enemies/`, scenes in
`systems/enemies/scenes/`): rat (15 hp, swarm, cost 1), kangaroo (60 hp, leap, cost 3, floor 2+), bat (20 hp, flies,
swoops, flees at 25%, cost 2), fly (5 hp, flying swarm, cost 1).

**Spawner** (host, on `floor_ready`): budget = `RunDifficulty.enemy_budget(floor_number, player_count)`;
picks from `DepartmentData.enemy_spawns` (weights) whose `min_floor` allows it, paying `spawn_cost`
until the budget is spent, at `Level.get_markers(&"enemy_spawn")`, never in the start room.
Health is multiplied by `RunDifficulty.enemy_health_multiplier(player_count)`.
RNG: `SeededRng.make(run_seed, &"enemy_spawns", floor_number)`.

**Navigation:** each room scene contains a baked `NavigationRegion3D`; when rooms are placed, regions
connect at doorways (edge connection). Enemies use `NavigationAgent3D`.
CHANGED 2026-10-19: no region in the room scenes: on `floor_ready` the host bakes one navigation mesh for the whole floor
(`bake_navigation`, from the WORLD colliders under the rooms), so doorways connect by themselves and room scenes need
no editing. Flying enemies (bats, flies) steer straight through the air. Without a navmesh enemies head straight
for their goal.

## EventBus
- Emits: `enemy_killed` (host).
- Listens: `floor_ready` (spawn), `floor_loading` (despawn), `player_died` (drop target).

## Data it owns and saves
Uses `EnemyData`. Saves nothing.

## Adding content
A new enemy using existing states is an `EnemyData` `.tres` + a scene that combines shared states.
**No code.** A unique trick is a new `EnemyBehaviour` (small code). Add it to a department's
`enemy_spawns` to make it appear.
Zoology (Phase 1): rats (swarm, weak), kangaroos (jump attack, knockback), bats (flying, swoop),
flies (swarm, annoying, attracted to Fly-mutated players). Botany: ent, flytrap (stationary), vines
(stationary grab), spore shooter (ranged). Robotics: roombas, turrets (stationary ranged), flock cameras
(alert others), drones (flying ranged) — Robotics enemies use loot tables with robot parts.

## Multiplayer
AI runs only on the host. Clients receive position, rotation and animation state through a
`MultiplayerSynchronizer` (~20/s, interpolated). Enemies are spawned through a `MultiplayerSpawner`.

## Dependencies and stubs
damage, net_core, level_gen (markers and nav; stub: a hand-made grey-box arena with markers and a nav region), player (targets).
Debug: registers the `enemy` spawner and `killall`.

## Test scene and GUT tests
Test scene: an arena with markers; buttons to spawn each enemy, toggle "players invisible", change player count for budget.
GUT tests: `test_state_machine_transitions`, `test_chase_when_player_visible`, `test_flee_at_low_health`,
`test_spawner_spends_budget`, `test_budget_scales_with_players` (1, 4, 8), `test_min_floor_respected`,
`test_same_seed_same_spawns`, `test_enemy_killed_emitted_with_killer`, `test_new_enemy_file_spawns_without_code`.
DONE 2026-10-19: `systems/enemies/test/enemies_test.tscn` (an arena with pillars and a back room through a doorway;
F1 rat, F2 kangaroo, F3 bat, F4 fly, F9 a floor's worth, [ ] players for F9, F7 players invisible, F8 kill all, F10
crowbar). GUT (`tests/unit/enemies/test_enemies.gd`, 15): all of the above plus `test_walls_block_sight`,
`test_attack_hurts_the_player`, `test_flying_enemies_hover`, `test_health_scaled_for_players`,
`test_navigation_goes_around_walls`, `test_enemies_move_the_same_on_host_and_client`.

## Acceptance criteria
- [ ] The 4 Zoology enemies work on 2 PCs with smooth movement for clients.
  *Rats and bats chased and hurt the host with matching positions on 2 game copies (2026-10-19); Steam not yet.*
- [ ] Enemies path between generated rooms through doorways. *Navmesh baked per floor; paths go around walls (GUT).*
- [x] More players → more and tougher enemies, from config. *(GUT)*
- [x] A new enemy made from existing states needs no code. *(GUT)*

## Open design questions
- DEFAULT: enemies don't steal from carts (field exists for later).
- DEFAULT: enemies don't respawn on a floor.
- Do enemies notice voice chat (loud talkers attract enemies)? Fun, later idea.

## Changelog
- 2026-10-07: spec created.
- 2026-10-19: built (Phase 1b). Changes marked above (runtime navigation, RPC syncing, the NEW functions). Content:
  `enemy_rat`, `enemy_kangaroo`, `enemy_bat`, `enemy_fly`.
- 2026-10-23 (bosses branch): NEW `Enemy.died(info)` signal (every PC) and `Enemy.setup_from(content, ...)` (a Boss builds
  its numbers from BossData); `EnemySpawner.spawn` takes BossData ids too, and when the connection changes (you start
  hosting or join after playing alone) the host re-spawns its enemies for everyone and a client drops its own copies.
- 2026-10-20 (Zachary: the bat flew away after one hit and never came back): enemies flee only once (NEW
  `Enemy.has_fled`), for 2.5 s (was 4), then go straight back after the player they ran from.

## HANDOFF
**Built (2026-10-19):** `Enemy`, `EnemyState` + 6 shared states, `EnemyBehaviour` + `JumpAttackBehaviour` and
`SwoopBehaviour`, `Perception`, `EnemySpawner`, the `Enemies` autoload (floor spawning on `floor_ready`, navmesh baking,
`spawn enemy_<name>`, `killall`), grey-box scenes and content for the 4 Zoology enemies, the test arena and 15 GUT
tests. Checked: a generated floor got its navmesh and 5 enemies; on 2 game copies a rat and a bat chased and bit the
host with the same positions on both PCs.

**Foundation / project.godot changes:** autoload line `Enemies` (after Items). No foundation changes; no new EventBus
signals (emits `enemy_killed` on the host).

**STUBS:** a department without `enemy_spawns` (today's placeholder) uses every enemy; flies aren't drawn to
Fly-mutated players yet (upgrades); no attack or death sounds (audio); no ranged attack state (Phase 2).

**For the next systems:**
- **bosses:** a boss can be an Enemy scene with its own states; spawn minions with `Enemies.spawn`.
- **loot:** listen to `enemy_killed(enemy_id, position, killer)` and roll `EnemyData.loot_id`.
- **death_respawn:** enemies already ignore dead players (`HealthComponent.is_dead()`).
- **level_gen:** add more `enemy_spawn` markers to rooms; the lift room never gets enemies.
