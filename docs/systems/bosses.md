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

class_name BossAttack extends Node          # building block; named child nodes of the boss scene
@export var attack_name: StringName         # matches BossPhaseData.attack_names
func can_start(boss: Boss) -> bool
func start(boss: Boss, target: PlayerCharacter) -> void
func is_finished() -> bool

class_name BossArena extends Node3D         # in the boss_arena room scene
signal fight_started()
signal fight_ended()
func lock_doors(locked: bool) -> void
func get_minion_spawn_points() -> Array[Node3D]
```
Shared attacks in `systems/bosses/attacks/`: `charge`, `slam`, `projectile_burst`, `laser_sweep`,
`summon_wave`, `rocket_volley`. Boss health × `RunDifficulty.boss_health_multiplier(player_count)`;
minions per wave scale with player count too.

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

## Acceptance criteria
- [ ] Giant Rat fight works start to finish on 2 PCs, with its phase 2 minions.
- [ ] A new boss built from existing attacks needs no code changes.

## Open design questions
- DEFAULT: players who die during a boss fight can be reprinted if a printer is in the arena (the boss arena room has one printer marker).

## Changelog
- 2026-10-07: spec created.
