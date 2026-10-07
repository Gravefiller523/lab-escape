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

class_name UpgradeCarrier extends Node     # child of glowing-gem and robot-part prop scenes
var upgrade_id: StringName                 # from NetProp.extra["upgrade_id"]
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
