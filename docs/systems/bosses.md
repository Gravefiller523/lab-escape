# bosses

Folder: `res://systems/bosses/` · Size: M · Phase 1b (Giant Rat), Phase 2 (Mushroom Man, Robobrain)

## Purpose
The boss framework: a boss fight in an arena room, split into **phases** that change at health
thresholds, each with its own attacks and **minion** waves. Bosses reuse the enemy states and damage
system; this adds phases, named attacks, minions and arena rules (doors lock during the fight).

**Not responsible for:** loading the boss floor (game_flow + level_gen), loot (loot listens to `boss_defeated`), regular enemy AI (enemies).

## Public API
```gdscript
class_name Boss extends Enemy
signal phase_changed(phase_index: int)
var boss_data: BossData
func get_phase() -> int
func start_fight() -> void                  # host; the arena calls it when players enter
static func current() -> Boss                  # NEW 2026-10-23: the boss in the game, or null
func is_fighting() -> bool                      # NEW
func get_attack(attack_name: StringName) -> BossAttack   # NEW
func spawn_wave() -> Array[Enemy]               # NEW, host: one wave of this phase's minions
func fire_attack_projectile(attack: BossAttack, from: Vector3, shot_velocity: Vector3) -> void   # NEW 2026-11-12, host: one shot of an attack, on every PC
static func minions_for_players(base: int, player_count: int, config: GameConfig = null) -> int   # NEW
@export var boss_move_speed: float, attack_gap: float, boss_sight_range: float   # NEW: its numbers (BossData holds health)

class_name BossAttack extends Node          # building block; named child nodes of the boss scene
@export var attack_name: StringName         # matches BossPhaseData.attack_names
func can_start(boss: Boss) -> bool            # default: target within min_range..max_range
func start(boss: Boss, target: PlayerCharacter) -> void
func update(boss: Boss, delta: float) -> void  # NEW 2026-10-23, host: every frame while it runs; call finish()
func is_finished() -> bool
func play_effect(boss: Boss) -> void           # NEW, every PC: the wind-up everyone sees
func get_projectile() -> RangedAttackData      # NEW 2026-11-12: what it fires through Boss.fire_attack_projectile (null = nothing)
static func hit_players_near(boss, point, radius, damage, damage_type, knockback, lift, already_hit = [], status_id = &"") -> Array[int]   # NEW helper

class_name BossArena extends Node3D         # in the boss_arena room scene
signal fight_started()
signal fight_ended()
func lock_doors(locked: bool) -> void
func get_minion_spawn_points() -> Array[Node3D]
func is_locked() -> bool                         # NEW 2026-10-23
func clamp_inside(point: Vector3, margin: float) -> Vector3   # NEW: keeps the boss in its arena
static func current() -> BossArena

# NEW 2026-10-23: autoload Bosses (systems/bosses/bosses.gd, BossesService)
func spawn(boss_id: StringName, xform: Transform3D) -> Boss   # host
static func boss_for(department: DepartmentData) -> StringName   # its boss_id (STUB: the first boss)
func make_arena() -> BossArena                  # every PC, on boss floors
```
Shared attacks in `systems/bosses/attacks/`: `charge`, `slam`, `projectile_burst`, `laser_sweep`,
`summon_wave`, `rocket_volley`. DONE 2026-10-23: `charge` and `slam` (`projectile_burst`, `laser_sweep`,
`rocket_volley` come with Phase 2 bosses). CHANGED: minion waves come from the phase data (`minion_enemy_ids`,
`minions_per_wave`, `minion_wave_interval`; one wave when the phase starts), not a `summon_wave` attack. Minions per
wave x (1 + `boss_minions_per_extra_player` (0.5) per extra player).
NEW 2026-10-23, how a fight goes: the Bosses autoload turns the arena room into a `BossArena` at runtime (no change to
level_gen's room scene) and the host spawns the boss at `boss_spawn` (through the Enemies spawner: a Boss is an
Enemy). The fight starts when the first player walks into the arena; once every living player is in, red bars block
the doorways until the boss dies. Bosses use the shared `boss_fight` state (walk at the target between attacks, pick
a random ready attack from the current phase every `attack_gap` seconds). The boss never leaves its arena. A health
label floats over it. Beating it: `boss_defeated` on every PC (the cargo lift works again), its minions vanish. Boss health × `RunDifficulty.boss_health_multiplier(player_count)`;
minions per wave scale with player count too.

NEW 2026-11-12 (roadmap WP13), the Phase 2 attacks, all in `systems/bosses/attacks/`:
- `projectile_burst_attack.gd` (covers the planned `projectile_burst` and `rocket_volley`): stop, wind up, fire a fan of
  `shots_per_volley` projectiles `fan_degrees` wide at the target (360 = a ring all round). Its `projectile` is a
  RangedAttackData (the same resource enemies' ranged attacks use); that resource's `shots` is the number of volleys
  and `shot_interval` the pause between them. Lobbed shots (gravity_scale above 0) aim to land at the target's distance.
- `laser_sweep_attack.gd`: a thin aiming line for `windup` seconds, then a low beam (`beam_height` 0.45 m, under a
  jump) that the boss drags through `sweep_degrees` by turning its whole body, so the synced facing shows the same
  sweep on every PC. Hits each player at most once per sweep, never through a wall; jumping or standing on a crate dodges it.
- `slam_attack.gd` gained `status_id` (everyone it hits gets that status) and `puff_color` (a burst of that colour).
Bosses: **Mushroom Man** (`boss_mushroom_man`, Botany, 700 health, 3 phases: spore volley and spore slam with 2
zombies at the start; a spore ring and zombie waves under 60%; faster volleys under 25%) and **Robobrain**
(`boss_robobrain`, Robotics, 800 health, 3 phases: laser sweep, rocket volley and a stomp; drone waves under 60%;
faster laser and rockets under 30%). Both are grey boxes and fight in `room_arena_grey` until level_gen has arenas
per department.

## EventBus
- Emits: `boss_phase_changed`, `boss_defeated` (all).
- Listens: `boss_floor_started` (host: spawn the boss at `Level.get_markers(&"boss_spawn")`).

## Data it owns and saves
Uses `BossData` and `BossPhaseData`. Saves nothing.

## Adding content
A new boss made of existing attacks and enemy states: a `BossData` `.tres`, a boss scene, an arena
room (`RoomData` with `room_kind = "boss_arena"`) and the department's `boss_id`. **No code.** A unique
attack is a new `BossAttack` file (building block).
Giant Rat (Zoology): phase 1 charge + slam; phase 2 (50%) summons rat minions (`enemy_rat`) and charges faster.
DONE 2026-10-23: `content/bosses/boss_giant_rat.tres` (600 health), scene `systems/bosses/scenes/giant_rat.tscn`
(grey box): phase 1 `charge` + `slam`; phase 2 at 50%: `charge_fast` (same ChargeAttack, faster) + `slam`, 3 rats
when it starts and every 12 s.
Mushroom Man (Botany): spore projectiles, summons zombie minions. Robobrain (Robotics): laser sweep and rocket volley; drops robot parts.

## Multiplayer
Host only AI and phases; synced like enemies, plus `phase_index` and the arena door state.

## Dependencies and stubs
enemies, damage, level_gen (arena room). Stub: a hand-built arena scene.
Debug: `boss` (go to this department's boss floor) and the `boss` spawner.

## Test scene and GUT tests
Test scene: the Giant Rat arena with 1 to 4 test players (local instances) and a "damage boss 10%" button.
GUT tests: `test_phase_changes_at_threshold`, `test_phase_change_emitted_once`, `test_minions_spawn_per_wave`,
`test_health_scales_with_players`, `test_doors_lock_and_unlock`, `test_defeat_emits_boss_defeated`, `test_attack_found_by_name`.
DONE 2026-10-23: `systems/bosses/test/boss_test.tscn` (a 24 m arena with one doorway; F1 damage the boss 10%, F2 new boss,
F7 players invisible, F10 crowbar). GUT (`tests/unit/bosses/test_bosses.gd`, 9): all of the above plus
`test_boss_attacks_close_players`, `test_department_boss_or_the_first_one`.
NEW 2026-11-12 (roadmap WP13): `tests/unit/bosses/test_new_bosses.gd` (15): every department has its own boss and boss
floors, every phase of every boss only names attacks and minions that exist, all three departments turn up as boss
floors, the Mushroom Man's zombies and three phases, the spore volley (a lobbed fan), the spore ring (all round), a
boss spore hurts and gives spores, the spore slam's status, the laser's reach and height, the sweep hits once and
turns the boss, standing on a crate dodges it, rocket pairs fly straight, Robobrain's drones, and beating each boss.

## Acceptance criteria
- [ ] Giant Rat fight works start to finish on 2 PCs, with its phase 2 minions.
  *2 game copies (2026-10-23): same boss health, phase 2, locked doors and damage on both PCs; and a real boss floor
  spawned it, phase 2 brought 3 rats, beating it cleared them and freed the lift. Steam not yet.*
- [ ] A new boss built from existing attacks needs no code changes. *(the Giant Rat is data + a scene; not tested with a second boss yet)*

## Open design questions
- DEFAULT: players who die during a boss fight can be reprinted if a printer is in the arena (the boss arena room has one printer marker).

## Changelog
- 2026-11-12 (roadmap WP13): Mushroom Man and Robobrain. NEW attacks `projectile_burst_attack.gd` and `laser_sweep_attack.gd`; `slam_attack.gd` NEW `status_id` and `puff_color`. NEW `Boss.fire_attack_projectile`, `BossAttack.get_projectile`, and a trailing `status_id` on `BossAttack.hit_players_near` (old calls still work). Botany's and Robotics' `boss_id` now point at their own bosses and their `boss_floors` are on, so boss floors are rolled among all three departments.
- 2026-10-07: spec created.
- 2026-10-23: built (Phase 1b). Changes marked above. New GameConfig `boss_minions_per_extra_player` (0.5). Content:
  `boss_giant_rat`. game_flow's "Defeat the boss" button stub is gone.

- 2026-11-11 (roadmap WP1): a boss arena built by a mid-floor joiner asks the host for its state once the connection is open (`HostLink`).

## HANDOFF
**Built (2026-10-23):** `Boss` (phases, minion waves, health label), `BossAttack` + `charge` and `slam`, the
`boss_fight` state, `BossArena` (fight start, door bars, keeps the boss inside), the `Bosses` autoload (boss floors,
`spawn boss_<name>`), the Giant Rat (scene + content), the test arena and 9 GUT tests.

**Foundation / project.godot changes:** GameConfig `boss_minions_per_extra_player`. Autoload line `Bosses` (after
Enemies). No new EventBus signals (emits `boss_phase_changed`, `boss_defeated` on every PC).

**Other systems touched (this branch):** enemies (NEW `Enemy.died` signal, `Enemy.setup_from`; `EnemySpawner` spawns
BossData too and re-spawns its enemies when you start hosting or join, like PropSpawner), game_flow (GameWorld's boss
button stub removed).

**STUBS:** a department without `boss_id` gets the first boss (every department has its own since 2026-11-12); no boss music or sounds (audio); grey-box models; one shared grey arena for all three bosses.

**For the next systems:**
- **loot:** `boss_defeated` (and `enemy_killed` for the boss itself) -> roll `BossData.loot_id`.
- **death_respawn:** the arena has no printer marker yet; players who die in the fight wait for the reprint rules.
- **ui:** a proper boss health bar can read `Boss.current().get_health()` and `phase_changed`.
