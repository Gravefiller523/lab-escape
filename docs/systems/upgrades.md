# upgrades

Folder: `res://systems/upgrades/` · Autoload: `Upgrades` · Size: L · Phase 1b (voice proof uses a slice of it in 1a)

## Purpose
Mutations and cybernetics, handled by **one shared system**. A glowing gem holds a mutation; a robot
part holds a cybernetic. Holding either and pressing **use** eats or installs it instantly. An upgrade
is a list of **effect pieces** (movement, voice, slots, stats, visual attachment, special behaviour)
that this system applies to the player. Upgrades are kept through death and reconnects (stored in the
player's record on the host), and follow stacking and clash rules.

**Not responsible for:** rolling which upgrade a gem holds (loot), spawning gems/parts (loot through
physics_props), movement code (player), voice processing (voice), slot logic (inventory).

## Public API
```gdscript
# Autoload Upgrades
func grant(player_id: int, upgrade_id: StringName) -> bool    # host; false if it did nothing
func remove(player_id: int, upgrade_id: StringName) -> void   # host (cheats, future cure items)
func get_upgrades(player_id: int) -> Array[StringName]        # repeated ids = stacks
func has_upgrade(player_id: int, upgrade_id: StringName) -> bool
func get_stack_count(player_id: int, upgrade_id: StringName) -> int
func get_hidden_cosmetic_slots(player_id: int) -> PackedStringArray   # cosmetics asks this
func request_consume(prop: NetProp) -> void                   # local; the use handler calls this
func preview_clash(player_id: int, upgrade_id: StringName) -> Array[StringName]   # upgrades it would replace (for the prompt)
func is_known(upgrade_id: StringName) -> bool    # NEW 2026-10-23: someone gained it this run (gems show its name)

class_name UpgradeCarrier extends Node     # child of glowing-gem and robot-part prop scenes
var upgrade_id: StringName                 # from NetProp.extra["upgrade_id"]
# NEW 2026-10-23: static func for_data(data: UpgradeEffectData) -> UpgradeEffect (UpgradeEffect, found by file name)
func get_upgrade() -> UpgradeData
static func of(node: Node) -> UpgradeCarrier

class_name UpgradeEffect extends RefCounted   # runtime building block, one per effect data class
func apply(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void
func remove(player: PlayerCharacter, data: UpgradeEffectData, source_id: StringName) -> void
```
**Effect pieces → runtime blocks** (found by file name, no list to edit):
`MovementEffectData` → `effects/movement_effect.gd` → `PlayerMovement.set_modifier`;
`VoiceEffectData` → `voice_effect.gd` → `Voice.set_voice_effect`;
`SlotEffectData` → `slot_effect.gd` → `InventoryComponent.set_bonus_slots` (host);
`StatEffectData` → `stat_effect.gd` → `StatsComponent.add_modifier`;
`VisualAttachmentEffectData` → `visual_attachment_effect.gd` → adds the scene at `get_attach_point()`;
`BehaviourEffectData` → `behaviour_effect.gd` → adds `behaviour_scene` under the player.
`source_id` is `"<upgrade_id>#<stack number>"` so each stack can be removed separately.

**Rules (defaults, all marked as open questions below):**
- **Stacking:** `UNIQUE` upgrades do nothing the second time (the gem is still eaten); `STACKS`
  upgrades add their effects again up to `max_stacks`.
- **Clashes:** if the new upgrade shares a `clash_tags` entry with one you have, the old one is
  **replaced**. The prompt warns: "Eat (replaces Octo)". Octo and Frog both use `legs`.
- **Removal:** only via cheats or replacement for now.
- Losing bonus slots that hold items drops those items in front of the player.

## EventBus
- Emits: `upgrade_gained`, `upgrade_lost` (all).
- Listens: `player_spawned` (re-apply everything from the record: after reprint and reconnect), `run_ended` (clear).

## Data it owns and saves
Uses `MutationData`, `CyberneticData`. Writes `upgrade_ids` in `PlayerRecord` (net_core). Saves nothing to disk.

## Adding content
A new mutation or cybernetic is one `.tres` in `content/mutations/` or `content/cybernetics/` made of
existing effect pieces. **No code.** A brand-new *kind* of effect piece (rare) is a new data class in
`core/data/upgrades/effects/` plus a matching `systems/upgrades/effects/<name>.gd`.

Launch examples: Fly (voice pitch 1.5 + "buzz", wings at back, hover mode, behaviour "attracted_to_trash"),
Octo (wall_climb mode, can_jump false, clash "legs"), Slug (slide mode, hides "shoes", clash "legs"),
Giraffe (height 1.6, long-neck attachment; hats switch to their giraffe variant if they have one), Frog (hop mode, jump 1.8, clash "legs").

## Multiplayer
- Consume: client sends `request_consume(prop)`; host checks the prop is held by that player and has an
  `UpgradeCarrier`, despawns it, updates the record, and tells all PCs to apply. Effects are applied
  on **every** PC (owner needs movement; everyone needs visuals and voice). Authoritative parts
  (slots, stats) only change on the host and sync through their components.
- Reconnect/reprint: record → `player_spawned` → re-apply in order.

## Dependencies and stubs
player, inventory, damage (stats), voice, physics_props (carrier props), net_core (records).
Stubs: a fake player with the components; a fake `Voice` that logs calls. Debug: registers `give <id> [player]` and spawners for `mutation`/`cybernetic` (spawns a carrier prop).

## Test scene and GUT tests
Test scene: one player, a table of glowing gems for each test mutation, plus one robot part (`prop_robot_part` holding `cybernetic_test_arm`).
GUT tests: `test_grant_applies_every_effect_piece`, `test_unique_does_not_stack`, `test_stacks_up_to_max`,
`test_clash_replaces_old`, `test_remove_reverts_effects`, `test_reapply_after_reprint_matches`,
`test_consume_requires_holding`, `test_robot_part_and_gem_use_same_path`,
`test_new_mutation_file_needs_no_code` (register a MutationData built from existing pieces and grant it).

## Acceptance criteria
- [ ] Eating a glowing gem and installing a robot part are the same interaction and both work on 2 PCs.
- [ ] Fly mutation changes movement, voice, looks and behaviour, from data alone.
- [ ] Upgrades survive death (reprint) and disconnect/reconnect.
- [ ] Adding a mutation made of existing pieces needs no code changes.

## Open design questions
- DEFAULT: gems can be passed around before eating (they're props).
- DEFAULT: a glowing gem shows its mutation by colour and a hover label ("Glowing gem: Fly?" with a question mark until someone has eaten that mutation this run). **Confirm with team.**
- DEFAULT: clashes replace; no way to remove a mutation yet.
- Should the same mutation stack (e.g. two Frogs = higher hops)? DEFAULT: launch mutations are UNIQUE.

## Changelog
- 2026-10-07: spec created.
- 2026-10-23: built (Phase 1b). Changes marked above. How it works: E while holding a prop with an `UpgradeCarrier`
  (use handler priority 70, above grabbing) -> `request_consume` -> the host checks you hold it, lets go, despawns it
  and `grant`s: the record's `upgrade_ids` is updated and every PC applies the effect pieces (`_gained_rpc`); slot
  pieces act on the host only. A new body (reconnect) gets everything from the record on `player_spawned`; a reprint
  keeps the same body so nothing is re-applied. `run_ended` removes everyone's upgrades. The prompt says "Eat glowing
  gem: ???" until someone has gained that mutation this run, then its name, plus "(replaces X)" for clashes; robot
  parts say "Install robot part". Console: `upgrade <id>`, `unupgrade <id>`, `spawn mutation_<name>` (a glowing gem
  holding it) / `spawn cybernetic_<name>` (a robot part). Content: `mutation_fly`, `mutation_frog`, `mutation_octo`,
  `mutation_giraffe`, `mutation_slug`, `cybernetic_test_arm` (drop_weight 0: debug only), `prop_robot_part` (scene in
  `systems/upgrades/carriers/`); body models in `systems/upgrades/visuals/`. loot's glowing gem got an UpgradeCarrier.
  player: `PlayerMovement.get_speed_multiplier()` also multiplies the `move_speed` stat (so the energy drink's speed
  boost works).
- 2026-10-24: playtest fix: the machine hopper also checks what is already in it every physics tick, so a vial carried into it and let go there goes in.
- 2026-10-24 (player): the movement modes `hover`, `hop`, `wall_climb` and `slide` now exist, so Fly, Frog, Octo and Slug move differently (no content changes needed).

## HANDOFF
**Built (2026-10-23):** the `Upgrades` autoload (`UpgradesService`), `UpgradeCarrier`, `UpgradeEffect` + six runtime pieces
(movement, voice, slot, stat, visual attachment, behaviour), the five launch mutations and the test arm, the test scene
(`systems/upgrades/test/upgrades_test.tscn`) and 15 GUT tests (`tests/unit/upgrades/test_upgrades.gd`: the spec's list plus
`test_fly_changes_voice_and_looks`, `test_stat_piece`, `test_new_body_gets_upgrades_from_the_record`,
`test_gem_name_unknown_until_eaten`, `test_run_end_clears_upgrades`, `test_energy_drink_speed_boost_makes_you_faster`).
Checked with 2 game copies: a client ate a Fly gem; both PCs showed it in the record, its floaty gravity and its wings.

**Foundation / project.godot changes:** autoload line `Upgrades` (after Death). No new EventBus signals (emits
`upgrade_gained`, `upgrade_lost`).

**Other systems touched (this branch):** player (`get_speed_multiplier` reads `move_speed`), loot (glowing gem scene has
an UpgradeCarrier), tests/unit/loot (its test cybernetic got its own id).

**STUBS / not yet:** the movement modes `hover`, `hop`, `wall_climb`, `slide` don't exist in the player system yet (bodies
walk; the speed, jump, gravity, height and can_jump numbers do work); Fly's "attracted to trash" behaviour and flies being
drawn to Fly players aren't made; no eating sound (audio); grey-box body models.
- 2026-10-23 (Zachary, branch system/upgrade_machine): CHANGED how upgrades are gained. No more eating glowing gems or
  installing robot parts: a **mutation machine** (`UpgradeMachine`, `upgrade_machine.tscn`, a booth made in code) spawns
  at one `upgrade_machine` marker per floor (picked with `SeededRng(run_seed, &"upgrade_machine_spot", floor)`, every PC
  places it, child "UpgradeMachine" of the marker). Load it with a **DNA vial** (`prop_dna_vial`, tag `dna_vial`, holds a
  mutation) or a **data drive** (`prop_data_drive`, tag `data_drive`, holds a cybernetic): drop it into the yellow hopper
  or press E at the machine while holding it (use priority 70). Several wait in line. Stand in the booth for
  `upgrade_machine_seconds` (1.5) and the first in line is granted to you; if you already have a UNIQUE one it stays
  loaded ("You already have X"). Vials / drives spawn on floor_ready (host, not boss floors, not in the lift room):
  `upgrade_carrier_tries` (3) tries at `prop_spawn` markers, each with `DepartmentData.upgrade_carrier_chance` (or
  GameConfig `upgrade_carrier_chance`, 0.2); `DepartmentData.upgrade_type` says mutation (Zoology, Botany) or cybernetic
  (Robotics); the upgrade is `Loot.pick_upgrade` (department filter, drop_weight). REMOVED (never merged):
  `request_consume`, eating, `prop_gem_glowing`, `prop_robot_part`. NEW: `carrier_prop_for()`, `place_machine()`,
  `spawn_floor_carriers()`, console `machine`; `spawn mutation_<name>` now makes a DNA vial, `spawn cybernetic_<name>` a
  data drive. Tests: `test_machine_applies_the_loaded_mutation_when_you_step_in`,
  `test_vial_dropped_in_the_hopper_loads_the_machine`, `test_e_at_the_machine_while_holding_a_vial_puts_it_in`,
  `test_machine_keeps_a_unique_mutation_you_already_have`, `test_data_drive_gives_a_cybernetic_the_same_way`,
  `test_carrier_prop_matches_the_kind_of_upgrade` (the two eating tests are gone). Foundation: GameConfig
  `upgrade_machine_seconds`, `upgrade_carrier_tries`, `upgrade_carrier_chance`; DepartmentData `upgrade_type`,
  `upgrade_carrier_chance`. level_gen: `upgrade_machine` markers in `room_hall_grey` and `room_corridor_grey`.
