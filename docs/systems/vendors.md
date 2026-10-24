# vendors

Folder: `res://systems/vendors/` · Size: M · Phase 1b

## Purpose
Vending machines and the Supply Room counter. Players drop or throw **physical gems** into the coin
slot; each gem's value is credited to **the player who last held it**. That player can buy an item
once their credit covers the price. Vendors keep no credit: after a purchase, extra value pops back out
as gems, and a refund lever spits out everything inserted. Vendors sell **items only**.

**Not responsible for:** gem drops (loot), item behaviour (items), where vendors go (level_gen markers).

## Public API
```gdscript
class_name VendorOffer extends RefCounted
var item_id: StringName
var price: int
var remaining: int                       # -1 = unlimited

class_name Vendor extends Node3D         # scenes: vending_machine.tscn, supply_counter.tscn
signal credit_changed(player_id: int, credit: int)
signal offers_changed()
@export var stock_id: StringName = &""   # empty = current department's stock_id
func get_offers() -> Array[VendorOffer]
func get_credit(player_id: int) -> int
func request_buy(offer_index: int) -> void   # local; the button Interactable calls it
func request_refund() -> void                # local; the lever (hold 1 s)
# NEW 2026-10-23, host:
func roll_offers() -> void
func add_credit(player_id: int, value: int) -> void   # 0 = nobody
func buy(player_id: int, offer_index: int) -> bool
func refund_all() -> void
func get_stock() -> VendorStockData
func use_seed(run_seed: int) -> void        # tests only
@export var vendor_index: int, screen_title: String   # NEW
const NOBODY: int = 0

# NEW 2026-10-23: autoload Vendors (systems/vendors/vendors.gd, VendorsService)
func place_vendors(floor_number: int = 0, limit: int = -1) -> Array[Vendor]   # every PC, on floor_ready
```
Buying: host checks the buyer's credit ≥ price and stock left → spawns the item pickup
(`Props.spawn_item`) in the tray → takes the price from that player's credit → ejects that player's
remaining credit as gems (largest gem values first, from props with `gem_value > 0`).
Refund: ejects every player's credit as gems.

## EventBus
- Emits: `vendor_purchase` (all).
- Listens: `floor_ready` (host: spawn vendors at `Level.get_markers(&"vendor")`; the Supply Room has its own marker kind `&"supply_counter"`).

## Data it owns and saves
Uses `VendorStockData` (entries: item, price, weight, stock count; `slots_shown`). Offers are rolled
with `SeededRng.make(run_seed, &"vendor", vendor_index)`. Saves nothing.

## Adding content
New stock lists: `.tres` in `content/vendor_stock/`; departments point to one by `stock_id`. Prices are data. No code.

## Multiplayer
- The coin slot is an Area3D on the host: a released gem entering it is despawned and credited to its
  `last_holder_id` (gems pushed in by a cart credit the cart's pusher).
- Credits and offers are synced to all (shown on the machine's screen).

## Dependencies and stubs
physics_props, items (item pickups exist), interaction (buttons, lever). Stub: spawn gem props by hand.

## Test scene and GUT tests
Test scene: one vending machine with test stock (crowbar 3, energy drink 2), 10 one-value gems and one 5-value gem.
GUT tests: `test_gem_credits_last_holder`, `test_buy_with_exact_credit`, `test_change_pops_out_as_gems`,
`test_not_enough_credit_refused`, `test_refund_returns_all`, `test_two_players_credit_separately`,
`test_stock_runs_out`, `test_offers_same_for_same_seed`, `test_only_items_can_be_offered` (validator check on stock).

## Acceptance criteria
- [ ] Throwing gems into the slot and buying a crowbar works on 2 PCs; change pops out.
- [ ] Two players can use one vendor without spending each other's gems.
- [ ] New stock and prices from data only.

## Open design questions
- DEFAULT: credit belongs to the last holder; gems inserted by nobody (rolled in) credit nobody and are ejected on refund.
- DEFAULT: each vendor shows 3 offers; Supply Room shows more (scene override).
- Shop placement and prices: tuning in playtests.

## Changelog
- 2026-10-07: spec created.
- 2026-10-23: built (Phase 1b). Changes marked above. The machine is made in code (`vending_machine.tscn` is just the
  root): a coin slot (yellow; an Area3D the host watches), one green buy button per offer, a red refund lever (hold E),
  a screen showing your credit, and a tray. Glowing gems aren't money (they don't go in). Vendors aren't spawned
  through a MultiplayerSpawner: every PC puts one at the same markers on `floor_ready`, child "Vendor" of the marker.
  NEW GameConfig `vendors_per_floor` (2): at most that many machines per floor, picked from the `vendor` markers with
  `SeededRng(run_seed, &"vendor_spots", floor)` (same on every PC); `supply_counter` markers always get one. STUB
  (department content): a department without `stock_id` uses the first stock. Content: `stock_zoology_vending`
  (crowbar 3, energy drink 2, knife 4, potted plant 1, hot coffee 3; shows 3). level_gen: `room_hall_grey` got a
  `vendor` marker.

## HANDOFF
**Built (2026-10-23):** `VendorOffer`, `Vendor` (coin slot credit to the last holder, buying, change as gems via
`LootService.gems_for_value`, refunds, synced offers and credits, toasts for "not enough gems"), the `Vendors` autoload,
the stock above, the test scene (`systems/vendors/test/vendor_test.tscn`) and 10 GUT tests
(`tests/unit/vendors/test_vendors.gd`: the spec's list plus `test_credit_and_offers_reach_the_client`). Checked with 2
game copies on a generated floor: both PCs had the same 2 machines and offers, and a purchase for the client matched.

**Foundation / project.godot changes:** GameConfig `vendors_per_floor`. Autoload line `Vendors` (after Loot). No new
EventBus signals (emits `vendor_purchase` on every PC). level_gen's `room_hall_grey` has a `vendor` marker.

**Not yet:** carts pushing gems in (carts: credit the pusher), sounds (audio), a nicer machine model.
