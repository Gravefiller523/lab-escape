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
func is_fragile() -> bool                  # NEW 2026-10-19: PropData.fragile_break_speed > 0 (shatters on hard hits)
static func of(node: Node) -> NetProp

# Autoload Props (host-only calls are marked)
func spawn_prop(prop_id: StringName, xform: Transform3D, extra: Dictionary = {}) -> NetProp   # host
func spawn_item(item_id: StringName, xform: Transform3D, uses_left: int = -1) -> NetProp      # host; uses ItemData.world_scene
func despawn(prop: NetProp) -> void                                                          # host
func get_prop(net_id: int) -> NetProp
func get_props(content_id: StringName = &"") -> Array[NetProp]     # all, or one kind
func apply_impulse(prop: NetProp, impulse: Vector3) -> void        # host
func get_loose_count(content_id: StringName) -> int
func request_break(prop: NetProp) -> void  # NEW 2026-10-19: a fragile prop hit too hard; the host shatters it (toast + despawn)

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

CHANGED 2026-10-17 (after Zachary's playtest: jittery and late for the joining player): snapshots carry the
host's clock; clients estimate it and show props `prop_interpolation_delay_msec` (100 ms) behind, gliding
between two snapshots; `prop_sync_rate_near` 20 -> 30. A client pushing a prop moves its own copy at once
(`predict_push`) and the host follows. Pushed props move at 90% of the pusher's speed (x weight rule) and
keep moving for 250 ms after the last push report, so the pusher stays pressed against them.
**Syncing.** One `PropSync` node on the host sends a batch of snapshots (net_id, position, rotation,
velocity) with `unreliable_ordered` RPCs. Only awake (moving) props are sent. Props near any player are
sent `prop_sync_rate_near` times a second; far ones `prop_sync_rate_far`. Sleeping props cost nothing.
Clients buffer ~100 ms and interpolate, so movement looks smooth.

**Spawning.** Host-only via a `MultiplayerSpawner` with a custom spawn function (data:
`content_id`, `net_id`, transform, `extra`). Late or reconnecting players get every existing prop automatically.

**CHANGED 2026-10-17: approach B is now used (Zachary chose it after playtesting approach A).** Each prop
has a physics owner (`get_owner_peer()`, 1 = host). When a client grabs a prop alone or pushes a loose one,
the host hands its physics to that client (`_set_owner` with the current state): the client's copy turns
dynamic and reacts with no delay, and the client sends its position to the host ~30 times a second, which
passes it on to everyone. When it has been untouched for 0.8 s and has settled, the client hands it back.
Props held by several players (heavy lifts) stay with the host. A newest grab moves ownership to the new
grabber. Props of a player who leaves, and key objects that fall out of the world, go back to the host.
Trade-off: the owner's PC is trusted with that prop's position (fine for co-op among friends). On the
owner's PC, other props are frozen copies, so a held prop can't knock them over there (the host's copy can).
Non-owners show props `prop_interpolation_delay_msec` = 50 ms behind (was 100).
**Holding, Half-Life 2 style (NEW 2026-10-18, from Valve's Source SDK `weapon_physcannon.cpp`):** a fully lifted
prop is steered each physics step with the velocity that reaches the hold point by the next step (capped at
`held_prop_track_speed` = 20 m/s), instead of a spring. It keeps the angle it was picked up at relative to
the holder's facing (yaw only) and turns with them (spin capped at 3600 deg/s, angular damping 10). While
fully lifted its physics mass is 1 kg (`NetProp.HELD_MASS`) so it nudges things gently; its real weight
(`get_true_mass()`) still decides the carry rules and throws. The hold point is `hold_distance` + the
prop's size in front of the eyes, pitch limited to 75 degrees, pulled in when a wall is in the way. Letting go
caps its speed at `held_prop_release_max_speed` (10.5 m/s) and spin at 720 deg/s (no flinging); a throw
adds a little random spin. Heavy props that aren't fully lifted still use the weaker pull (they drag).
**More from the research (NEW 2026-10-18, Zachary):** (1) every instant move of a prop (key-object respawn,
new owner, big follower snaps) calls `reset_physics_interpolation()` so it doesn't smear; (2) throws follow
Half-Life 2: push = `throw_force` (34) x a weight factor (0.5 at 0.5 kg to 4 at 15 kg+), so a 10 kg crate flies
~10 m/s and heavier things less far (`throw_impulse` is deprecated); (3) you can't pick up a prop you're
standing on (no prompt either); (4) **ownership sequence** (Glenn Fiedler): each prop's number goes up every
time its owner changes; snapshots and hand-backs carry it and anything with an old number is ignored;
(5) **claim ahead**: a prop run by a player's PC looks 0.15 s ahead along its speed (plus 0.15 m) 20 times a
second and claims loose props it is about to hit (`find_props_ahead`), so they're already its own on contact.
**Smoothness:** physics interpolation is on for the project; followers show props at least two update
intervals behind (Source's rule), `prop_sync_rate_near` 30 -> 40, with only a light extra glide.
NEW 2026-10-18 (from the research, Zachary approved): **knock-on ownership** (a prop run by a player's PC
that bumps a loose host-run prop asks the host to run that one too: `request_knock_on`, granted if one of
the asker's props is within 3 m); **speed in snapshots** (position, rotation and velocity; followers carry a
late prop along its last speed for up to 0.2 s, and hand-overs keep a flying prop flying via
`get_estimated_velocity`); **hand-over cooldown** (`prop_owner_cooldown_msec` = 300: a prop that just
changed PC waits before changing again; `hand_to` is now public for the host).
Old text kept below for reference.
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
into a prop can't shove it through a wall. You move props by holding them. CHANGED 2026-10-17 (Zachary): a prop you hold stays solid against you;
instead, stepping onto the prop you hold drops it (Half-Life 2's rule), so you can't ride it.
**Pushing (NEW 2026-10-17, Zachary):** walking into a prop pushes it. CHANGED: only walking into its **side**
counts (contacts whose normal points up or down by more than 0.5 are ignored), so standing or walking on
top of a prop never moves it. With approach B the pusher's PC runs the pushed prop. The walker's GrabController sees the
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
- [x] Two players on two PCs can pass one box with no visible lag for the holder and smooth motion for the watcher.
  *Two local windows (2026-10-17) and 2 PCs on real Steam (Zachary, 2026-10-18).*
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
- 2026-10-17: smoother for clients (timestamped snapshots, interpolation delay, 30 Hz, push prediction).
  Test: `test_client_push_moves_its_copy_at_once_and_the_host_follows`.
- 2026-10-17: approach B (physics ownership hand-off), side-only pushing, 50 ms interpolation delay. Added
  `get_owner_peer`, `is_simulated_here`, `throw_strength`, `peer_of_player`, `report_stuck`. Tests:
  `test_client_grab_hands_physics_to_the_client_and_back`, `test_standing_on_a_prop_does_not_push_it`.
- 2026-10-17: a client's throw is no longer held back (`let_go_here`); held props stay solid and standing on
  your held prop drops it. Tests: `test_held_prop_stays_solid_but_standing_on_it_drops_it`,
  `test_client_throw_flies_as_far_as_a_host_throw`.
- 2026-10-18: knock-on ownership, velocity in snapshots, hand-over cooldown. Tests:
  `test_hand_over_waits_for_the_cooldown`, `test_snapshots_carry_speed`, `test_knock_on_ownership`.
- 2026-10-18: Half-Life 2 style holding (shadow control, pick-up angle, 1 kg while held, size- and wall-aware
  hold point, release caps, throw spin), physics interpolation, Source-style interpolation delay. Added
  `get_true_mass`, `get_radius`, `throw_now`. Tests: `test_held_prop_turns_with_the_holder`,
  `test_held_prop_is_light_and_heavy_again_when_dropped`, `test_dropping_a_fast_prop_does_not_fling_it`,
  `test_held_prop_comes_closer_near_a_wall`.
- 2026-10-18: interpolation resets on teleports, Half-Life 2 throw strength (`throw_force`), no pick-up of what
  you stand on, ownership sequence numbers, claim-ahead. Tests: `test_heavier_props_are_thrown_less_far`,
  `test_cannot_pick_up_what_you_stand_on`, `test_old_owner_updates_are_ignored`,
  `test_props_about_to_be_hit_are_found_ahead`.
- 2026-10-18: NEW: the Props autoload registers the `prop` spawner with the debug console, so `spawn prop_<name> [count]`
  works (host only, laid out with `DebugConsoleService.spread`). Test: `tests/integration/test_console_spawns_props.gd`.
- 2026-10-18: fix (found by Zachary): a player who joins after props were moved saw them where they first spawned.
  Each new copy on a client now asks the host for the prop's current place, owner, owner number and holders
  (NEW `NetProp.apply_join_state`). Test: `test_late_joiner_sees_props_where_they_are_now`.
- 2026-10-18: fix: a PropSpawner in a level being unloaded (the host left) ignores roster changes instead of
  erroring. Test: `test_unloaded_level_ignores_roster_changes`.
- 2026-10-18 fix (Zachary: error at a floor change): a message can reach a PropSpawner (or another scene node)
  that is already leaving the tree with its scene; every RPC handler on scene nodes now ignores it then
  (PropSpawner, LevelFloor, BreakRoom, PlayerCharacter, InteractionController, test scenes).

- 2026-10-19 (cargo_lift branch): fragile props (`PropData.fragile_break_speed`, for the vacuum tube). The PC running a
  fragile prop watches its contacts; a hit at that speed or faster calls `request_break` and the host shatters it
  for everyone ("The vacuum tube shattered!"). NEW: `NetProp.is_fragile()`, `PropSpawner.request_break()`. Test:
  `test_fragile_props_shatter_when_dropped_hard`.

- 2026-10-19 (items branch): `Props.spawn_item` is real: item pickups (ItemData.world_scene, a NetProp with an
  ItemPickup child) spawn like props (`PropSpawner.spawn_item`; `spawn_prop` also accepts item ids and makes a PropData
  from the ItemData, mass = `world_mass`).

- 2026-10-23 (carts branch): NEW `NetProp.keep_on_host` (bool): the host always runs its physics; `PropSpawner.hand_to`
  won't hand it to a client. Carts use it.
- 2026-10-24: playtest fix: light props thrown hard (a gem flies ~57 m/s) went through thin walls. Every NetProp now uses continuous collision detection (`continuous_cd = true`). Tests in `tests/unit/physics_props/test_fast_props.gd`.
- 2026-10-29 (feel step 0): the hold, throw and push numbers moved to ONE place, `Config.feel.props` (`PropTuning`, in `config/feel_tuning.tres`). REMOVED constants `NetProp.HOLD_STIFFNESS`, `HOLD_DAMPING`, `HOLD_BREAK_SECONDS`, `PUSH_SPEED_FACTOR`, `HELD_MASS`, `HELD_ANGULAR_DAMP`, `HOLD_MAX_SPIN`, `RELEASE_MAX_SPIN`, `THROW_SPIN` and `GrabController.MAX_HOLD_PITCH`, `MIN_HOLD_GAP` (nothing outside physics_props used them). DEPRECATED (kept, no longer read) GameConfig `grab_max_mass`, `heavy_lift_per_holder`, `held_prop_max_speed`, `held_prop_track_speed`, `held_prop_release_max_speed`, `grab_reach`, `hold_distance`, `hold_break_distance`, `throw_force`. No values changed. Network rates stay in GameConfig.
- 2026-10-29 (feel step 0.3): physics project settings (`project.godot`): Jolt `limits/max_angular_velocity` 47.12 -> 62.83 rad/s (the hold spin of 62.8 was being clamped), `limits/max_linear_velocity` 500 -> 100 m/s (a thrown gem peaks near 57), `simulation/sleep_velocity_threshold` 0.03 -> 0.05 (props settle sooner), `simulation/penetration_slop` 0.02 -> 0.01 (props sink into each other less); `physics/common/physics_jitter_fix` 0.5 -> 0 (physics interpolation is on, so it only adds jitter). Gravity is unchanged until movement step 1.3.

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
- 2026-10-24 (fix, found by Zachary): `GrabController.get_held()` returns null once the held prop has been freed (a vial
  put into the mutation machine), instead of the freed object, so prompts and E don't error that frame.
