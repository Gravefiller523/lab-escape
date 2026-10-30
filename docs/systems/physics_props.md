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
# NEW 2026-10-30 (HL2 feel step 4.3): the punt
signal prop_punted(prop: NetProp, player_id: int)   # host
func punt_strength(prop: NetProp) -> float            # the punt's impulse (kg x m/s)
func request_punt(prop: NetProp, direction: Vector3, predicted: bool) -> void   # PropPunter calls it
func decide_punt(body: PlayerCharacter, prop: NetProp) -> String   # host: "" or why not (REFUSE_*)
signal enemy_punted(enemy: Enemy, player_id: int)   # host
static func punt_push_for(enemy: Enemy, direction: Vector3) -> Vector3
func request_punt_enemy(enemy: Enemy, direction: Vector3) -> void
func decide_punt_enemy(body: PlayerCharacter, enemy: Enemy) -> String
static func grab_reach_of(body: PlayerCharacter) -> float   # grab_reach, longer with the punt arm
func request_pull(prop: NetProp, body: PlayerCharacter, point: Vector3) -> void   # PropPunter, while E is held
func decide_pull(body: PlayerCharacter, prop: NetProp) -> String

# class_name PropPunter extends Node (NEW 2026-10-30): the punt arm cybernetic's behaviour node, under a body
signal punted(prop: NetProp)                          # local
static func of(body: Node) -> PropPunter              # null = no punt arm
func try_punt() -> bool                               # local: what right click does
func find_target(reach: float = -1.0) -> NetProp      # the loose prop aimed at within punt_range (or reach)
func find_enemy() -> Enemy                            # the living enemy aimed at within punt_range
func pull(prop: NetProp, by_key: bool = false) / stop_pull() / get_pulled() / can_pull(prop)   # local
signal punted_enemy(enemy: Enemy)                     # local
# NetProp: punt_now(direction, strength) (owner), mark_launched_by(player_id) (the punter gets hit credit),
# add_pull(player_id, point, speed) / is_pulled() (owner)
```
**Punt (NEW 2026-10-30, HL2 feel step 4.3):** like Half-Life 2's gravity gun punt, given by the punt arm
cybernetic (`content/cybernetics/cybernetic_punt_arm.tres`, from a data drive in the mutation machine, or
`upgrade cybernetic_punt_arm` in the console). Right click launches the prop you hold, or else the loose prop
you aim at within `punt_range` (6.35 m; if the look ray misses, the one nearest the middle of the view inside
`punt_cone_dot` that no wall hides). It flies off at `punt_speed` (15 m/s), up to `punt_light_bonus` faster for
light things, but never with more than `punt_max_impulse` (heavy crates only shift). A prop resting on
something is never driven down into it: the launch points at least `punt_floor_lift` up (about 12 degrees),
so things on the floor hop up and fly (our choice, for feel). One punt per
`punt_cooldown` (0.5 s). With nothing to punt, the click goes on to the item in your hand. The host checks it
(`decide_punt`: the arm, the cooldown, reach, nobody else holding it, nobody standing on it), then the PC
that runs the prop launches it; if that is the punter's PC it already did, at once. The punter gets the
credit for its hits, as with a throw. Sound: `EventSounds.punt`. Numbers: `Config.feel.props`, `punt_*`.
**Punting enemies (NEW 2026-10-30, Zachary):** an enemy nearer the middle of the view than any prop is shoved
instead (`Enemy.knock_back`): away from you with a little hop, `punt_enemy_impulse` / its impact mass m/s (at most
`punt_enemy_max_speed`), so a rat flies and a kangaroo stumbles. It never does damage, but the enemy turns on you.
**Pull (NEW 2026-10-30, Zachary's idea):** with the arm, holding E on a prop that is too far to pick up (within
`pull_range`, 8 m) drags it towards you like a magnet (`pull_speed`), and it is picked up as soon as it is in
reach. CHANGED 2026-10-30 (Zachary's playtest): it keeps its weight and tumbles along the ground (the tug acts
`pull_tumble` above its middle) instead of floating, and the range is 8 m (was 15). The arm also makes your reach `pull_grab_bonus` (1.5 m) longer (`PropSpawner.grab_reach_of`).
Props that need helpers aren't pulled. Like pushing, the host hands a pulled prop to the puller's PC, so it
moves without delay.
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

NEW 2026-10-30 (punt): `tests/unit/physics_props/test_punt.gd`: `test_light_things_fly_faster_and_heavy_things_barely_move`,
`test_right_click_punts_the_crate_you_aim_at`, `test_nothing_in_reach_leaves_the_click_to_the_item`,
`test_a_held_crate_is_punted_out_of_your_hands_faster_than_a_throw`, `test_only_a_punt_arm_can_punt_and_not_too_often`,
`test_a_punted_crate_kills_a_light_enemy_and_the_punter_gets_the_credit`, `test_a_client_punt_launches_the_crate_on_every_pc`,
`test_holding_e_pulls_a_far_crate_in_and_picks_it_up`, `test_the_arm_lets_e_reach_a_bit_further_and_e_starts_a_pull`,
`test_heavy_props_are_not_pulled`, `test_a_client_pulls_a_crate_from_afar`, `test_punting_an_enemy_shoves_it_but_never_hurts_it`,
`test_heavy_enemies_are_shoved_less`.
Playtest: F6 in `systems/player/test/feel_playtest.tscn` gives everyone the punt arm.

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
- 2026-10-29 (HL2 feel step 2, branch feel/step-2). New numbers are in `Config.feel.props` (PropTuning).
  - 2.1: `throw_force` 25.4 (was 34, Half-Life 2's; a 10 kg crate flies about 7 m/s), `held_prop_release_max_speed` 7.2 (was 10.5), `held_prop_track_speed` 25 (was 20). NEW `prop_max_speed` 50 (the PC running a prop caps it), `disable_sprint_while_holding` (GrabController sets a movement modifier with the NEW `MovementEffectData.can_sprint` = false), held props never sleep (`can_sleep` off while held), NEW `drop_clears_velocity_on_contact`: a plain drop (not a throw) while touching something stops it dead (`NetProp.settle_if_touching()`, `is_touching_something()`; `let_go_here(player_id, thrown)` has a NEW `thrown` argument).
  - 2.2: held props sit `hold_base_gap` (NEW, 0.6) + the body's radius + their depth along the view in front of the eyes (`NetProp.get_depth_along(direction)`; `hold_distance` is @deprecated). While touching something a held prop slides along it (motion test) and turns slower (`hold_contact_spin_min`, `hold_contact_spin_rate`), so it doesn't jitter against walls. Picked up within `carry_snap_angle_degrees` (30) of square, it is carried square (`NetProp.tidy_rotation`). Drop rule: dropped when its smoothed distance from the hold point passes `hold_error_drop` (0.45 m, `hold_error_smoothing` 0.15 s) after `hold_error_grace` (1 s); `hold_break_distance` and `hold_break_seconds` are @deprecated. When that happens the PC running it lets go at once and it stops dead. Grabbing forgives a near miss: NEW `grab_cone_dot` (0.8) and `GrabController.find_prop_in_view()`; never when aiming at an Interactable. NEW `GrabController.get_hold_point()`, `PropsService.spawner_for(node)`.
  - 2.3 (Zachary's rule, NEW `no_grab_while_stood_on`): the host refuses a grab of a prop any player stands on (NEW `PropSpawner.REFUSE_STOOD_ON`, `is_stood_on(prop)`, `get_body_standing_on(prop)`), and drops a held prop the moment any player steps onto it. Held props stay solid and light (1 kg) as before, like Half-Life 2.
  - 2.4: knocks and scrapes. The PC running a prop hears its hits (speed lost in a physics step beyond gravity), plays the knock and sends it through the host to everyone (`PropSpawner.report_impact`, `play_impact`, signal `impact_heard`). Silent below `impact_sound_min_speed` (1.8 m/s), full volume at `impact_sound_full_speed` (8), at most one per `impact_sound_debounce` (0.05 s); a soft knock (`pickup_sound_db`) on pickup. Sliding props scrape on every PC, worked out from how the copy moves (`scrape_min_speed`, `scrape_full_speed`, `scrape_volume_db`; carts never scrape). Sounds come from the prop's material: NEW `PropData.surface` (default wood; lift parts and carts metal, gems and glass parts glass, meat flesh) and `NetProp.get_surface()`.
  - 2.5: impact damage. The PC running a prop reports a hit on an enemy or player it was slowed by (`PropSpawner.report_hit`); the host checks owner, distance, cooldown and caps, then applies damage = `impact_damage_scale` x half the prop's mass x speed lost squared / the victim's impact mass (`PropSpawner.impact_damage`, `impact_mass_of`; NEW `EnemyData.impact_mass`, `BossData.impact_mass`, `Enemy.get_impact_mass()`, `player_impact_mass` 85, metadata "impact_mass" on anything else). Props under `impact_min_mass` (2 kg) never hurt; small ones are capped; teammates take `friendly_physics_damage_scale` (0.25). The last player to let go within `physics_attacker_window` (2 s) gets the credit (`NetProp.get_recent_thrower`). Held props never hurt. NEW signal `prop_hit` (host).
  - 2.6: breakables. NEW `PropData.health` (0 = never breaks), `break_pieces`, `break_scene`. Hard knocks wear a breakable prop down (`prop_self_damage_scale`; `PropSpawner.report_wear`, host-only `NetProp.health_left`); at 0 it breaks for everyone: each PC makes its own cosmetic pieces (NEW `PropDebris`, layer DEBRIS, only hits the world) that shrink away after `gib_lifetime`, at most `max_gibs`. The crate (`prop_crate`) now has 60 health (about three hard throws). Fragile props still shatter as before, with pieces now. NEW signal `prop_broken`.
  - 2.7: `NetProp.own_hit_damage` (thrown inventory items use their own damage, so impact damage skips them).
  - Tests: 57 in `test_props.gd`. The feel playtest level has a prop yard and targets.
- 2026-10-29 (Zachary's step 2 playtest): (1) "prop flying" (jump off a box, grab it mid-air, land on it, repeat) is blocked: nobody can grab a prop under any player's feet down to NEW `no_grab_below_depth` (1.2 m), even mid-jump (NEW `PropSpawner.is_under_a_player(prop)`, used by the host's grab rules and the grab prompt). (2) Looking down while carrying no longer shoves you backwards: the hold point always stays NEW `hold_body_clearance` (0.1 m) outside your own body. (3) Crates broke too easily: sideways hits only wear a prop down from NEW `prop_wear_min_speed` (5 m/s; a throw into a wall is about 7), and landings only from NEW `prop_wear_min_fall_speed` (9 m/s, a fall of about 2.7 m), so dropping a crate from head height is harmless (`NetProp.wear_speed_of`). Wear never counts more than the speed the prop really lost, so a crate that glances off an enemy still hurts it instead of smashing first.
- 2026-10-30 (HL2 feel step 3.3): every prop knock is also a noise enemies hear (`EventBus.noise_made`, on the host), carrying 3 m for a soft bump up to 15 m for a hard hit (`Config.feel.ai.noise_prop_quietest` / `noise_prop_loudest`).
- 2026-10-30 (fix): a hit that takes a few physics steps to stop a prop counts as one hit. For NEW `NetProp.HIT_GATHER_STEPS` (3) steps after a hit, the prop keeps reporting how much speed it has lost since just before the hit (so a bounce is not counted twice), and within `impact_report_cooldown` the host deals only the extra damage (it remembers what each hit dealt). A thrown crate sometimes did a quarter of its damage when its stop was split over two steps.
- 2026-10-30 (HL2 feel step 4.3): the punt. NEW `PropPunter` (`prop_punter.gd`), PropSpawner `punt_strength`, `request_punt`, `decide_punt`, `prop_punted` and `REFUSE_NO_PUNT_ARM` / `REFUSE_TOO_SOON` / `REFUSE_HELD` / `REFUSE_ATTACHED`, NetProp `punt_now` and `mark_launched_by`, PropTuning "Punt" group (`punt_range` 6.35, `punt_cooldown` 0.5, `punt_speed` 15, `punt_light_bonus` 5, `punt_light_mass` 5, `punt_max_impulse` 600, `punt_floor_lift` 0.2, `punt_cone_dot` 0.97), PropSpawner `punt_direction`. CHANGED: `_impulse_rpc` wakes a sleeping prop before pushing it. 7 GUT tests (`test_punt.gd`). Same day, Zachary's ideas: punting an enemy shoves it and never hurts it (`punt_enemy_impulse` 150, `punt_enemy_max_speed` 10, `punt_enemy_lift` 3; `REFUSE_DEAD`); holding E pulls far props in like a magnet and the arm reaches 1.5 m further (`pull_range` 8, `pull_speed` 10, `pull_acceleration` 40, `pull_grab_bonus` 1.5, `pull_tumble` 0.5; `REFUSE_TOO_HEAVY`; after Zachary's playtest it drags and tumbles instead of floating, and reaches 8 m, not 15). FIX: `InteractionController` forgets a target that was removed between physics steps, so pressing E right then no longer errors (`test_pressing_use_right_after_the_target_is_removed_is_safe`). GrabController and the host's grab check use `grab_reach_of`. 13 GUT tests in `test_punt.gd`.

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
