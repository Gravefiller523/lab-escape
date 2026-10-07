# physics_props

Folder: `res://systems/physics_props/` · Autoload: `Props` · Size: L · Phase 1a (proof), 1b (full) · **Highest risk**

## Purpose
All loose physics objects (gems, meat, crates, trash, robot parts, lift parts, keycards, item pickups):
spawning them, syncing them over the network, and Half-Life 2 style **grab, carry, drop and throw**.
Held objects float in front of the camera but still collide with the world. Heavy objects need two
players. Key objects respawn somewhere safe if they fall out of the world. It also keeps the number
of synced objects under control so co-op doesn't lag.

**Not responsible for:** carts (carts), what a prop *means* (gems: loot/vendors; meat: death_respawn;
lift parts: cargo_lift; glowing gems and robot parts: upgrades), item pickups' "add to inventory" (items).

## Public API
```gdscript
class_name NetProp extends RigidBody3D     # root of every prop and item-pickup scene
signal hold_changed()
var net_id: int                            # unique per spawned prop, set by the host
var content_id: StringName                 # prop id (&"prop_gem") or item id for pickups
var data: PropData                         # null for item pickups
var last_holder_id: int                    # last player who held or threw it (vendors use it to know who pays)
var extra: Dictionary                      # spawn data (e.g. {"upgrade_id": &"mutation_fly", "uses_left": 2})
func is_held() -> bool
func get_holder_ids() -> Array[int]        # 1, or 2 for a shared heavy lift
func is_attached() -> bool                 # snapped into a cart, vendor or lift
func attach_to(anchor: Node3D) -> void     # host: freeze and follow anchor (carts, vendor trays)
func detach() -> void                      # host: physics back on
static func of(node: Node) -> NetProp

# Autoload Props (host-only calls are marked)
func spawn_prop(prop_id: StringName, xform: Transform3D, extra: Dictionary = {}) -> NetProp   # host
func spawn_item(item_id: StringName, xform: Transform3D, uses_left: int = -1) -> NetProp      # host; uses ItemData.world_scene
func despawn(prop: NetProp) -> void                                                          # host
func get_prop(net_id: int) -> NetProp
func get_props(content_id: StringName = &"") -> Array[NetProp]     # all, or one kind
func apply_impulse(prop: NetProp, impulse: Vector3) -> void        # host
func get_loose_count(content_id: StringName) -> int

class_name GrabController extends Node    # child "Grab" of the player
signal held_changed(prop: NetProp)        # null when let go
func get_held() -> NetProp
func try_grab(prop: NetProp) -> void      # local: predicts, asks host
func drop() -> void
func throw() -> void
func can_lift(prop: NetProp) -> bool      # mass vs Config.game.grab_max_mass + carry_strength stat
```
Registers with interaction: a use handler (look at prop → grab; holding → drop) and a prompt provider
("Pick up", "Too heavy", "Needs two people"). PRIMARY while holding = throw.

## EventBus
- Emits: `prop_grabbed`, `prop_released`, `key_object_respawned`.
- Listens: `floor_loading` (despawn all props except those riding the lift; cargo_lift hands them over), `player_died`/`player_left` (release what they held).

## Data it owns and saves
Uses `PropData` content. Saves nothing.

## Adding content
New props are `.tres` files in `content/props/` with a scene whose root uses `NetProp`. Mass, key-object
flag, cart rules and despawn timer are data.

## Multiplayer (the hard part; prototype first)
**Ownership.** The host simulates every prop. Clients' copies are frozen (kinematic) and smoothly
follow the host's snapshots.

**Syncing.** One `PropSync` node on the host sends a batch of snapshots (net_id, position, rotation,
velocity) with `unreliable_ordered` RPCs. Only awake (moving) props are sent. Props near any player are
sent `prop_sync_rate_near` times a second; far ones `prop_sync_rate_far`. Sleeping props cost nothing.
Clients buffer ~100 ms and interpolate, so movement looks smooth.

**Spawning.** Host-only via a `MultiplayerSpawner` with a custom spawn function (data:
`content_id`, `net_id`, transform, `extra`). Late or reconnecting players get every existing prop automatically.

**Holding with local prediction (approach A, default).** When a client grabs:
1. The client immediately moves its own copy toward its hold point each frame (shape-cast against the
   world so it doesn't pass through walls). This makes holding feel instant.
2. It sends a grab request; the host checks reach and mass and either confirms or refuses (the client
   snaps the prop back if refused).
3. While held, the client sends its hold-point position ~30 times a second. The host pulls the real
   body toward it with a spring force, so it really collides, pushes things and stacks.
4. The holder ignores host snapshots for that prop but corrects gently if they drift more than
   `hold_break_distance`; past that, the prop is dropped.
5. On release/throw the holder blends back to host snapshots over ~0.2 s.
**Approach B (fallback to compare in the proof):** hand physics authority of the held prop to the
holder's PC while held, and give it back on release.

**Two-player lift.** If mass is above `grab_max_mass` but at most `two_player_lift_max_mass`, it only
lifts once two players hold it; the hold point is the average of both.

**Key objects.** `is_key_object` props falling below `out_of_world_y` (or into a kill zone) are moved
by the host to their last safe resting spot (last place they were still on the WORLD layer), or else
the lift room.

**Limits.** Despawn timers from data; loot merges plain gems when there are too many (see loot).
Pickups of 2 players on the same frame: the host accepts the first request it receives; the second gets "refused".

## Dependencies and stubs
net_core, player (hold point, aim), interaction (handlers). Stub player: a capsule with a camera and the GrabController.

## Test scene and GUT tests
**Phase 1 proof scene** `systems/physics_props/test/pass_the_box.tscn`: a grey-box room, a table, 5
crates of different masses, one heavy (two-player) crate, a pit with a kill zone and one key object.
Two local instances (then two Steam PCs): pass one box back and forth, stack, throw, drop into the pit.
Measure: does holding feel instant for the client? Jitter? Bandwidth at 100 awake props?
GUT tests: `test_spawn_assigns_unique_net_id`, `test_too_heavy_refused`, `test_two_player_lift_needs_two`,
`test_first_grab_wins`, `test_key_object_respawns_at_safe_spot`, `test_sleeping_props_not_sent`,
`test_throw_sets_last_holder`, `test_attach_freezes_detach_restores`.

## Acceptance criteria
- [ ] Two players on two PCs can pass one box with no visible lag for the holder and smooth motion for the watcher.
- [ ] Held props collide with walls and can knock other props over and be stacked.
- [ ] A lift part dropped in the pit reappears at a safe spot for everyone.
- [ ] 150 props on a floor (most asleep) keep the game smooth with 4 players; tested at 8.
- [ ] A new prop is just a new `.tres` + scene.

## Open design questions
- Approach A vs. B: decide after the Phase 1 proof.
- DEFAULT: first grab wins; no tug-of-war.
- DEFAULT: players can't stand on a prop they are holding (prevents "prop surfing" launching).

## Changelog
- 2026-10-07: spec created.
