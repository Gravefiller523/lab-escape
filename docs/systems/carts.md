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
