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

# NEW 2026-10-17:
# NetProp
func is_lifted() -> bool                  # off the ground: one holder, or two for a heavy prop
func needs_two_people() -> bool
func get_spawner() -> PropSpawner
func get_safe_position() -> Vector3       # key objects return here
# Props autoload (class_name PropsService)
signal grab_refused(prop: NetProp, reason: String)   # local
func get_spawner() -> PropSpawner         # the current level's
static func grab_of(body: PlayerCharacter) -> GrabController
# class_name PropSpawner extends Node3D: put one in every level; props are its children.
func spawn_prop(...) / despawn / get_prop / get_props / get_loose_count / apply_impulse   # same as Props
func decide_grab(prop: NetProp, player_id: int, refusal: Array[String]) -> Array[int]   # host: the grab rules
func release_all(prop: NetProp) -> void   # host
func get_snapshot_batch(near: bool) -> Array   # what the host would send now (moving props only)
func get_config() -> GameConfig
func use_net(net: NetService, config: GameConfig) -> void   # tests only
```
NEW 2026-10-17: `NetProp.apply_holders`, `apply_snapshot`, `start_predicting`, `stop_predicting`,
`set_hold_target` and `set_spawner`, and PropSpawner's `request_grab`, `request_release` and
`send_hold_point`, are internal to physics_props (only PropSpawner and GrabController call them).
The `Props` autoload gives every body a GrabController when it spawns, the same way interaction does,
so the player scene needn't change. A level needs a `PropSpawner` node, like it needs a PlayerSpawner.
When the connection changes (hosting, joining, leaving), the host spawns its props again so new
clients get them, and clients drop their old copies.
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
CHANGED 2026-10-17 (Zachary's decisions, gap 24): a second player grabbing a **heavy** prop that someone
holds **joins the lift** (up to 2 holders). A second player grabbing a **normal** prop someone holds
**takes it**: the newest grab wins and the old holder lets go. The host decides the holder(s).
CHANGED AGAIN 2026-10-17 (Zachary, after playtesting): **no limit on helpers.** Each holder of a heavy
prop takes `heavy_lift_per_holder` kg (30) off its weight. `NetProp.get_support()` = holders x 30 / mass
(0..1): the host's spring pulls that much weaker, gravity is reduced by that much, and the top speed is
`held_prop_max_speed` (8 m/s) x support. An 80 kg crate: 1 holder 37% (drags very slowly), 2 holders 75%,
3 holders 100% (fully lifted, like a normal prop). CHANGED: **nothing is too heavy**; `two_player_lift_max_mass`
is no longer used (a 300 kg prop with 1 holder: 10%). Heavy props aren't predicted on the client.

**Solid props (NEW 2026-10-17):** players collide with props (the player mask has PROPS), so you bump
into them and can stand on them, but props don't react to players (their mask has no PLAYERS): walking
into a prop can't shove it through a wall. You move props by holding them. A prop you hold ignores your
body (collision exception), so you can't stand on or push yourself with it.
**Pushing (NEW 2026-10-17, Zachary):** walking into a prop pushes it. The walker's GrabController sees the
collision and asks the host (`request_push`, ~20 a second); the host gives the prop up to walking speed x
`support_for(number of pushers)`, the same weight rule as carrying: props of 30 kg or less move at walking
speed, the 80 kg crate at about a third, a 300 kg one at a tenth; more pushers = faster. The host ignores
pushers more than 3 m away and speeds above sprinting.

**Key objects.** `is_key_object` props falling below `out_of_world_y` (or into a kill zone) are moved
by the host to their last safe resting spot (last place they were still on the WORLD layer), or else
the lift room.
CHANGED 2026-10-17: the "last safe spot" is where it last fell asleep (came to rest) at least 5 m above
`out_of_world_y`, or where it spawned. Non-key props that fall out of the world are despawned. No kill
zones or "lift room" fallback yet.

**Limits.** Despawn timers from data; loot merges plain gems when there are too many (see loot).
CHANGED 2026-10-17: grabs are handled in the order the host receives them. For a normal prop the
newest grab wins (even two on the same frame end with exactly one holder: the later one). For a heavy
prop every grabber joins in (no limit).

## Dependencies and stubs
net_core, player (hold point, aim), interaction (handlers). Stub player: a capsule with a camera and the GrabController.

## Test scene and GUT tests
**Phase 1 proof scene** `systems/physics_props/test/pass_the_box.tscn`: a grey-box room, a table, 5
crates of different masses, one heavy (two-player) crate, a pit with a kill zone and one key object.
Two local instances (then two Steam PCs): pass one box back and forth, stack, throw, drop into the pit.
Measure: does holding feel instant for the client? Jitter? Bandwidth at 100 awake props?
GUT tests: `test_spawn_assigns_unique_net_id`, `test_too_heavy_refused`, `test_two_player_lift_needs_two`,
`test_first_grab_wins` (CHANGED 2026-10-17: now `test_newest_grab_takes_normal_prop` and
`test_second_grab_helps_lift_heavy_prop`), `test_key_object_respawns_at_safe_spot`, `test_sleeping_props_not_sent`,
`test_throw_sets_last_holder`, `test_attach_freezes_detach_restores`.

NEW 2026-10-17: tests are in `tests/unit/physics_props/test_props.gd`, plus
`test_grab_carries_and_throw_sets_last_holder` and `test_client_grab_goes_through_host_and_newest_grab_wins`
(two "PCs" over real ENet). Test props added as content: `prop_crate` (10 kg), `prop_crate_heavy` (80 kg,
two people), `prop_lift_part_zoology` (key object), with scenes in `systems/physics_props/scenes/`.
The proof scene has 4 light crates (all the same mass for now), the heavy crate, a lift part, a table,
a pit (no kill zone: things fall out of the world), and R to reset the props.

## Acceptance criteria
- [ ] Two players on two PCs can pass one box with no visible lag for the holder and smooth motion for the watcher.
  *Two local windows work (checked 2026-10-17). Zachary to judge the feel; two PCs on Steam still to do.*
- [x] Held props collide with walls and can knock other props over and be stacked. *(the host's spring-pulled body really collides; check by eye)*
- [x] A lift part dropped in the pit reappears at a safe spot for everyone. *(GUT)*
- [ ] 150 props on a floor (most asleep) keep the game smooth with 4 players; tested at 8. *Not measured yet.*
- [x] A new prop is just a new `.tres` + scene. *(the three test props)*

## Open design questions
- Approach A vs. B: decide after the Phase 1 proof.
- CHANGED 2026-10-17 (decided): newest grab takes a normal prop; a second grab on a heavy prop helps lift it.
- DEFAULT: players can't stand on a prop they are holding (prevents "prop surfing" launching).

## Changelog
- 2026-10-07: spec created.
- 2026-10-17: grab rules decided by Zachary: newest grab takes normal props; a second player helps lift heavy ones.
- 2026-10-17: Phase 1a proof built (approach A). Added the functions marked NEW, PropSpawner, the test props.
- 2026-10-17: after playtesting: unlimited helpers on heavy props (`heavy_lift_per_holder`, `held_prop_max_speed`,
  `get_support()`, `needs_two_people()` -> `needs_help()`), props solid for players (player mask + prop mask),
  holders ignore the prop they hold. Tests: `test_every_grab_helps_lift_heavy_prop`,
  `test_each_helper_carries_more_of_the_weight`, `test_heavy_prop_moves_faster_with_more_helpers`,
  `test_players_can_stand_on_props_and_bump_into_them`, `test_holder_does_not_collide_with_held_prop`.
- 2026-10-17: nothing is too heavy to move (`two_player_lift_max_mass` deprecated); walking into props pushes
  them by weight (`add_push`, `support_for`, `request_push`). Tests: `test_nothing_is_too_heavy`,
  `test_walking_into_props_pushes_them_by_weight`.

## HANDOFF
**Done (Phase 1a proof, approach A):** `NetProp`, `PropSpawner` (spawning through a MultiplayerSpawner,
net ids, near/far snapshot batches of moving props only, host spring holding, grab rules, throw,
key-object respawn, fallen props removed, session restarts), the `Props` autoload, `GrabController`
(plugs into interaction: E grabs/drops, left click throws, Q drops, prompts "Pick up", "Take", "Help lift",
"Help lift (N holding)", "Drag (heavy: more people make it faster)", "Too heavy", "Drop"), 3 test props, the pass-the-box scene, 10 GUT tests (all pass).

**Not done yet:** item pickups (`spawn_item` is a stub until items exists); `floor_loading` handover to
cargo_lift; releasing props on `player_died` (death_respawn); carts' use of `attach_to`; approach B to
compare; client-side drift correction (the host already drops a held prop that gets stuck); the
"can't stand on a prop you're holding" rule; the carry_strength stat (upgrades); 5 crates of different
masses (needs more content files); measuring bandwidth at 100 awake props and 150 props with 8 players.

**Known limits:** a client sees its held light prop instantly (prediction), but while two players lift a
heavy prop, both see it move with the network delay (no prediction for shared lifts). The held prop is
pulled by a spring, so very fast turning makes it lag slightly behind your hands, on purpose.

**For other systems:** levels need a `PropSpawner` node; spawn props with `Props.spawn_prop(id, xform, extra)`
(host only); vendors read `last_holder_id`; carts call `attach_to`/`detach`; upgrades can register a
higher-priority use handler on the InteractionController ("Eat glowing gem") that checks
`PropsService.grab_of(body).get_held()`.
