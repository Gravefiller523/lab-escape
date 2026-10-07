# cosmetics

Folder: `res://systems/cosmetics/` · Autoload: `Cosmetics` · Size: M · Phase 2

## Purpose
Hats, lab coats, glasses, gloves and shoes that only change how a player looks. Unlocked by playing,
saved on each player's own PC, chosen at the Break Room's jacket closet, and shown to everyone. Makes
cosmetics fit mutated bodies (giraffe variants) or hides slots that clash (Slug can't wear shoes).

**Not responsible for:** saving (save_load), the closet screen's look (ui), mutation visuals (upgrades).

## Public API
```gdscript
# Autoload Cosmetics
func get_unlocked() -> Array[StringName]
func is_unlocked(cosmetic_id: StringName) -> bool
func get_all_for_slot(slot: StringName) -> Array[CosmeticData]   # from ContentRegistry
func get_loadout(player_id: int) -> Dictionary                  # slot -> cosmetic id
func request_equip(cosmetic_id: StringName) -> void             # local; must be unlocked
func request_unequip(slot: StringName) -> void
func unlock(cosmetic_id: StringName) -> void                    # local; saves, emits cosmetic_unlocked
func check_unlocks() -> Array[StringName]                       # local; runs every UnlockRuleData, returns new unlocks

class_name CosmeticDresser extends Node    # child of the player body
func refresh() -> void                     # rebuilds visible cosmetics from loadout + hidden slots + mutation variants
```
Unlock rule kinds: `default` (no rule = unlocked from the start), `runs_completed`, `floors_reached`,
`boss_defeated` (boss_id), `achievement` (achievement_id). New kinds need a small code addition here.

Fitting: for each worn cosmetic, if the player has a mutation listed in `mutation_variants`, use that
scene instead; if any upgrade hides the slot (`Upgrades.get_hidden_cosmetic_slots`), don't show it.

## EventBus
- Emits: `cosmetics_changed` (all), `cosmetic_unlocked` (local).
- Listens: `run_ended` (check unlocks), `achievement_unlocked`, `upgrade_gained`/`upgrade_lost` (refresh), `player_spawned` (dress them).

## Data it owns and saves
Uses `CosmeticData`. Writes `unlocked_cosmetic_ids` and `loadout` in the save_load profile; writes
`cosmetic_loadout` in the PlayerRecord so everyone sees it.

## Adding content
A new cosmetic: model scene + `CosmeticData` `.tres` (slot, unlock rule, optional giraffe/slug variants). No code.

## Multiplayer
Each player sends their own loadout to the host when joining and when changing. The host checks the
ids exist (it trusts unlocks: cosmetics can't affect gameplay), stores it in the record, and syncs it.
Every PC dresses every player with `CosmeticDresser`.

## Dependencies and stubs
save_load (stub: in-memory profile), net_core, player (attach points), upgrades (hidden slots; stub returns none).
Debug: `unlock_cosmetics`.

## Test scene and GUT tests
Test scene: a mannequin player with every cosmetic, toggles for Giraffe and Slug mutations.
GUT tests: `test_default_cosmetics_unlocked`, `test_equip_locked_refused`, `test_unlock_rule_runs_completed`,
`test_boss_unlock_rule`, `test_hidden_slot_not_shown`, `test_mutation_variant_used`, `test_loadout_synced_to_all`,
`test_new_cosmetic_file_needs_no_code`.

## Acceptance criteria
- [ ] Pick a hat at the closet; everyone sees it; it's still on after restarting the game.
- [ ] Slug hides shoes; Giraffe uses the variant hat when one exists.
- [ ] Cosmetics never change any gameplay number (no stat fields exist on CosmeticData).

## Open design questions
- What unlocks each cosmetic? DEFAULT: a starter set unlocked, some by runs completed (1, 5, 10),
  one per boss beaten, some from achievements. **Team to decide the list.**

## Changelog
- 2026-10-07: spec created.
