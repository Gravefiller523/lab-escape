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

class_name InventoryComponent extends Node         # child "Inventory" of the player
signal changed()
signal active_slot_changed(index: int)             # -1 = fists (no slot selected or empty)
func get_slot_count() -> int
func get_slot(index: int) -> InventorySlot         # null if empty
func get_active_index() -> int
func get_active_item_id() -> StringName            # Config.game.unarmed_item_id when empty
func has_free_slot() -> bool
func find_item(item_id: StringName) -> int         # -1 if not held
func request_select(index: int) -> void            # local; predicted, confirmed by host
# Host only:
func add_item(item_id: StringName, uses_left: int = -1) -> bool   # false if full
func remove_item(index: int) -> InventorySlot
func spend_use(index: int) -> void                 # removes the item at 0 uses
func set_bonus_slots(source_id: StringName, count: int) -> void   # upgrades' SlotEffectData
func clear_bonus_slots(source_id: StringName) -> void
func take_all() -> Array[InventorySlot]            # empties every slot (death_respawn spawns pickups)
static func of(node: Node) -> InventoryComponent
```
If bonus slots are removed while full, the extra items are returned by the next `take_all`-style call and dropped by upgrades (see upgrades spec).

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
GUT tests: `test_starts_with_base_slots`, `test_add_until_full`, `test_bonus_slots_add_and_remove`,
`test_spend_use_removes_at_zero`, `test_take_all_empties`, `test_active_item_is_fists_when_empty`,
`test_select_out_of_range_ignored`.

## Acceptance criteria
- [ ] Start with fists + 1 slot; a SlotEffectData upgrade adds a slot with no code change.
- [ ] Contents match on host and clients; HUD updates via `inventory_changed`.
- [ ] Death removes everything (with death_respawn).

## Open design questions
- DEFAULT: consumables (energy drink, coffee) take a slot, like tools.
- DEFAULT: no stacking: two energy drinks need two slots.

## Changelog
- 2026-10-07: spec created.
