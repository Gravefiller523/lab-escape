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

class_name Enemy extends CharacterBody3D
var data: EnemyData
func get_health() -> HealthComponent
func get_target() -> PlayerCharacter        # null if none
func set_target(player: PlayerCharacter) -> void
static func of(node: Node) -> Enemy

class_name EnemyState extends Node           # building block; children of the StateMachine node
func can_enter(enemy: Enemy) -> bool
func enter(enemy: Enemy) -> void
func exit(enemy: Enemy) -> void
func physics_update(enemy: Enemy, delta: float) -> StringName      # name of the next state, or &"" to stay

class_name EnemyBehaviour extends Node       # small per-enemy extras, e.g. JumpAttackBehaviour
func on_state_changed(enemy: Enemy, state: StringName) -> void

class_name Perception extends Node           # sight cone, hearing, nearest visible player
func get_visible_players() -> Array[PlayerCharacter]
```
Shared states in `systems/enemies/states/`: `idle`, `patrol`, `chase`, `attack_melee`,
`attack_ranged`, `flee`, `swarm` (flies/rats moving as a group). An enemy scene lists which states it uses.

**Spawner** (host, on `floor_ready`): budget = `RunDifficulty.enemy_budget(floor_number, player_count)`;
picks from `DepartmentData.enemy_spawns` (weights) whose `min_floor` allows it, paying `spawn_cost`
until the budget is spent, at `Level.get_markers(&"enemy_spawn")`, never in the start room.
Health is multiplied by `RunDifficulty.enemy_health_multiplier(player_count)`.
RNG: `SeededRng.make(run_seed, &"enemy_spawns", floor_number)`.

**Navigation:** each room scene contains a baked `NavigationRegion3D`; when rooms are placed, regions
connect at doorways (edge connection). Enemies use `NavigationAgent3D`.

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

## Acceptance criteria
- [ ] The 4 Zoology enemies work on 2 PCs with smooth movement for clients.
- [ ] Enemies path between generated rooms through doorways.
- [ ] More players → more and tougher enemies, from config.
- [ ] A new enemy made from existing states needs no code.

## Open design questions
- DEFAULT: enemies don't steal from carts (field exists for later).
- DEFAULT: enemies don't respawn on a floor.
- Do enemies notice voice chat (loud talkers attract enemies)? Fun, later idea.

## Changelog
- 2026-10-07: spec created.
