# carts

Folder: `res://systems/carts/` · Size: M · Phase 1b

## Purpose
Pushable carts that carry many props at once. A player grabs the handle to push; props dropped into
the basket **snap into place and ride along frozen** (no jitter, nothing flies out); grabbing one out
turns its physics back on. One pusher at a time. Carts fit through every door and in the cargo lift.

**Not responsible for:** where carts spawn (level_gen places `cart` markers; this system spawns carts
at them), door widths (level_gen room rules), lift travel (cargo_lift carries the cart and contents).

## Public API
```gdscript
class_name Cart extends NetProp
signal contents_changed()
func get_contents() -> Array[NetProp]
func get_capacity() -> int                  # Config.game.cart_capacity unless the cart scene overrides it
func can_accept(prop: NetProp) -> bool      # cart_allowed, not full, not another cart
func get_pusher_id() -> int                 # 0 if nobody
func request_push(start: bool) -> void      # local player starts/stops pushing
# Host only:
func add_prop(prop: NetProp) -> bool        # snaps into the next free slot anchor
func remove_prop(prop: NetProp) -> void
func spill_all(impulse: float = 2.0) -> void  # e.g. if it tips over or is hit hard (option)
func request_take_out(prop: NetProp) -> void  # NEW 2026-10-23, local
func has_prop(prop: NetProp) -> bool        # NEW
static func cart_of(prop: NetProp) -> Cart   # NEW: the cart a prop rides in
@export var capacity_override: int          # NEW: 0 = Config.game.cart_capacity

# NEW 2026-10-23: autoload Carts (systems/carts/carts.gd, CartsService)
func pushed_by(player_id: int) -> Cart
func spawn_floor_carts() -> Array[NetProp]  # host, on floor_ready
```
Cart types are props: `content/props/prop_cart_*.tres` with a scene whose root is `Cart`. The scene
has a `Basket` Area3D and a grid of `Slot` Marker3Ds (anchors).

## EventBus
- Emits: `cart_contents_changed(cart)`.
- Listens: `floor_ready` (host: spawn carts at `Level.get_markers(&"cart")`).

## Data it owns and saves
Cart PropData content. Saves nothing.

## Adding content
New cart types: a new prop `.tres` and cart scene (different capacity, look, wheels). No code.

## Multiplayer
- Host simulates the cart. Pushing: the pusher's PC predicts the cart in front of them (like a held
  prop, approach A from physics_props) and sends the handle position; the host pulls the real cart.
- Snapped props are attached with `NetProp.attach_to` and stop sending snapshots (they follow the cart).
- A second player trying to push is refused ("Someone is pushing").

## Dependencies and stubs
physics_props (NetProp, attach/detach, sync), interaction (handle prompt), level_gen markers (stub: place a marker by hand).

## Test scene and GUT tests
Test scene: grey-box corridor with a door at the minimum width, a ramp, a fake lift box; one cart and 20 gems.
GUT tests: `test_prop_snaps_in_and_freezes`, `test_grab_out_detaches`, `test_capacity_from_config`,
`test_second_pusher_refused`, `test_cart_cannot_hold_cart`, `test_disallowed_prop_rejected`.

## Acceptance criteria
- [ ] Fill a cart with 12 gems, push it through a door and up a ramp with nothing falling out, on 2 PCs.
- [ ] Grabbing a gem from the cart works with physics back on.
- [ ] A cart fits in the cargo lift with a player.

## Open design questions
- DEFAULT: enemies can't knock items out or steal carts (EnemyData has `can_steal_from_carts` for later).
- DEFAULT: players can't ride inside carts (could be a funny later feature).

## Changelog
- 2026-10-07: spec created.
- 2026-10-23: built (Phase 1b). Changes marked above. CHANGED from the spec: the host always runs a cart's physics
  (NEW physics_props flag `NetProp.keep_on_host`: never handed to a client), and pushing isn't predicted on the pusher's
  PC: the host pulls the cart towards a spot 1.3 m in front of the pusher (from its copy of the pusher's body) and turns
  its handle to face them, so a client's push lags by their ping. The basket's 24 slots (3 x 4 x 2) are made in code;
  capacity = `cart_capacity` (12) unless `capacity_override`. Props in a cart are attached (frozen, no collision with
  the cart) and follow it; other PCs see them through the normal prop snapshots. E keys (Carts autoload, priority 55):
  E on a cart = push / let go, E on a prop in a cart = take it out into your hands. The pusher lets go if the cart gets
  stuck more than 3.5 m away, or dies. Content: `prop_cart_standard` (30 kg, tag `cart`; scene
  `systems/carts/scenes/cart_standard.tscn`); one spawns at each `cart` marker (the lift room has one).
- 2026-10-24: playtest fix: the basket also checks what is already in it every physics tick, so a prop carried into it and let go there is taken.

## HANDOFF
**Built (2026-10-23):** `Cart` (extends NetProp), the `Carts` autoload, the standard cart, the test scene
(`systems/carts/test/cart_test.tscn`) and 10 GUT tests (`tests/unit/carts/test_carts.gd`: the spec's list plus
`test_cart_spawns_as_a_cart`, `test_e_on_a_prop_in_the_cart_takes_it_out_into_your_hands`, `test_pushing_moves_the_cart`,
`test_contents_follow_into_the_lift_zone`). Checked with 2 game copies on a generated floor: the host dropped 4 gems in,
the client pushed the cart 2 m, and both PCs had it in the same place with the 4 gems inside.

**Foundation / project.godot changes:** autoload line `Carts` (after Upgrades). No new EventBus signals (emits
`cart_contents_changed`).

**Other systems touched (this branch):** physics_props (NEW `NetProp.keep_on_host`; `PropSpawner.hand_to` refuses it).

**Not yet:** vendors don't credit gems pushed in by a cart (gems in a cart are attached, so they don't fall into the coin
slot; take them out first); no tipping or spilling on hard hits; no wheel sounds (audio).
