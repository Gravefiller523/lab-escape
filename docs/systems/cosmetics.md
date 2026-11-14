# cosmetics

Folder: `res://systems/cosmetics/` · Autoload: `Cosmetics` · Size: M · Phase 2

## Purpose
Hats, lab coats, glasses, gloves and shoes that only change how a player looks. Unlocked by playing,
saved on each player's own PC, chosen at the Break Room's jacket closet, and shown to everyone. Makes
cosmetics fit mutated bodies (giraffe variants) or hides slots that clash (Slug can't wear shoes).

**Not responsible for:** saving (save_load), mutation visuals (upgrades). CHANGED 2026-11-13: the closet screen
lives here (`systems/cosmetics/closet_screen.tscn`), built from ui's `HudStyle`, like the other systems' screens.

## Public API
```gdscript
# Autoload Cosmetics (class CosmeticsService)
const SLOTS: Array[StringName]                                   # hat, glasses, coat, gloves, shoes
const SCREEN_CLOSET: StringName = &"closet"                      # registered with UI
func open_closet() -> void                                       # NEW 2026-11-13; local: shows the closet screen
func rule_met(rule: UnlockRuleData) -> bool                      # NEW 2026-11-13; is this rule met by your profile?
static func describe_unlock(data: CosmeticData) -> String        # NEW 2026-11-13; how to get it (its description)
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
func get_shown() -> Dictionary[StringName, Node3D]   # NEW 2026-11-13; the models on the body now, by slot
static func model_for(data: CosmeticData, upgrade_ids: Array[StringName]) -> PackedScene   # NEW 2026-11-13

class_name ClosetScreen extends Control    # NEW 2026-11-13; the closet screen (tests drive it with these)
func show_slot(slot: StringName) -> void
func pick(cosmetic_id: StringName) -> void
func press_wear() -> void                  # wears the picked item, or takes it off if worn
```
Slots sit on these player attach points: hat on `head`, glasses on `face`, coat and gloves on `body`, shoes on `feet`.
Your own cosmetics are hidden from you, like the rest of your body; the closet's turning preview shows them.
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
save_load (real: `SaveSystem` profile), net_core, player (attach points), upgrades (hidden slots, mutation ids),
achievements (`Achievements.is_unlocked` for achievement rules), ui (`UI.register_screen`, `HudStyle`),
break_room (its closet calls `open_closet()`). No stubs left. Debug: `unlock_cosmetics`.

## Test scene and GUT tests
Test scene: `systems/cosmetics/test/closet_test.tscn` (F6). The closet opens at once, with a profile in a test
folder. F1 unlocks everything, F2 toggles Slug (no shoes), F3 toggles Giraffe, C reopens the closet.
GUT tests (`tests/unit/cosmetics/test_cosmetics.gd`): `test_starter_set_and_unlocks_follow_decision_d6`,
`test_default_cosmetics_unlocked`, `test_equip_locked_refused`, `test_one_item_per_slot`,
`test_unlock_rule_runs_completed`, `test_boss_unlock_rule`, `test_achievement_unlock_rule`,
`test_unlocks_and_outfit_survive_a_restart`, `test_dresser_puts_worn_cosmetics_on_the_body`,
`test_hidden_slot_not_shown`, `test_mutation_variant_used`, `test_new_cosmetic_file_needs_no_code`,
`test_closet_tries_on_and_wears`. Planned `test_loadout_synced_to_all` became a check that your outfit reaches
your PlayerRecord (in `test_equip_locked_refused`); the record reaching everyone is net_core's record syncing, which every record field uses.
Break Room: `test_closet_opens_for_whoever_used_it`.

## Acceptance criteria
- [ ] Pick a hat at the closet; everyone sees it; it's still on after restarting the game. *(Closet, record and
  restart covered by GUT; "everyone sees it" still needs 2 game windows.)*
- [x] Slug hides shoes; Giraffe uses the variant hat when one exists. *(No variant models exist yet: every
  cosmetic fits the grey-box body. The swap is tested with an in-memory one.)*
- [x] Cosmetics never change any gameplay number (no stat fields exist on CosmeticData; tested).

## Open design questions
- ~~What unlocks each cosmetic?~~ Decided (D6, 2026-11-11): 6 starter items, 3 for runs escaped (1, 3, 10),
  1 per boss beaten, 2 from achievements. 14 items: see `content/cosmetics/`.

## Changelog
- 2026-10-07: spec created.
- 2026-11-13 (roadmap WP17, closet mock-up approved by Zachary): built. The `Cosmetics` autoload, `CosmeticDresser`,
  the closet screen (`ClosetScreen`, slots on the left, items in the middle, a turning preview on the right) and
  14 grey-box cosmetics following D6. "Runs completed" counts escapes (lifetime stat `runs_escaped`). NEW API:
  `open_closet`, `rule_met`, `describe_unlock`, `SLOTS`, `SCREEN_CLOSET`, `CosmeticDresser.get_shown`/`model_for`,
  `ClosetScreen`. The closet screen lives in this system, not ui. The saved outfit is sent to the host when your
  body spawns and is only written to disk when you change it.

## HANDOFF
**Done (WP17, 2026-11-13):** everything in the Public API. Unlocks are checked when the game starts, when a run
ends, when a boss is beaten and when an achievement unlocks; a toast says "New in the jacket closet: ...".
**Not yet:** real models (grey boxes now, roadmap section d) and Giraffe variants; a 2-window check that others
see your outfit; achievement-based cosmetics on Steam need decision D8 like the achievements themselves.
- 2026-11-14 (art rollout): the closet's turning stand-in uses the player scene's body model when it has one (the scientist), not a grey capsule.
- 2026-11-14 (art rollout, Zachary asked): a worn coat replaces the body's white lab coat. `CosmeticDresser.refresh` calls `PlayerCharacter.set_default_coat_shown(not coat_worn)`; the closet preview hides its stand-in's white coat the same way. Test: `test_a_closet_coat_replaces_the_white_lab_coat`.
- 2026-11-14 (art rollout): all 14 cosmetics have finished models (`assets/models/shared/cosmetic_<name>.mesh`, the brain jar also `cosmetic_hat_brain_jar_glass`), made to fit the scientist; each scene is one `Model` node (and `Glass` for the brain jar). The closet's "Lab coat" is now a closed, buttoned lab coat, so it looks different from the body's open white coat.
