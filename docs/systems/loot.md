# loot

Folder: `res://systems/loot/` · Autoload: `Loot` · Size: M · Phase 1b

## Purpose
Decides and spawns what drops when monsters die (and from crates): plain gems (money), glowing gems
(holding a mutation), meat, robot parts (holding a cybernetic) and items. The **host** rolls everything
with the floor's seed. Handles the glow chance with a **pity rule**, picks which mutation or cybernetic
a drop holds, and merges plain gems when there are too many loose ones.

**Not responsible for:** spending gems (vendors), eating gems (upgrades), physics (physics_props).

## Public API
```gdscript
class_name LootDrop extends RefCounted
var prop_id: StringName
var item_id: StringName
var upgrade_id: StringName          # set for glowing gems and robot parts
var count: int

# Autoload Loot
func roll(loot_id: StringName, rng: RandomNumberGenerator) -> Array[LootDrop]   # pure: no spawning (testable)
func roll_and_spawn(loot_id: StringName, at: Vector3, source_id: StringName) -> Array[NetProp]   # host; CHANGED 2026-10-23: returns what it spawned
func roll_glow(rng: RandomNumberGenerator) -> bool          # uses and updates the pity counter
func pick_upgrade(type_key: StringName, rng: RandomNumberGenerator) -> StringName   # &"mutation" or &"cybernetic"; filtered by current department, weighted by drop_weight
func get_glow_chance() -> float                             # current chance including pity
func reset_pity() -> void
func merge_gems(max_loose: int = -1) -> int       # NEW 2026-10-23, host: returns how many gems went away
static func gems_for_value(value: int) -> Array[StringName]   # NEW: plain gem props adding up to a value, biggest first
func use_department(department: DepartmentData) -> void   # NEW: tests only (clear_department_override() undoes it)
```
- A drop of a prop whose PropData has `gem_value > 0` may become glowing: `roll_glow` → if true, it spawns
  `prop_gem_glowing` (any prop tagged `glowing_gem`) with `extra.upgrade_id = pick_upgrade(&"mutation")`.
- A drop of a prop tagged `robot_part` always gets `extra.upgrade_id = pick_upgrade(&"cybernetic")`.
- Outside Robotics, regular enemies also drop a robot part with chance `off_department_robot_part_chance` (default 0).
- RNG: `SeededRng.make(run_seed, &"loot", drop_counter)`; the counter increases with every roll on the floor.
- **Gem merging:** when loose plain gems exceed `max_loose_gems_per_floor`, the host merges groups of
  nearby resting plain gems into one higher-value gem prop (the lowest-value prop with enough
  `gem_value`). Value is never lost.

## EventBus
- Emits: `loot_dropped` (host).
- Listens: `enemy_killed` → `roll_and_spawn(enemy's loot_id or department default)`; `boss_defeated` →
  boss loot; `floor_ready` → reset drop counter (pity carries across floors in a run); `run_started` → reset pity.

## Data it owns and saves
Uses `LootTableData`; glow numbers from `Config.game` (`gem_glow_chance`, `gem_glow_pity_step`,
`gem_glow_chance_max`, `off_department_robot_part_chance`, `max_loose_gems_per_floor`). Saves nothing.

## Adding content
New loot tables are `.tres` files in `content/loot_tables/`; enemies, bosses and departments point to
them by id. New upgrades join the pools automatically. No code.

## Multiplayer
Host only. Clients just see the spawned props.

## Dependencies and stubs
physics_props (`Props.spawn_prop`), game_flow (current department and seed; stub with a fixed seed and
department). Debug: registers `gems <amount>` and `loot <loot_id>`.

## Test scene and GUT tests
Test scene: a button that "kills" a dummy rat 100 times and shows counts of each drop and glow rate.
GUT tests: `test_same_seed_same_drops`, `test_weights_respected_over_many_rolls`, `test_pity_raises_chance_until_glow`,
`test_chance_never_above_max`, `test_upgrade_pick_respects_department_filter`, `test_robot_part_always_has_cybernetic`,
`test_merge_keeps_total_value`, `test_new_mutation_joins_pool`.

## Acceptance criteria
- [ ] Killing a rat drops gems/meat per its table, identical for everyone.
- [ ] Glowing chance and pity come from GameConfig; turning pity off works.
- [ ] Adding a mutation file makes it droppable with no code changes.

## Open design questions
- DEFAULT: pity on: +3% per non-glowing gem, capped at 60%, reset when one glows.
- DEFAULT: off-department robot parts off (0%), so Zoology-only runs have no cybernetics except the Phase 1 debug part. **Team to decide** (e.g. 2% "broken drone" drop).
- DEFAULT: plain gems never vanish; they merge instead.

## Changelog
- 2026-10-07: spec created.
- 2026-10-23: built (Phase 1b). Changes marked above. Content: `prop_gem` (1), `prop_gem_large` (5), `prop_gem_glowing`
  (tag `glowing_gem`, tinted with its mutation's `glow_color`), `prop_meat` (tag `meat`), scenes in `systems/loot/scenes/`;
  loot tables `loot_zoology_small` (rats, flies), `loot_zoology_medium` (bats, kangaroos), `loot_boss_giant_rat`; the
  four enemies and the Giant Rat point at them (`loot_id`). Nothing drops where there is no PropSpawner.
- 2026-10-24: playtest "only the rat dropped meat": the rolls were working, meat was just rare (rats and flies 1 kill in 6). Meat weight raised: `loot_zoology_small` 1 -> 2 (about 1 kill in 3), `loot_zoology_medium` 1.5 -> 2.5 (over half of kills). Test `test_every_enemy_drops_meat_often`.

## HANDOFF
**Built (2026-10-23):** `LootDrop`, the `Loot` autoload (rolls with `SeededRng(run_seed, &"loot", drop counter)`, glow
with pity from GameConfig, mutation / cybernetic picks filtered by department and weighted by `drop_weight`, robot parts
always hold a cybernetic, gem merging every 2 s past `max_loose_gems_per_floor`, console `gems` and `loot`), the props
and tables above, the test scene (`systems/loot/test/loot_test.tscn`) and 12 GUT tests (`tests/unit/loot/test_loot.gd`:
the spec's list plus `test_pity_can_be_turned_off`, `test_glowing_gem_holds_a_mutation`,
`test_killing_a_rat_spawns_its_drops`, `test_gems_for_value_adds_up`). Checked with 2 game copies: the same drops on
both PCs.

**Foundation / project.godot changes:** autoload line `Loot` (after Bosses). No new EventBus signals (emits
`loot_dropped`). Edited content: `loot_id` on the 4 enemies and the Giant Rat.

**Not yet:** glowing gems only appear once mutations exist (upgrades); no drop sounds (audio).

**For the next systems:** vendors take gems (`gem_value`) and give change with `gems_for_value`; death_respawn uses
`prop_meat` (tag `meat`); upgrades reads `extra.upgrade_id` on glowing gems.
- 2026-10-23 (Zachary, branch system/upgrade_machine): REMOVED glowing gems, the glow pity rule and robot-part drops (mutations
  come from DNA vials and the mutation machine, see upgrades). Gems are money only. `roll_glow`, `get_glow_chance`,
  `reset_pity` and `prop_gem_glowing` are gone (never merged); GameConfig `gem_glow_chance`, `gem_glow_pity_step`,
  `gem_glow_chance_max`, `off_department_robot_part_chance` are kept but `@deprecated` (not used). `pick_upgrade` stays:
  upgrades uses it to fill vials and drives. Tests for glow, pity and robot parts are gone.
