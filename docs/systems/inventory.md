# inventory

Folder: `res://systems/inventory/` · Size: M · Phase 1b

## Purpose
Each player's inventory slots for **weapons, tools and consumables only** (everything else is carried
by hand). Players start with fists plus `Config.game.base_inventory_slots` empty slots (1). Upgrades
can add slots. Handles switching the active slot and removing everything on death.

**Not responsible for:** what items do (items), spawning item pickups in the world (items via physics_props), the inventory bar's look (ui).

## Public API
```gdscript
class_name InventorySlot extends RefCounted
var item_id: StringName
var uses_left: int                                 # -1 = unlimited
var count: int                                     # NEW 2026-10-19: how many are stacked (ItemData.max_stack)

class_name InventoryComponent extends Node         # child "Inventory" of the player
signal changed()
signal active_slot_changed(index: int)             # CHANGED 2026-10-19: the selected slot (0 and up; fists = is_using_fists())
signal item_dropped(slot: InventorySlot, at: Transform3D)   # NEW 2026-10-19, host: an item left into the world
func get_slot_count() -> int
func get_slot(index: int) -> InventorySlot         # null if empty
func get_active_index() -> int                     # CHANGED 2026-10-19: the selected slot, even if empty or holstered
func is_using_fists() -> bool                      # NEW 2026-10-19: holstered, or the selected slot is empty
func is_holstered() -> bool                        # NEW 2026-10-19
func can_add(item_id: StringName) -> bool          # NEW 2026-10-19: fits without swapping
func get_active_item_id() -> StringName            # Config.game.unarmed_item_id when empty
func has_free_slot() -> bool
func find_item(item_id: StringName) -> int         # -1 if not held
func request_select(index: int) -> void            # local; predicted, confirmed by host
func request_holster_toggle() -> void              # NEW 2026-10-19: Alt
func request_drop() -> void                        # NEW 2026-10-19: Q (when not holding a prop)
# Host only:
func add_item(item_id: StringName, uses_left: int = -1) -> bool   # false if full (stacks first)
func pick_up(item_id: StringName, uses_left: int = -1) -> bool    # NEW 2026-10-19: add, or swap with the selected item when full
func remove_item(index: int) -> InventorySlot
func spend_use(index: int) -> void                 # removes the item at 0 uses
func set_bonus_slots(source_id: StringName, count: int) -> void   # upgrades' SlotEffectData
func clear_bonus_slots(source_id: StringName) -> void
func take_all() -> Array[InventorySlot]            # empties every slot (death_respawn spawns pickups)
static func of(node: Node) -> InventoryComponent
```
NEW 2026-10-19 (Zachary): **2 slots** to start (`base_inventory_slots`); an empty slot means your **fists** are out.
**Alt** holsters the item (fists out; Alt again takes it back out; picking a slot also takes it out). Keys 1-9 pick a
slot, the mouse wheel cycles, **Q** drops the selected item (only when you aren't holding a prop; one at a time off a
stack). Items **stack** up to `ItemData.max_stack` (1 = no stacking; drinks and weapons are 1). **Picking up with every
slot full swaps** the new item into the selected slot and drops the old one in front of you. Dropped items call
`Props.spawn_item` when the item has a `world_scene` (items system), and `item_dropped` fires on the host.
CHANGED 2026-10-19: items in bonus slots that are removed are dropped at once.
The autoload `Inventory` (`systems/inventory/inventory.gd`, `InventoryService`) gives every player body its
"Inventory" child when it spawns; `Inventory.get_local()` is your own. Console: `give <item_id>`, `slots <extra>`, `inv`.
OLD TEXT: If bonus slots are removed while full, the extra items are returned by the next `take_all`-style call and dropped by upgrades (see upgrades spec).

## EventBus
- Emits: `inventory_changed(player_id)` (all).
- Listens: none.

## Data it owns and saves
The slot contents for the current run. Saves nothing (runs start fresh).

## Adding content
None: any ItemData can sit in a slot.

## Multiplayer
- Host owns contents. Synced to all (the owner needs it for the HUD and view model; others to show the held item).
- Selecting a slot is predicted locally (instant view-model swap) and confirmed by the host.
- Slot count follows base + bonuses; never a fixed number.

## Dependencies and stubs
player (attach to body), net_core. Stub: a bare node with an InventoryComponent and a fake player id.

## Test scene and GUT tests
Test scene: one player, keys to add the crowbar, add a bonus slot, remove it, drop all.
DONE 2026-10-19: `systems/inventory/test/inventory_test.tscn` (F1 crowbar, F2 energy drink, F3 bolt (stacks 3), F4 +1 slot,
F7 remove extra slots, F8 empty all; a slot bar at the bottom). GUT (`tests/unit/inventory/test_inventory.gd`, 14): the
ones below plus `test_items_stack_up_to_max_stack`, `test_full_inventory_swaps_with_the_selected_item`,
`test_pick_up_with_room_just_adds`, `test_holster_puts_fists_out_and_back`, `test_drop_removes_one_and_tells_listeners`,
`test_inventory_changed_event`, `test_contents_match_on_host_and_client`.
GUT tests: `test_starts_with_base_slots`, `test_add_until_full`, `test_bonus_slots_add_and_remove`,
`test_spend_use_removes_at_zero`, `test_take_all_empties`, `test_active_item_is_fists_when_empty`,
`test_select_out_of_range_ignored`.

## Acceptance criteria
- [ ] Start with fists + 2 slots (CHANGED); a SlotEffectData upgrade adds a slot with no code change.
  *2 slots and bonus slots work (GUT); upgrades will call set_bonus_slots.*
- [ ] Contents match on host and clients; HUD updates via `inventory_changed`.
  *Host and 1 client match (GUT and 2 game copies, 2026-10-19); the HUD bar comes with ui.*
- [ ] Death removes everything (with death_respawn).

## Open design questions
- DEFAULT: consumables (energy drink, coffee) take a slot, like tools.
- DECIDED 2026-10-19 (Zachary): drinks are 1 per slot, but items can stack (`max_stack`) for future items.
- DECIDED 2026-10-19 (Zachary): a full inventory swaps the selected item for the new one.

## Changelog
- 2026-10-07: spec created.
- 2026-10-19: built (Phase 1b) with Zachary's rules: 2 slots, fists in empty slots, Alt holster, stacking
  (`ItemData.max_stack`), swap when full. Changes marked above. Foundation: GameConfig `base_inventory_slots` 1 -> 2,
  InputActions `HOLSTER` (Alt), ItemData `max_stack`. project.godot: autoload `Inventory`.

## HANDOFF
**Built (2026-10-19):** `InventorySlot`, `InventoryComponent`, the `Inventory` autoload (gives bodies an inventory,
console `give` / `slots` / `inv`), the test scene and 14 GUT tests. Checked with 2 game copies: a client's pickups,
slot choice, holster and a full-inventory swap matched on both PCs.

**Foundation / project.godot changes:** GameConfig `base_inventory_slots` = 2 (was 1), InputActions `HOLSTER` (Alt),
ItemData `max_stack` (1). Autoload line `Inventory` (after Damage). No new EventBus signals (emits `inventory_changed`).

**For the next systems:**
- **items:** world pickups call `InventoryComponent.of(body).pick_up(item_id, uses_left)` on the host; implement
  `Props.spawn_item` (physics_props' stub) so dropped items appear; read `get_active_item_id()` (fists when empty or
  holstered) for the held model and attacks; `spend_use(get_active_index())` for drinks.
- **upgrades:** `set_bonus_slots(upgrade_id, count)` / `clear_bonus_slots(upgrade_id)` for SlotEffectData.
- **death_respawn:** `take_all()` on death, spawn the pickups where the player died.
- **ui:** the HUD inventory bar goes in the HUD's `InventorySlot` spot: one box per `get_slot_count()`, refreshed on `changed`.
