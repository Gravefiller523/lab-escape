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
